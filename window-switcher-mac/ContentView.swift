//
//  ContentView.swift
//  window-switcher-mac
//
//  Created by 岐部龍太 on 2024/03/24.
//

import SwiftUI

struct ContentView: View {
  @ObservedObject private var viewModel = ViewModel()
  @FocusState private var focused: Bool
  
  var body: some View {
    ZStack(alignment: .center) {
      ForEach(viewModel.appWindows, id: \.uuid) { appWindow in VStack {
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
        .frame(width: appWindow.overlayViewFrame.width, height: appWindow.overlayViewFrame.height)
        .backgroundStyle(.secondary)
        .background(Color.black.opacity(0.8))
        .cornerRadius(10)
        .position(
          x: appWindow.overlayViewFrame.origin.x,
          y: appWindow.overlayViewFrame.origin.y
        )
      }
    }
    .background(Color.black.opacity(0.0000000001)) // NOTE: For enabling tap on transparent area
    .onTapGesture {
      viewModel.hide()
    }
    .background(WindowAccessor(window: $viewModel.window))
    .focusable()
    .focused($focused)
    .focusEffectDisabled()
    .onAppear {
      viewModel.checkPermission()
    }
    .onKeyPress { press in
      viewModel.onKeyPress(press)
    }
    .onChange(of: viewModel.focused) {
      focused = viewModel.focused
    }
  }
}
