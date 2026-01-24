//
//  UIElementModel.swift
//  window-switcher-mac
//
//  Model representing a clickable UI element
//

import Foundation
import ApplicationServices

/// Represents a clickable UI element detected via Accessibility API
struct UIElementModel: Identifiable {
    let id: UUID
    let element: AXUIElement
    let frame: CGRect
    let role: String
    let title: String?
    var label: String  // Keyboard shortcut label (e.g., "a", "ab")
    
    /// Creates an overlay frame for displaying the label at the element's position
    var overlayFrame: CGRect {
        // Position the label at the top-left corner of the element
        CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(frame.width, 24),
            height: max(frame.height, 24)
        )
    }
    
    /// Returns a display name combining title and role
    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        // Use role description as fallback
        return element.getRoleDescription() ?? role
    }
}
