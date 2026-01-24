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
    // Hide traffic light buttons (close, minimize, zoom)
    window?.standardWindowButton(.closeButton)?.isHidden = true
    window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window?.standardWindowButton(.zoomButton)?.isHidden = true
    window?.titlebarAppearsTransparent = true
    window?.titleVisibility = .hidden
    super.viewDidMoveToWindow()
  }
}
