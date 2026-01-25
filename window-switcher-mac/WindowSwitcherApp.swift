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
    private var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon since this is an overlay-only app
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize overlay system
        overlayController = OverlayPanelController()
        viewModel = ViewModel(overlayController: overlayController!)
        
        // Setup menu bar status item
        setupStatusBarItem()
    }
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Window Switcher")
        }
        
        let menu = NSMenu()
        
        // Status indicator (disabled, just for display)
        let statusMenuItem = NSMenuItem(title: "Window Switcher (Running)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit action
        let quitMenuItem = NSMenuItem(title: "Quit Window Switcher", action: #selector(quitApp), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        overlayController?.hideOverlay()
    }
}
