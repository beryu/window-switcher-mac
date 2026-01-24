import SwiftUI

@main
struct WindowSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty Settings scene to keep app running without visible window
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: ViewModel?
    private var overlayController: OverlayPanelController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon since this is an overlay-only app
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize overlay system
        overlayController = OverlayPanelController()
        viewModel = ViewModel(overlayController: overlayController!)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        overlayController?.hideOverlay()
    }
}
