//
//  Extension+AXUIElement.swift
//  window-switcher-mac
//
//  Created by Ryuta Kibe on 2024/03/25.
//

import ApplicationServices

extension AXUIElement {
  func getOrigin() -> CGPoint? {
    var position: AnyObject?
    let result = AXUIElementCopyAttributeValue(self, kAXPositionAttribute as CFString, &position)

    if result == .success {
      let axValue = position as! AXValue
      var point = CGPoint.zero
      AXValueGetValue(axValue, AXValueType.cgPoint, &point)
      return point
    }
    return nil
  }

  func getSize() -> CGSize? {
    var size: AnyObject?
    let result = AXUIElementCopyAttributeValue(self, kAXSizeAttribute as CFString, &size)
    if result == .success {
      let axValue = size as! AXValue
      var size = CGSize.zero
      AXValueGetValue(axValue, AXValueType.cgSize, &size)
      return size
    }
    return nil
  }
}
