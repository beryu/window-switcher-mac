//
//  ClusterModel.swift
//  window-switcher-mac
//
//  Model representing a cluster of nearby UI elements
//

import Foundation

/// Represents a cluster of nearby UI elements for grouped display
struct ClusterModel: Identifiable {
    let id: UUID
    var elements: [UIElementModel]
    var label: String  // Keyboard shortcut label for selecting this cluster
    var customBounds: CGRect? = nil // Optional override for the bounding frame
    
    /// The bounding rectangle that contains all elements in this cluster
    var boundingFrame: CGRect {
        if let custom = customBounds {
            return custom
        }
        
        guard let first = elements.first else {
            return .zero
        }
        
        var minX = first.frame.minX
        var minY = first.frame.minY
        var maxX = first.frame.maxX
        var maxY = first.frame.maxY
        
        for element in elements.dropFirst() {
            minX = min(minX, element.frame.minX)
            minY = min(minY, element.frame.minY)
            maxX = max(maxX, element.frame.maxX)
            maxY = max(maxY, element.frame.maxY)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// Center point of the cluster for label positioning
    var center: CGPoint {
        let frame = boundingFrame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    
    /// Number of elements in this cluster
    var count: Int {
        elements.count
    }
}
