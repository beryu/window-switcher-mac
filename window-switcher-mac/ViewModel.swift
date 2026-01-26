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
        var matchableName: String
        var key: String
        var image: NSImage?
    }
    
    @Published private(set) var appWindows: [AppWindow] = []
    private var allAppWindows: [AppWindow] = []
    @Published private(set) var uiElements: [UIElementModel] = []
    @Published private(set) var clusters: [ClusterModel] = []
    @Published private(set) var isolatedElements: [UIElementModel] = []
    @Published var selectedCluster: ClusterModel? = nil
    @Published var windowScreenshot: NSImage? = nil  // Screenshot of the target window
    @Published var windowFrame: CGRect = .zero  // Frame of the target window in screen coordinates
    @Published var focused: Bool = false
    @Published var mode: Mode = .windowSwitcher
    @Published var uiElementSubMode: UIElementSubMode = .clusterSelection
    
    enum Mode {
        case windowSwitcher
        case uiElement
        case scrollTargetSelection
        case scroll
    }
    
    enum UIElementSubMode {
        case clusterSelection  // First phase: select cluster or isolated element
        case elementSelection  // Second phase: select element within cluster
    }
    

    
    /// Minimum target size for zoom (ensure elements are spread enough)
    private static let minZoomedClusterSize: CGFloat = 400
    
    /// Computed zoom scale for the selected cluster
    var zoomScale: CGFloat {
        guard let cluster = selectedCluster else { return 1.0 }
        let clusterWidth = cluster.boundingFrame.width
        let clusterHeight = cluster.boundingFrame.height
        
        guard clusterWidth > 0, clusterHeight > 0 else { return 1.0 }
        
        // Base scale calculation
        let maxDim = max(clusterWidth, clusterHeight)
        let targetScale = Self.minZoomedClusterSize / maxDim
        
        // Check screen bounds to prevent overflow
        // Check screen bounds to prevent overflow
        // Use visible frame if possible, fallback to main screen
        var screenSize = CGSize(width: 1440, height: 900)
        
        // Find screen containing the cluster center
        let center = cluster.center
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                let bounds = CGDisplayBounds(id)
                if bounds.contains(center) {
                    screenSize = bounds.size
                    break
                }
            }
        }
        
        // Calculate max allowed scale such that:
        // dimension * scale <= screenSize * 0.9 (90% of screen)
        let maxScaleX = (screenSize.width * 0.9) / clusterWidth
        let maxScaleY = (screenSize.height * 0.9) / clusterHeight
        let maxAllowedScale = min(maxScaleX, maxScaleY)
        
        // Final scale: at least 1.5x, up to 5.0x, but capped by screen fit
        let finalScale = min(max(targetScale, 1.5), 5.0)
        
        return min(finalScale, maxAllowedScale)
    }
    
    /// Computed zoom center for the selected cluster
    var zoomCenter: CGPoint {
        guard let cluster = selectedCluster else { return .zero }
        return cluster.center
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
        
        // UI Element Mode: Control + Option + Escape
        uiElementHotKeyManager = GlobalHotKeyManager.controlOptionEscape { [weak self] in
             Task { @MainActor in
                 self?.startUIElementSelection()
             }
        }
        
        // Scroll Mode: Option + Escape
        scrollHotKeyManager = GlobalHotKeyManager.optionEscape { [weak self] in
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
            // Check for direct key match first (Handles selected keys like A, B, C or 1, 2, 3)
            // We check this BEFORE filtering to allow selection of available choices
            // IMPORTANT: Only select if there is a UNIQUE match. If multiple windows share the key (e.g. prefix matches), we should filter.
            let keyMatches = appWindows.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }
            if keyMatches.count == 1 {
                focusApp(appWindow: keyMatches[0])
                previouslyActiveApp = nil
                hide()
                return
            }
            
            // Append to buffer to check for matches
            let nextBuffer = inputBuffer + key.lowercased()
            let matches = allAppWindows.filter { $0.matchableName.starts(with: nextBuffer) }
            
            if matches.isEmpty {
                // Ignore invalid input
                return
            }
            
            inputBuffer = nextBuffer
            assignHotKeys()
            
            // Auto-activate if only one match
            if appWindows.count == 1 {
                focusApp(appWindow: appWindows[0])
                previouslyActiveApp = nil
                hide()
            }
            
        case .uiElement:
            switch uiElementSubMode {
            case .clusterSelection:
                // Phase 1: Select a cluster or isolated element
                let upperKey = key.uppercased()
                
                // Check if key matches a cluster
                if let cluster = clusters.first(where: { $0.label == upperKey }) {
                    // Transition to element selection within this cluster
                    selectedCluster = cluster
                    uiElementSubMode = .elementSelection
                    inputBuffer = ""
                    
                    // Re-assign labels to the cluster's elements
                    var elementsToLabel = cluster.elements
                    uiElementScanner.assignLabelsToElements(&elementsToLabel)
                    uiElements = elementsToLabel
                    return
                }
                
                // Check if key matches an isolated element
                // Instead of immediate match, append to buffer and check uniqueness
                let lowerKey = key.lowercased()
                
                // Try prefix matching for isolated elements
                inputBuffer += lowerKey
                let matchingIsolated = isolatedElements.filter { $0.label.starts(with: inputBuffer) }
                
                if matchingIsolated.isEmpty {
                    inputBuffer = ""
                    return
                }
                
                if matchingIsolated.count == 1, matchingIsolated.first?.label == inputBuffer {
                    if let element = matchingIsolated.first {
                        clickUIElement(element)
                    }
                }
                
            case .elementSelection:
                // Phase 2: Select element within the selected cluster
                if key == "\n" {
                    if let element = uiElements.first(where: { $0.label == inputBuffer }) {
                        clickUIElement(element)
                        return
                    }
                }
                
                inputBuffer += key.lowercased()
                let matchingElements = uiElements.filter { $0.label.starts(with: inputBuffer) }
                
                if matchingElements.isEmpty {
                    inputBuffer = ""
                    return
                }
                
                if matchingElements.count == 1, matchingElements.first?.label == inputBuffer {
                    if let element = matchingElements.first {
                        clickUIElement(element)
                    }
                }
            }
            
            
            
            case .scrollTargetSelection:
                 // Similar to uiElement logic but transitions to scroll mode
                 if key == "\n" {
                     if let element = uiElements.first(where: { $0.label == inputBuffer }) {
                         let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
                         transitionToScrollMode(targetCenter: center)
                         return
                     }
                 }

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
        
        overlayController.showOverlay { screenFrame in
            OverlayContentView(viewModel: self, screenFrame: screenFrame)
        }
        
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
            clusters = []
            isolatedElements = []
            selectedCluster = nil
            uiElementSubMode = .clusterSelection
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
        
        var newAppWindows: [AppWindow] = []
        for entry in windowList ?? [] {
            guard
                let owner = entry[kCGWindowOwnerName as String] as? String,
                let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                !newAppWindows.contains(where: { $0.pid == pid })
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
                    print("AXUIElementGetPid is failed with \(result.rawValue)")
                    continue
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
                newAppWindows.append(.init(
                    uuid: UUID(),
                    pid: pid,
                    element: element,
                    overlayViewFrame: CGRect(
                        origin: CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2),
                        size: CGSize(width: 150, height: 150)
                    ),
                    name: owner,
                    matchableName: owner.lowercased().replacingOccurrences(of: " ", with: ""),
                    key: "", // will be assigned
                    image: iconImage
                ))
            }
        }
        
        self.allAppWindows = newAppWindows
        self.inputBuffer = ""
        assignHotKeys()
    }
    
    private func assignHotKeys() {
        let filtered: [AppWindow]
        if inputBuffer.isEmpty {
            filtered = allAppWindows
        } else {
            filtered = allAppWindows.filter { $0.matchableName.starts(with: inputBuffer) }
        }
        
        var resultWindows = filtered
        
        // Check if all filtered windows belong to the same app name
        let uniqueNames = Set(resultWindows.map { $0.matchableName })
        let isUniqueNameGroup = uniqueNames.count == 1
        
        var reservedKeys: Set<String> = []
        var exactMatchIndices: [Int] = []
        
        // First pass: Identify prefix matches and reserve their keys
        for i in 0..<resultWindows.count {
            let name = resultWindows[i].matchableName
            
            if isUniqueNameGroup || name == inputBuffer {
                // Will be assigned an index key later
                exactMatchIndices.append(i)
            } else {
                // Prefix match case
                if inputBuffer.count < name.count {
                    let index = name.index(name.startIndex, offsetBy: inputBuffer.count)
                    let key = String(name[index]).uppercased()
                    resultWindows[i].key = key
                    reservedKeys.insert(key)
                } else {
                    resultWindows[i].key = "?"
                }
            }
        }
        
        // Second pass: Assign index keys (A-Z) to exact matches, skipping reserved keys
        var currentOffset = 0
        
        // Group exact matches by name to reset counter for different names (if any, though isUniqueNameGroup makes this simpler)
        // If not unique group but exact match (e.g. "App" match, "App" match, "Apple" prefix)
        // We want to number the "App"s.
        // Actually, previous logic numbered *by name*.
        // "App" #1, "App" #2.
        // "Apple" -> 'L'.
        // If we switch to A-Z, we should probably share the pool or per-name?
        // User said: "Use A-start alphabets instead of numbers".
        // Current logic:
        // "App" #1 -> A
        // "App" #2 -> B
        // "Apple" -> L
        // If L is used, skip it.
        
        // We need to track assignment for each exact match group?
        // Actually, just iterating through exactMatchIndices is fine if we just want unique keys.
        // But previously we tracked `exactMatchIndices` map to reset count?
        // With A-Z, uniqueness across the board is safer? Or just per name?
        // If I have "App" x2 and "Bat" x2. Input empty.
        // "App" (A), "App" (B). "Bat" (B), "Bat" (A).
        // Conflict A and B.
        // But `assignHotKeys` assumes we filtered by name prefixes.
        // If empty input: Keys are First Letter. A, B.
        // "App" -> A. "Bat" -> B.
        // My logic above replaces keys entirely.
        // If `inputBuffer` is empty, logic uses first char.
        // `name.index(..., offsetBy: 0)` -> first char.
        // So `reservedKeys` will have "A", "B".
        // `exactMatchIndices` will coincide?
        // `inputBuffer` "A". "App" matches "App" (prefix).
        // Wait, "App" vs "Apple".
        // If "App" is exact match? No, inputBuffer="A". "App" is prefix match "p".
        // Logic covers this.
        // Only when name == inputBuffer OR isUniqueNameGroup do we fall into "Exact Match".
        
        // So we just need to assign keys for the indices we collected.
        // We should use a single sequence A, B, C... for ALL items needing an index?
        // Or per name group?
        // If "App" and "Bob" (both somehow exact match? Impossible unless inputBuffer matches both, which implies same name).
        // So really only one name group can be "Exact Match" at a time.
        // OR `isUniqueNameGroup` is true -> multiple windows, same name.
        // So a single counter is sufficient.
        
        for i in exactMatchIndices {
            // Find next available char
            while true {
                 // 0 -> A, 1 -> B
                 // Check bounds?
                 if currentOffset > 25 {
                     // Fallback to numbers if we run out of letters?
                     // Or double letters? Let's use numbers after Z.
                     let numIndex = currentOffset - 26 + 1
                     let key = "\(numIndex)"
                     if !reservedKeys.contains(key) {
                         resultWindows[i].key = key
                         reservedKeys.insert(key)
                         currentOffset += 1
                         break
                     }
                 } else {
                     let scalar = UnicodeScalar(65 + currentOffset)! // A=65
                     let key = String(scalar)
                     if !reservedKeys.contains(key) {
                         resultWindows[i].key = key
                         reservedKeys.insert(key)
                         currentOffset += 1
                         break
                     }
                 }
                 currentOffset += 1
            }
        }
        
        self.appWindows = resolveOverlaps(windows: resultWindows)
    }
    
    private func resolveOverlaps(windows: [AppWindow]) -> [AppWindow] {
        var windows = windows
        var i = 0
        let margin: CGFloat = 10
        while i < windows.count {
            let originalOverlayViewFrame = windows[i].overlayViewFrame
            var j = i + 1
            while j < windows.count {
                if windows[i].overlayViewFrame.intersects(windows[j].overlayViewFrame) {
                    windows[j].overlayViewFrame = CGRect(
                        origin: CGPoint(
                            x: windows[i].overlayViewFrame.origin.x + windows[j].overlayViewFrame.size.width + margin,
                            y: windows[j].overlayViewFrame.origin.y
                        ),
                        size: originalOverlayViewFrame.size
                    )
                }
                j += 1
            }
            i += 1
        }
        return windows
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
        
        // Reset state
        mode = .uiElement
        uiElementSubMode = .clusterSelection
        inputBuffer = ""
        selectedCluster = nil
        windowScreenshot = nil
        windowFrame = .zero
        
        // Start screenshot capture asynchronously
        // We do this immediately so it might be ready when user selects a cluster
        let pid = prevActiveApp.processIdentifier
        Task {
            // Find window ID first (we need UIElementScanner to get the window ID from accessibility element)
            // Or we can let ScreenRecorder find the main window for the app?
            // Actually, best to get the ID from our scanner since we know which window is focused.
            
            // Get focused window frame and ID
            if let windowInfo = uiElementScanner.getFocusedWindowInfo(pid: pid) {
                let windowID = windowInfo.id
                let frame = windowInfo.frame
                
                // Update frame immediately
                await MainActor.run {
                    self.windowFrame = frame
                }
                
                // Capture
                if let image = try? await ScreenRecorder.captureWindow(windowID: windowID) {
                    await MainActor.run {
                        self.windowScreenshot = image
                    }
                }
            }
        }
        
        // Scan all elements
        // Note: This matches the "focused window" that we are capturing
        let allElements = uiElementScanner.scanFrontmostWindow()
        
        // Cluster elements
        let (foundClusters, foundIsolated) = uiElementScanner.clusterElements(elements: allElements)
        
        clusters = foundClusters
        isolatedElements = foundIsolated
        uiElements = allElements  // Keep for reference
        
        show()
    }
    
    /*
    /// Capture a screenshot of the specified application's focused window
    /// Returns the image and the window frame in screen coordinates
    private func captureWindowScreenshot(pid: pid_t) -> (image: NSImage, frame: CGRect)? {
        // Get window list for the specified process
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        // Find windows belonging to the target process
        let targetWindows = windowList.filter { info in
            guard let windowPID = info[kCGWindowOwnerPID as String] as? Int32 else { return false }
            return windowPID == pid
        }
        
        // Get the frontmost window (first in the list for this app)
        guard let windowInfo = targetWindows.first,
              let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
            print("captureWindowScreenshot: No window found for pid \(pid)")
            return nil
        }
        
        // Get window bounds (in screen coordinates with top-left origin)
        var windowBounds: CGRect = .zero
        if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
           let x = boundsDict["X"] as? CGFloat,
           let y = boundsDict["Y"] as? CGFloat,
           let width = boundsDict["Width"] as? CGFloat,
           let height = boundsDict["Height"] as? CGFloat {
            // CGWindowBounds uses top-left origin
            windowBounds = CGRect(x: x, y: y, width: width, height: height)
            print("captureWindowScreenshot: Window bounds (CG top-left): \(windowBounds)")
        }
        
        // Capture the window image
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            print("captureWindowScreenshot: Failed to capture window image")
            return nil
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        print("captureWindowScreenshot: Captured \(cgImage.width)x\(cgImage.height) image")
        return (nsImage, windowBounds)
    }
    */
    
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
