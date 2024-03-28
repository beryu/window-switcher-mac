import ApplicationServices
import Foundation
import SwiftUI
import Carbon.HIToolbox
import HotKey

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

  @Published var window: NSWindow?
  @Published var focused: Bool = false
  var previouslyActiveApp: NSRunningApplication? = nil
  private var hotKey: HotKey?
  private(set) var appWindows: [AppWindow] = []
  private let keys: [String] = [
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
  ]
  
  init() {
    monitorActiveOrInactive()
    monitorHotKey()
  }
  
  func monitorActiveOrInactive() {
    NotificationCenter.default.addObserver(self, selector: #selector(becomeActive), name: NSApplication.willBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(becomeInactive), name: NSApplication.willResignActiveNotification, object: nil)
  }
  
  @objc
  func becomeActive() {
    refreshAppWindows()
    show()
  }
  
  @objc
  func becomeInactive() {
    hide()
  }

  func monitorHotKey() {
    // NOTE: NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) will fail to focus this app
    hotKey = HotKey(key: .escape, modifiers: [.command], keyDownHandler: { [weak self] in
      if let prevActiveApp = NSWorkspace.shared.runningApplications.first(where: {
        $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier
      }) {
        self?.previouslyActiveApp = prevActiveApp
      }
      self?.refreshAppWindows()
      self?.show()
      NSApp.activate()
    })
  }
  
  func checkPermission() {
    let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
    let options = [trustedCheckOptionPrompt: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
  
  func onKeyPress(_ press: KeyPress) -> KeyPress.Result {
    // hide when escape pressed
    if press.characters == "\u{1B}" {
      hide()
      return .handled
    }
    guard let appWindow = appWindows.first(where: { $0.key == press.characters }) else {
      return .ignored
    }
    focusApp(appWindow: appWindow)
    previouslyActiveApp = nil
    hide()

    return .handled
  }

  func show() {
    window?.orderFront(nil)
    // DispatchQueue.main.async is for workaround of below's warning:
    // "Publishing changes from within view updates is not allowed, this will cause undefined behavior."
    DispatchQueue.main.async { [weak self] in
      self?.focused = true
    }
  }

  func hide() {
    window?.orderOut(nil)
    previouslyActiveApp?.activate()
    previouslyActiveApp = nil
    // DispatchQueue.main.async is for workaround of below's warning:
    // "Publishing changes from within view updates is not allowed, this will cause undefined behavior."
    DispatchQueue.main.async { [weak self] in
      self?.focused = false
    }
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
      fatalError("AXUIElementGetPid is failed with \(result.rawValue)")
    }
    guard let app = NSRunningApplication(processIdentifier: pid) else {
      fatalError("NSRunningApplication(processIdentifier:) is failed")
    }
    if !app.activate() {
      fatalError("app.activate(options:) is failed")
    }
    result = AXUIElementSetAttributeValue(appWindow.element, kAXMainAttribute as CFString, kCFBooleanTrue)
    if result != .success {
      print("Set kAXFocusedAttribute with AXUIElementSetAttributeValue is failed with \(result.rawValue)...")
    }
  }
}
