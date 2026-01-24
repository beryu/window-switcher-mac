import ApplicationServices
import Foundation
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class ViewModel: ObservableObject {
    struct AppWindow {
        var uuid: UUID
        var pid: Int32
        var element: AXUIElement
        var overlayViewFrame: CGRect
        var name: String
        var key: String
        var image: NSImage?
    }
    
    @Published private(set) var appWindows: [AppWindow] = []
    @Published private(set) var uiElements: [UIElementModel] = []
    @Published var focused: Bool = false
    @Published var mode: Mode = .windowSwitcher
    
    enum Mode {
        case windowSwitcher
        case uiElement
        case scrollTargetSelection
        case scroll
    }
    
    var previouslyActiveApp: NSRunningApplication? = nil
    private let overlayController: OverlayPanelController
    private let uiElementScanner = UIElementScanner()
    private var scrollTargetLocation: CGPoint? = nil
    
    // Using nonisolated(unsafe) because GlobalHotKeyManager uses Carbon APIs that work on any thread
    // and we dispatch back to main thread in the callback
    nonisolated(unsafe) private var hotKeyManager: GlobalHotKeyManager?
    nonisolated(unsafe) private var uiElementHotKeyManager: GlobalHotKeyManager?
    nonisolated(unsafe) private var scrollHotKeyManager: GlobalHotKeyManager?
    
    private let keys: [String] = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    ]
    
    init(overlayController: OverlayPanelController) {
        self.overlayController = overlayController
        monitorHotKey()
    }
    
    func monitorHotKey() {
        // Window Switcher Mode: Control + Escape
        hotKeyManager = GlobalHotKeyManager.controlEscape { [weak self] in
            Task { @MainActor in
                if let prevActiveApp = NSWorkspace.shared.runningApplications.first(where: {
                    $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                }) {
                    self?.previouslyActiveApp = prevActiveApp
                }
                self?.mode = .windowSwitcher
                self?.refreshAppWindows()
                self?.show()
            }
        }
        
        // UI Element Mode: Option + Escape
        uiElementHotKeyManager = GlobalHotKeyManager.optionEscape { [weak self] in
             Task { @MainActor in
                 self?.startUIElementSelection()
             }
        }
        
        // Scroll Mode: Control + Option + Escape
        scrollHotKeyManager = GlobalHotKeyManager.controlOptionEscape { [weak self] in
            Task { @MainActor in
                self?.startScrollMode()
            }
        }
        
        if hotKeyManager == nil {
            print("Warning: Failed to register global hotkey Control+Escape")
        }
        if uiElementHotKeyManager == nil {
             print("Warning: Failed to register global hotkey Option+Escape")
        }
        if scrollHotKeyManager == nil {
            print("Warning: Failed to register global hotkey Control+Option+Escape")
        }
    }
    
    func checkPermission() {
        let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    @Published var inputBuffer: String = ""
    
    /// Handle key press from global key capture
    func handleGlobalKeyPress(_ key: String) {
        switch mode {
        case .windowSwitcher:
            guard let appWindow = appWindows.first(where: { $0.key == key }) else {
                return
            }
            focusApp(appWindow: appWindow)
            previouslyActiveApp = nil
            hide()
            
        case .uiElement:
            // Append key to buffer
            inputBuffer += key
            
            // Filter elements matching buffer
            let matchingElements = uiElements.filter { $0.label.starts(with: inputBuffer) }
            
            if matchingElements.isEmpty {
                // No match, reset buffer? Or keep it and show error?
                // For now, reset if no match found at all locally, but maybe better to just ignore?
                // If the user typed a wrong character, they might want to clear.
                // Let's reset buffer if invalid sequence
                inputBuffer = ""
                return
            }
            
            if matchingElements.count == 1, matchingElements.first?.label == inputBuffer {
                // Exact match and unique
                if let element = matchingElements.first {
                    clickUIElement(element)
                    // Note: hide() is called inside clickUIElement
                }
            }
            
        case .scrollTargetSelection:
             // Similar to uiElement logic but transitions to scroll mode
             inputBuffer += key
             let matchingElements = uiElements.filter { $0.label.starts(with: inputBuffer) }
             
             if matchingElements.isEmpty {
                 inputBuffer = ""
                 return
             }
             
             if matchingElements.count == 1, matchingElements.first?.label == inputBuffer {
                 if let element = matchingElements.first {
                     // Target selected
                     let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
                     transitionToScrollMode(targetCenter: center)
                 }
             }
             
        case .scroll:
            let scrollAmount: Int32 = 50
            switch key {
            case "h": // Left
                performScroll(deltaX: scrollAmount, deltaY: 0)
            case "j": // Down
                performScroll(deltaX: 0, deltaY: -scrollAmount)
            case "k": // Up
                performScroll(deltaX: 0, deltaY: scrollAmount)
            case "l": // Right
                performScroll(deltaX: -scrollAmount, deltaY: 0)
            default:
                break
            }
        }
    }
    
    func show() {
        checkPermission()
        
        let contentView = OverlayContentView(viewModel: self)
        overlayController.showOverlay(with: contentView)
        
        Task { @MainActor in
            focused = true
        }
        
        // Enable global key capture during overlay display
        hotKeyManager?.enableOverlayMode(
            keyHandler: { [weak self] key in
                Task { @MainActor in
                    self?.handleGlobalKeyPress(key)
                }
            },
            escapeHandler: { [weak self] in
                Task { @MainActor in
                    self?.hide()
                }
            }
        )
        
        // Configure overlay interaction based on mode
        if mode == .scroll {
             overlayController.setIgnoresMouseEvents(true)
        } else {
             overlayController.setIgnoresMouseEvents(false)
        }
    }
    
    func hide() {
        // Disable global key capture
        hotKeyManager?.disableOverlayMode()
        
        Task { @MainActor in
            appWindows = []
            uiElements = []
            inputBuffer = ""
            focused = false
        }
        overlayController.hideOverlay()
        
        // Only reactivate previous app if we didn't just switch to it or click an element
        // But for window switcher logic, we usually want to activate the target.
        // If we just hid the overlay without selection, we might want to restore focus.
        if let prev = previouslyActiveApp, prev.isActive == false {
             prev.activate()
        }
        previouslyActiveApp = nil
    }
    
    func refreshAppWindows() {
        let type = CGWindowListOption.optionOnScreenOnly
        let windowList = CGWindowListCopyWindowInfo(type, kCGNullWindowID) as NSArray? as? [[String: AnyObject]]
        
        var appWindows: [AppWindow] = []
        for entry in windowList ?? [] {
            guard
                let owner = entry[kCGWindowOwnerName as String] as? String,
                let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                !appWindows.contains(where: { $0.pid == pid })
            else {
                continue
            }
            
            let appRef = AXUIElementCreateApplication(pid);
            
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
            if result != .success {
                continue
            }
            
            guard let windowList = value as? [AXUIElement] else {
                continue
            }
            
            let iconImage: NSImage?
            if let app = NSRunningApplication(processIdentifier: pid) {
                iconImage = app.icon
            } else {
                iconImage = nil
            }
            
            for element in windowList {
                var pid: pid_t = 0
                let result = AXUIElementGetPid(element, &pid)
                if result != .success {
                    fatalError("AXUIElementGetPid is failed with \(result.rawValue)")
                }
                
                guard
                    owner != "window-switcher-mac",
                    let position = element.getOrigin(),
                    let size = element.getSize()
                else {
                    continue
                }
                if owner == "Finder" && size == NSScreen.main?.frame.size {
                    // Don't include Finder which don't has window
                    continue
                }
                appWindows.append(.init(
                    uuid: UUID(),
                    pid: pid,
                    element: element,
                    overlayViewFrame: CGRect(
                        origin: CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2),
                        size: CGSize(width: 150, height: 150)
                    ),
                    name: owner,
                    key: keys[appWindows.count],
                    image: iconImage
                ))
                if appWindows.count >= keys.count {
                    break
                }
            }
            
            // Modify position of overlapping overlayViewFrames
            var i = 0
            let margin: CGFloat = 10
            while i < appWindows.count {
                let originalOverlayViewFrame = appWindows[i].overlayViewFrame
                var j = i + 1
                while j < appWindows.count {
                    if appWindows[i].overlayViewFrame.intersects(appWindows[j].overlayViewFrame) {
                        appWindows[j].overlayViewFrame = CGRect(
                            origin: CGPoint(
                                x: appWindows[i].overlayViewFrame.origin.x + appWindows[j].overlayViewFrame.size.width + margin,
                                y: appWindows[j].overlayViewFrame.origin.y
                            ),
                            size: originalOverlayViewFrame.size
                        )
                    }
                    j += 1
                }
                i += 1
            }
        }
        self.appWindows = appWindows
    }
    
    // MARK: - Scroll Mode Actions
    
    func startScrollMode() {
        guard let prevActiveApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }) else {
            return
        }
        self.previouslyActiveApp = prevActiveApp
        
        // Scan for scrollable elements
        let scrollableElements = uiElementScanner.scanScrollableElements()
        
        if scrollableElements.isEmpty {
            // No specific scrollable elements found, fallback to window center
            if let pid = previouslyActiveApp?.processIdentifier,
               let frame = uiElementScanner.getFocusedWindowFrame(pid: pid) {
                let center = CGPoint(x: frame.midX, y: frame.midY)
                transitionToScrollMode(targetCenter: center)
            } else {
                // Total fallback (mouse position)
                transitionToScrollMode(targetCenter: nil)
            }
        } else if scrollableElements.count == 1 {
            // Only one scrollable element, select it automatically
            let element = scrollableElements[0]
            let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
            transitionToScrollMode(targetCenter: center)
        } else {
            // Multiple elements, ask user to select
            mode = .scrollTargetSelection
            inputBuffer = ""
            uiElements = scrollableElements
            scrollTargetLocation = nil
            show()
        }
    }
    
    private func transitionToScrollMode(targetCenter: CGPoint?) {
        scrollTargetLocation = targetCenter
        mode = .scroll
        inputBuffer = ""
        uiElements = [] // Clear labels
        show() // Re-configure overlay for scroll mode (transparency)
    }
    
    private func performScroll(deltaX: Int32, deltaY: Int32) {
        // Create scroll wheel event
        // Note: wheelCount=2 means we are providing Y (wheel1) and X (wheel2) deltas
        // Units: .pixel gives smoother control, .line gives larger steps
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0) else {
            print("Failed to create scroll event")
            return
        }
        
        // IMPORTANT: Must set the location to valid point in the target window.
        // We assume the target is the previously active app's focused window.
        // If we can get its frame, we target the center.
        // Otherwise fallback to mouse or (0,0) (which fails).
        
        if let target = scrollTargetLocation {
            event.location = target
        } else if let pid = previouslyActiveApp?.processIdentifier, // Fallback re-check
                  let frame = uiElementScanner.getFocusedWindowFrame(pid: pid) {
             event.location = CGPoint(x: frame.midX, y: frame.midY)
        } else if let currentEvent = CGEvent(source: nil) {
            event.location = currentEvent.location
        }
        
        // We rely on ignoresMouseEvents = true on the overlay panel so the event passes through
        event.post(tap: .cghidEventTap)
        print("Performed scroll: X=\(deltaX), Y=\(deltaY) at \(event.location)")
    }
    
    // MARK: - UI Element Actions
    
    func startUIElementSelection() {
        guard let prevActiveApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }) else {
            return
        }
        self.previouslyActiveApp = prevActiveApp
        
        mode = .uiElement
        inputBuffer = ""
        uiElements = uiElementScanner.scanFrontmostWindow()
        show()
    }
    
    private func clickUIElement(_ element: UIElementModel) {
        print("Clicking element: \(element.label) - \(element.displayName)")
        
        // Hide overlay first to activate the target app
        hide()
        
        Task {
            // Wait for window activation to complete
            // Increased delay to ensure app is ready to receive events
            try? await Task.sleep(nanoseconds: 300 * 1_000_000) // 300ms
            
            // Try Accessibility API first
            if element.element.performClick() {
                print("AXPerformAction dispatched")
            }
            
            // Fallback / Ensure click: Mouse simulation
            // We use await here to ensure the hold time is respected
            await performMouseClick(at: CGPoint(x: element.frame.midX, y: element.frame.midY))
        }
    }
    
    private func performMouseClick(at point: CGPoint) async {
        // Save current mouse position
        let originalPosition = CGEvent(source: nil)?.location ?? point
        
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
              let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        
        // Post events
        // Move mouse to target
        move.post(tap: .cghidEventTap)
        
        // Click
        down.post(tap: .cghidEventTap)
        
        // Verify click duration: Hold for a short duration to ensure it registers
        try? await Task.sleep(nanoseconds: 50 * 1_000_000) // 50ms hold
        
        up.post(tap: .cghidEventTap)
        
        // Restore mouse position
        // Let's move it back after a short delay so user sees where it clicked
        try? await Task.sleep(nanoseconds: 150 * 1_000_000)
        if let restore = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: originalPosition, mouseButton: .left) {
            restore.post(tap: .cghidEventTap)
        }
        
        print("Mouse click simulated at \(point)")
    }

    private func focusApp(appWindow: AppWindow) {
        var pid: pid_t = 0
        var result = AXUIElementGetPid(appWindow.element, &pid)
        if result != .success {
            print("focusApp: AXUIElementGetPid failed with \(result.rawValue)")
            return
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            print("focusApp: NSRunningApplication(processIdentifier:) failed for pid \(pid)")
            return
        }
        if !app.activate() {
            print("focusApp: app.activate() failed for \(app.localizedName ?? "unknown app")")
            // Still try to set the main attribute even if activate failed
        }
        result = AXUIElementSetAttributeValue(appWindow.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if result != .success {
            print("focusApp: AXUIElementSetAttributeValue failed with \(result.rawValue)")
        }
    }
}
