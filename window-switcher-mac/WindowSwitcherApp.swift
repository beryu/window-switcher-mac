//
//  WindowSwitcherApp.swift
//  window-switcher-mac
//
//  Created by 岐部龍太 on 2024/03/24.
//

import SwiftUI
import HotKey

let WIDTH: CGFloat = 400
let HEIGHT: CGFloat = 200

@main
struct WindowSwitcherApp: App {
  @State var window: NSWindow?
  let hotKey = HotKey(key: .escape, modifiers: [.command], keyDownHandler: {
    NSApp.activate()
  })

  var body: some Scene {
    WindowGroup {
      ContentView(window: $window)
        .background(TransparentWindow())
        .frame(width: NSScreen.main?.frame.width, height: NSScreen.main?.frame.height)
    }
    .windowStyle(HiddenTitleBarWindowStyle())
  }
}
