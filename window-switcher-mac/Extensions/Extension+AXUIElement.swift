//
//  Extension+AXUIElement.swift
//  window-switcher-mac
//
//  Created by Ryuta Kibe on 2024/03/25.
//

import Cocoa
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
  
  /// Get the frame (origin + size) of this element
  func getFrame() -> CGRect? {
    guard let origin = getOrigin(), let size = getSize() else {
      return nil
    }
    return CGRect(origin: origin, size: size)
  }
  
  /// Get child elements of this element
  func getChildren() -> [AXUIElement]? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(self, kAXChildrenAttribute as CFString, &value)
    if result == .success {
      return value as? [AXUIElement]
    }
    return nil
  }
  
  /// Get the role of this element (e.g., "AXButton", "AXLink", "AXTextField")
  func getRole() -> String? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(self, kAXRoleAttribute as CFString, &value)
    if result == .success {
      return value as? String
    }
    return nil
  }
  
  /// Get the title/label of this element
  func getTitle() -> String? {
    var value: AnyObject?
    // Try title first
    var result = AXUIElementCopyAttributeValue(self, kAXTitleAttribute as CFString, &value)
    if result == .success, let title = value as? String, !title.isEmpty {
      return title
    }
    // Try description as fallback
    result = AXUIElementCopyAttributeValue(self, kAXDescriptionAttribute as CFString, &value)
    if result == .success, let description = value as? String, !description.isEmpty {
      return description
    }
    // Try value as another fallback
    result = AXUIElementCopyAttributeValue(self, kAXValueAttribute as CFString, &value)
    if result == .success, let strValue = value as? String, !strValue.isEmpty {
      return strValue
    }
    return nil
  }
  
  /// Get the role description (human-readable role)
  func getRoleDescription() -> String? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(self, kAXRoleDescriptionAttribute as CFString, &value)
    if result == .success {
      return value as? String
    }
    return nil
  }
  
  /// Check if this element is clickable
  func isClickable() -> Bool {
    guard let role = getRole() else { return false }
    
    // Common clickable roles
    let clickableRoles: Set<String> = [
      "AXButton",
      "AXLink",
      "AXMenuItem",
      "AXMenuBarItem",
      "AXCheckBox",
      "AXRadioButton",
      "AXPopUpButton",
      "AXComboBox",
      "AXDisclosureTriangle",
      "AXIncrementor",
      "AXTab",
      "AXToolbarButton",
      "AXImage",  // Sometimes clickable
      "AXStaticText",  // Sometimes clickable (links in text)
      "AXCell",  // Table cells
    ]
    
    if clickableRoles.contains(role) {
      return true
    }
    
    // Check if element has AXPress action
    var actions: AnyObject?
    let result = AXUIElementCopyAttributeValue(self, "AXActions" as CFString, &actions)
    if result == .success, let actionList = actions as? [String] {
      if actionList.contains("AXPress") || actionList.contains("AXOpen") {
        return true
      }
    }
    
    return false
  }
  
  /// Perform a click action on this element
  @discardableResult
  func performClick() -> Bool {
    // Try AXPress first
    var result = AXUIElementPerformAction(self, kAXPressAction as CFString)
    if result == .success {
      return true
    }
    
    // Try AXOpen as fallback (for some elements like links)
    result = AXUIElementPerformAction(self, "AXOpen" as CFString)
    if result == .success {
      return true
    }
    
    return false
  }
  
  /// Check if element is enabled
  func isEnabled() -> Bool {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(self, kAXEnabledAttribute as CFString, &value)
    if result == .success, let enabled = value as? Bool {
      return enabled
    }
    // Default to true if attribute not available
    return true
  }
  
  /// Check if element is visible (has non-zero size and is on screen)
  func isVisible() -> Bool {
    guard let frame = getFrame() else { return false }
    // Check if element has non-zero size
    if frame.width <= 0 || frame.height <= 0 {
      return false
    }
    // Check if element is within screen bounds
    guard let screenFrame = NSScreen.main?.frame else { return true }
    return frame.intersects(screenFrame)
  }
  /// Check if this element is potentially scrollable
  func isScrollable() -> Bool {
    guard let role = getRole() else { return false }
    
    // Roles that typically contain scrollable content
    let scrollableRoles: Set<String> = [
      "AXScrollArea",
      "AXWebArea",
      "AXTable",
      "AXOutline",
      "AXList",
      "AXBrowser",
      "AXTextArea", // Multi-line text inputs
    ]
    
    if scrollableRoles.contains(role) {
      return true
    }
    
    return false
  }
}
