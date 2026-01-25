import SwiftUI
import ServiceManagement

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
    private var openAtLoginMenuItem: NSMenuItem?
    
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
        
        // Open at Login toggle
        openAtLoginMenuItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        openAtLoginMenuItem?.target = self
        updateOpenAtLoginState()
        menu.addItem(openAtLoginMenuItem!)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit action
        let quitMenuItem = NSMenuItem(title: "Quit Window Switcher", action: #selector(quitApp), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)
        
        statusItem?.menu = menu
    }
    
    private func updateOpenAtLoginState() {
        let isEnabled = SMAppService.mainApp.status == .enabled
        openAtLoginMenuItem?.state = isEnabled ? .on : .off
    }
    
    @objc private func toggleOpenAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Failed to toggle Open at Login: \(error)")
        }
        updateOpenAtLoginState()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        overlayController?.hideOverlay()
    }
}
