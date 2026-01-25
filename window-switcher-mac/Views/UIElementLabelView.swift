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
    var screenFrame: CGRect = .zero
    
    /// Calculate zoomed position for the element
    private var zoomedPosition: CGPoint {
        let globalX = element.overlayFrame.origin.x + 12
        let globalY = element.overlayFrame.origin.y + 12
        
        // Local coordinates in the current overlay panel
        let localX = globalX - screenFrame.origin.x
        let localY = globalY - screenFrame.origin.y
        
        if zoomScale == 1.0 {
            return CGPoint(x: localX, y: localY)
        }
        
        // Center of the current screen/panel
        let localScreenCenter = CGPoint(x: screenFrame.width / 2, y: screenFrame.height / 2)
        
        // Transform: translate to screen center, scale around cluster center
        // We use global coordinates for the offset vector calculation, which is safe/correct
        let offsetFromCluster = CGPoint(
            x: globalX - zoomCenter.x,
            y: globalY - zoomCenter.y
        )
        
        // Scale the offset and place at screen center
        return CGPoint(
            x: localScreenCenter.x + offsetFromCluster.x * zoomScale,
            y: localScreenCenter.y + offsetFromCluster.y * zoomScale
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
