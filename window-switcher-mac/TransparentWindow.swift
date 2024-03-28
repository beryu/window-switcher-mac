import SwiftUI
import AppKit

struct TransparentWindow: NSViewRepresentable {
  func makeNSView(context: Self.Context) -> NSView {
    return TransparentWindowView()
  }
  
  func updateNSView(_ nsView: NSView, context: Context) { }
}

final private class TransparentWindowView: NSView {
  override func viewDidMoveToWindow() {
    window?.backgroundColor = .clear
    super.viewDidMoveToWindow()
  }
}
