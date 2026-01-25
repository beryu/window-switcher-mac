//
//  UIElementLabelView.swift
//  window-switcher-mac
//
//  Display component for UI element keyboard shortcuts
//

import SwiftUI

struct UIElementLabelView: View {
    let element: UIElementModel
    var zoomScale: CGFloat = 1.0
    var zoomCenter: CGPoint = .zero
    
    /// Calculate zoomed position for the element
    private var zoomedPosition: CGPoint {
        let originalX = element.overlayFrame.origin.x + 12
        let originalY = element.overlayFrame.origin.y + 12
        
        if zoomScale == 1.0 {
            return CGPoint(x: originalX, y: originalY)
        }
        
        // Get screen center for zoom pivot
        let screenCenter = NSScreen.main.map { 
            CGPoint(x: $0.frame.width / 2, y: $0.frame.height / 2) 
        } ?? CGPoint(x: 960, y: 540)
        
        // Transform: translate to screen center, scale around cluster center
        let offsetFromCluster = CGPoint(
            x: originalX - zoomCenter.x,
            y: originalY - zoomCenter.y
        )
        
        // Scale the offset and place at screen center
        return CGPoint(
            x: screenCenter.x + offsetFromCluster.x * zoomScale,
            y: screenCenter.y + offsetFromCluster.y * zoomScale
        )
    }
    
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
            .position(zoomedPosition)
    }
}
