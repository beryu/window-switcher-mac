//
//  WindowSwitcherApp.swift
//  window-switcher-mac
//
//  Created by 岐部龍太 on 2024/03/24.
//

import SwiftUI
import HotKey

@main
struct WindowSwitcherApp: App {
  @State var window: NSWindow?
  static var previouslyActiveApp: NSRunningApplication?

  let hotKey = HotKey(key: .escape, modifiers: [.command], keyDownHandler: {
    if let prevActiveApp = NSWorkspace.shared.runningApplications.first(where: { $0.isActive }) {
      Self.previouslyActiveApp = prevActiveApp
    }
    NSApp.activate()
  })

  var body: some Scene {
    WindowGroup {
      ContentView(previouslyActiveApp: .init(
        get: {
          Self.previouslyActiveApp
        },
        set: { Self.previouslyActiveApp = $0 }
      ))
      .background(TransparentWindow())
        .background(WindowAccessor(window: $window))
        .onTapGesture {
          window?.orderOut(nil)
        }
        .frame(width: NSScreen.main?.frame.width, height: NSScreen.main?.frame.height)
    }
    .windowStyle(HiddenTitleBarWindowStyle())
  }
}
