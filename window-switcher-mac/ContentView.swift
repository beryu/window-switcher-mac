//
//  ContentView.swift
//  window-switcher-mac
//
//  Created by 岐部龍太 on 2024/03/24.
//

import SwiftUI

struct ContentView: View {
  struct AppWindow {
    var uuid: UUID
    var pid: Int32
    var element: AXUIElement
    var x: CGFloat
    var y: CGFloat
    var name: String
    var key: String
  }

  @Binding var window: NSWindow?
  @State var appWindows: [AppWindow] = []
  @State var shouldShow: Bool = false
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
  ]
  @FocusState private var focused: Bool

  var body: some View {
    ZStack {
      if shouldShow {
        ForEach(appWindows, id: \.uuid) { appWindow in
          VStack {
            Text(appWindow.key)
              .font(.system(size: 36, weight: .bold))
              .foregroundStyle(.primary)
            Text(appWindow.name)
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(.primary)
              .minimumScaleFactor(0.1)
          }
          .padding(8)
          .frame(width: 150, height: 150)
          .background(Color.black.opacity(0.8))
          .cornerRadius(10)
          .position(x: appWindow.x + 75, y: appWindow.y + 10)
        }
      }
    }
    .focusable()
    .focused($focused)
    .focusEffectDisabled()
    .onKeyPress { press in
      guard let appWindow = appWindows.first(where: { $0.key == press.characters }) else {
        return .ignored
      }
      focusApp(appWindow: appWindow)
      shouldShow = false

      return .handled
    }
    .onAppear {
      let type = CGWindowListOption.optionOnScreenOnly
      let windowList = CGWindowListCopyWindowInfo(type, kCGNullWindowID) as NSArray? as? [[String: AnyObject]]
      appWindows = []

      for entry in windowList ?? [] {
        guard 
          let owner = entry[kCGWindowOwnerName as String] as? String,
          let pid = entry[kCGWindowOwnerPID as String] as? Int32,
          !appWindows.contains(where: { $0.pid == pid })
        else {
          continue
        }

        let appRef = AXUIElementCreateApplication(pid);  //TopLevel Accessability Object of PID

        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
        if result != .success {
          continue
        }

        guard let windowList = value as? [AXUIElement] else {
          continue
        }

        for window in windowList {
          var pid: pid_t = 0
          let result = AXUIElementGetPid(window, &pid)
          if result != .success {
            fatalError("AXUIElementGetPid is failed with \(result.rawValue)")
          }

          guard let position = window.getOrigin() else {
            continue
          }
          appWindows.append(.init(
            uuid: UUID(),
            pid: pid,
            element: window,
            x: position.x,
            y: position.y,
            name: owner,
            key: keys[appWindows.count]
          ))
          if appWindows.count >= keys.count {
            return
          }
        }

        focused = true
        shouldShow = true
      }
    }

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
    result = AXUIElementSetAttributeValue(appWindow.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    if result != .success {
      fatalError("Set kAXFocusedAttribute with AXUIElementSetAttributeValue is failed with \(result.rawValue)...")
    }
  }
}
