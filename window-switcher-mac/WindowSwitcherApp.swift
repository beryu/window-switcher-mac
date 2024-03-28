//
//  WindowSwitcherApp.swift
//  window-switcher-mac
//
//  Created by 岐部龍太 on 2024/03/24.
//

import SwiftUI

@main
struct WindowSwitcherApp: App {
  @State var window: NSWindow?
  static var previouslyActiveApp: NSRunningApplication?

  var body: some Scene {
    WindowGroup {
      ContentView()
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
