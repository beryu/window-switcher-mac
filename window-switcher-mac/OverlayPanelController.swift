import AppKit
import SwiftUI

/// Manages NSPanel overlays that display above all windows on all screens
final class OverlayPanelController {
    private var panels: [NSPanel] = []
    private var hostingViews: [NSPanel: NSHostingView<AnyView>] = [:]
    
    init() {
        // Monitor screen changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Shows the overlay panels with content provided by the factory closure
    /// The closure receives the Global display bounds (AX coordinates) for the screen
    func showOverlay(viewFactory: @escaping (CGRect) -> some View) {
        if panels.isEmpty {
            createPanels()
        }
        
        for panel in panels {
            guard let screen = panel.screen else { continue }
            // Get the AX Frame (Global AX Coordinates) for this screen
            let axFrame = getAXFrame(for: screen)
            
            // Generate view for this specific screen
            let content = viewFactory(axFrame)
            
            let hostingView = NSHostingView(rootView: AnyView(content))
            hostingView.frame = panel.contentView?.bounds ?? .zero
            hostingView.autoresizingMask = [.width, .height]
            
            panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
            panel.contentView?.addSubview(hostingView)
            
            hostingViews[panel] = hostingView
            
            panel.orderFrontRegardless()
        }
    }
    
    /// Hides all overlay panels
    func hideOverlay() {
        panels.forEach { $0.orderOut(nil) }
    }
    
    /// Returns true if any overlay is currently visible
    var isVisible: Bool {
        panels.contains { $0.isVisible }
    }
    
    /// Sets whether the overlays ignore mouse events (click-through)
    func setIgnoresMouseEvents(_ ignores: Bool) {
        panels.forEach { $0.ignoresMouseEvents = ignores }
    }
    
    // MARK: - Private
    
    @objc private func screenParametersDidChange() {
        // When screens change, we should probably reset everything.
        // If overlays are visible, we might lose them until next activation.
        // For robustness, we close existing panels so they don't linger in invalid positions.
        panels.forEach { $0.close() }
        panels.removeAll()
        hostingViews.removeAll()
    }

    private func createPanels() {
        panels.forEach { $0.close() }
        panels.removeAll()
        
        for screen in NSScreen.screens {
            let panel = createPanel(for: screen)
            panels.append(panel)
        }
    }
    
    private func createPanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Critical settings for always-on-top behavior
        panel.level = .screenSaver  // Above all other windows
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        
        // Panel-specific behavior
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        
        // Allow mouse events to pass through transparent areas
        panel.ignoresMouseEvents = false
        
        return panel
    }
    
    private func getAXFrame(for screen: NSScreen) -> CGRect {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return screen.frame // Fallback, though likely incorrect coordinate system
        }
        return CGDisplayBounds(screenNumber)
    }
}
