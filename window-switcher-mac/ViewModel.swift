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
    @Published var focused: Bool = false
    
    var previouslyActiveApp: NSRunningApplication? = nil
    private let overlayController: OverlayPanelController
    
    // Using nonisolated(unsafe) because GlobalHotKeyManager uses Carbon APIs that work on any thread
    // and we dispatch back to main thread in the callback
    nonisolated(unsafe) private var hotKeyManager: GlobalHotKeyManager?
    
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
        // Using native CGEvent tap for global hotkey
        // NOTE: NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) will fail to focus this app
        // NOTE: Command+Escape is reserved by macOS for Force Quit, so we use Control+Escape instead
        hotKeyManager = GlobalHotKeyManager.controlEscape { [weak self] in
            Task { @MainActor in
                if let prevActiveApp = NSWorkspace.shared.runningApplications.first(where: {
                    $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                }) {
                    self?.previouslyActiveApp = prevActiveApp
                }
                self?.refreshAppWindows()
                self?.show()
            }
        }
        
        if hotKeyManager == nil {
            print("Warning: Failed to register global hotkey Control+Escape")
        }
    }
    
    func checkPermission() {
        let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    /// Handle key press from global key capture
    func handleGlobalKeyPress(_ key: String) {
        guard let appWindow = appWindows.first(where: { $0.key == key }) else {
            return
        }
        focusApp(appWindow: appWindow)
        previouslyActiveApp = nil
        hide()
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
    }
    
    func hide() {
        // Disable global key capture
        hotKeyManager?.disableOverlayMode()
        
        Task { @MainActor in
            appWindows = []
            focused = false
        }
        overlayController.hideOverlay()
        previouslyActiveApp?.activate()
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
