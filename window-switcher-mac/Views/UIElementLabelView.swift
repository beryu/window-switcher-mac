//
//  UIElementLabelView.swift
//  window-switcher-mac
//
//  Display component for UI element keyboard shortcuts
//

import SwiftUI

struct UIElementLabelView: View {
    let element: UIElementModel
    
    var body: some View {
        Text(element.label)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.yellow) // Homerow-like distinct color
                    .stroke(Color.black, lineWidth: 1)
            )
            .position(
                x: element.overlayFrame.origin.x + 12, // Offset slightly to align
                y: element.overlayFrame.origin.y + 12
            )
    }
}
