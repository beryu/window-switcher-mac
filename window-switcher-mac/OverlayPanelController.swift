import AppKit
import SwiftUI

/// Manages an NSPanel overlay that displays above all windows
final class OverlayPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    
    /// Shows the overlay panel with the given SwiftUI content
    func showOverlay<Content: View>(with content: Content) {
        if panel == nil {
            createPanel()
        }
        
        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = panel?.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        
        panel?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        panel?.contentView?.addSubview(hostingView)
        self.hostingView = hostingView
        
        panel?.orderFrontRegardless()
    }
    
    /// Hides the overlay panel
    func hideOverlay() {
        panel?.orderOut(nil)
    }
    
    /// Updates the content of the overlay without recreating the panel
    func updateContent<Content: View>(with content: Content) {
        guard let hostingView = hostingView else {
            showOverlay(with: content)
            return
        }
        hostingView.rootView = AnyView(content)
    }
    
    /// Returns true if the overlay is currently visible
    var isVisible: Bool {
        panel?.isVisible ?? false
    }
    
    // MARK: - Private
    
    private func createPanel() {
        guard let screen = NSScreen.main else { return }
        
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
        
        self.panel = panel
    }
}
