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
    var keyFrame: CGRect
    var name: String
    var key: String
    var image: NSImage?
  }

  @State var window: NSWindow?
  @State var myAppWindow: AppWindow?
  @Binding var previouslyActiveApp: NSRunningApplication?
  @State private var appWindows: [AppWindow] = []
  @FocusState private var focused: Bool
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

  var body: some View {
    ZStack(alignment: .center) {
      ForEach(appWindows, id: \.uuid) { appWindow in
        VStack {
          Text(appWindow.key)
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(.white)
          HStack {
            if let image = appWindow.image {
              Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
            }
            Text(appWindow.name)
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(.gray)
              .minimumScaleFactor(0.1)
          }
        }
        .padding(8)
        .frame(width: appWindow.keyFrame.width, height: appWindow.keyFrame.height)
        .backgroundStyle(.secondary)
        .background(Color.black.opacity(0.8))
        .cornerRadius(10)
        .position(
          x: appWindow.keyFrame.origin.x,
          y: appWindow.keyFrame.origin.y
        )
      }
    }
    .onTapGesture {
      hide()
    }
    .background(WindowAccessor(window: $window))
    .focusable()
    .focused($focused)
    .focusEffectDisabled()
    .onKeyPress { press in
      if press.characters == "\u{1B}" {
        hide()
        previouslyActiveApp?.activate()
        return .handled
      }
      guard let appWindow = appWindows.first(where: { $0.key == press.characters }) else {
        return .ignored
      }
      focusApp(appWindow: appWindow)
      hide()

      return .handled
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
      refreshAppWindows()
      show()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
      hide()
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
    result = AXUIElementSetAttributeValue(appWindow.element, kAXMainAttribute as CFString, kCFBooleanTrue)
    if result != .success {
      print("Set kAXFocusedAttribute with AXUIElementSetAttributeValue is failed with \(result.rawValue)...")
    }
  }

  private func refreshAppWindows() {
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
          let position = element.getOrigin(),
          let size = element.getSize()
        else {
          continue
        }
        if owner == "window-switcher-mac" {
          myAppWindow = .init(
            uuid: UUID(),
            pid: pid,
            element: element,
            keyFrame: CGRect.zero,
            name: owner,
            key: "",
            image: iconImage
          )
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
          keyFrame: CGRect(
            origin: CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2),
            size: CGSize(width: 150, height: 150)
          ),
          name: owner,
          key: keys[appWindows.count],
          image: iconImage
        ))
        if appWindows.count >= keys.count {
          return
        }
      }

      // Modify position of overlapping keyFrames
      var i = 0
      let margin: CGFloat = 10
      while i < appWindows.count {
        let originalKeyFrame = appWindows[i].keyFrame
        var j = i + 1
        while j < appWindows.count {
          if appWindows[i].keyFrame.intersects(appWindows[j].keyFrame) {
            appWindows[j].keyFrame = CGRect(
              origin: CGPoint(
                x: appWindows[i].keyFrame.origin.x + appWindows[j].keyFrame.size.width + margin,
                y: appWindows[j].keyFrame.origin.y
              ),
              size: originalKeyFrame.size
            )
          }
          j += 1
        }
        i += 1
      }
    }

  }

  private func show() {
    window?.orderFront(nil)
    focused = true
  }

  private func hide() {
    focused = false
    window?.orderOut(nil)
  }
}
