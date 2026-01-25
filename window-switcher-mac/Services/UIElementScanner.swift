//
//  UIElementScanner.swift
//  window-switcher-mac
//
//  Scans UI elements within windows using Accessibility API
//

import Cocoa
import ApplicationServices
import Foundation

/// Scans the frontmost window for clickable UI elements
final class UIElementScanner {
    
    /// Label generator for assigning keyboard shortcuts
    private static let labelCharacters = Array("asdfghjklqwertyuiopzxcvbnm")
    
    /// Scan the frontmost application's window for clickable elements
    /// - Parameter maxElements: Maximum number of elements to return
    /// - Returns: Array of UIElementModel representing clickable elements
    func scanFrontmostWindow(maxElements: Int = 702) -> [UIElementModel] {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("UIElementScanner: No frontmost application")
            return []
        }
        
        let pid = frontmostApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get focused window
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard result == .success, let windowElement = focusedWindow else {
            print("UIElementScanner: Could not get focused window")
            return []
        }
        
        let axWindow = windowElement as! AXUIElement
        
        // Recursively find all clickable elements
        var elements: [UIElementModel] = []
        scanElement(axWindow, into: &elements, maxElements: maxElements)
        
        // Assign labels to elements
        assignLabels(to: &elements)
        
        print("UIElementScanner: Found \(elements.count) clickable elements")
        return elements
    }
    
    /// Recursively scan an element and its children for clickable elements
    private func scanElement(_ element: AXUIElement, into elements: inout [UIElementModel], maxElements: Int, depth: Int = 0) {
        // Limit recursion depth to prevent infinite loops
        guard depth < 20 else { return }
        
        // Check if we've reached the maximum
        guard elements.count < maxElements else { return }
        
        // Check if this element is clickable and visible
        if element.isClickable() && element.isVisible() && element.isEnabled() {
            if let frame = element.getFrame(), let role = element.getRole() {
                let title = element.getTitle()
                let uiElement = UIElementModel(
                    id: UUID(),
                    element: element,
                    frame: frame,
                    role: role,
                    title: title,
                    label: ""  // Will be assigned later
                )
                elements.append(uiElement)
            }
        }
        
        // Recursively scan children
        if let children = element.getChildren() {
            for child in children {
                scanElement(child, into: &elements, maxElements: maxElements, depth: depth + 1)
            }
        }
    }
    
    /// Assign keyboard labels to elements
    private func assignLabels(to elements: inout [UIElementModel]) {
        let chars = Self.labelCharacters
        let charCount = chars.count
        
        for (index, _) in elements.enumerated() {
            let label: String
            if index < charCount {
                // Single character label: a, s, d, f, ...
                label = String(chars[index])
            } else {
                // Two character label: aa, as, ad, ...
                let firstIndex = (index - charCount) / charCount
                let secondIndex = (index - charCount) % charCount
                if firstIndex < charCount {
                    label = String(chars[firstIndex]) + String(chars[secondIndex])
                } else {
                    // Fallback for very large number of elements
                    label = String(index)
                }
            }
            elements[index].label = label
        }
    }
    
    /// Public method to assign labels to elements (for use when reassigning within a cluster)
    func assignLabelsToElements(_ elements: inout [UIElementModel]) {
        assignLabels(to: &elements)
    }
    
    // MARK: - Clustering
    
    /// Threshold distance for considering elements as part of the same cluster
    private static let clusterThreshold: CGFloat = 50.0
    
    /// Minimum number of elements to form a cluster (otherwise show individually)
    private static let minClusterSize: Int = 3
    
    /// Cluster elements based on proximity
    /// - Parameters:
    ///   - elements: Array of UI elements to cluster
    /// - Returns: Tuple of (clusters, isolatedElements)
    func clusterElements(elements: [UIElementModel]) -> (clusters: [ClusterModel], isolated: [UIElementModel]) {
        guard !elements.isEmpty else {
            return ([], [])
        }
        
        // Use Union-Find algorithm for clustering
        var parent = Array(0..<elements.count)
        
        func find(_ x: Int) -> Int {
            if parent[x] != x {
                parent[x] = find(parent[x])
            }
            return parent[x]
        }
        
        func union(_ x: Int, _ y: Int) {
            let px = find(x)
            let py = find(y)
            if px != py {
                parent[px] = py
            }
        }
        
        // Check all pairs for proximity
        for i in 0..<elements.count {
            for j in (i+1)..<elements.count {
                if areElementsNearby(elements[i], elements[j]) {
                    union(i, j)
                }
            }
        }
        
        // Group elements by their root parent
        var groups: [Int: [Int]] = [:]
        for i in 0..<elements.count {
            let root = find(i)
            groups[root, default: []].append(i)
        }
        
        // Separate clusters from isolated elements
        var clusters: [ClusterModel] = []
        var isolated: [UIElementModel] = []
        
        for (_, indices) in groups {
            if indices.count >= Self.minClusterSize {
                // This is a cluster
                let clusterElements = indices.map { elements[$0] }
                let cluster = ClusterModel(
                    id: UUID(),
                    elements: clusterElements,
                    label: ""  // Will be assigned later
                )
                clusters.append(cluster)
            } else {
                // These are isolated elements
                for index in indices {
                    isolated.append(elements[index])
                }
            }
        }
        
        // Assign labels to clusters
        assignClusterLabels(to: &clusters)
        
        // Assign labels to isolated elements
        assignLabels(to: &isolated)
        
        print("UIElementScanner: Created \(clusters.count) clusters and \(isolated.count) isolated elements")
        return (clusters, isolated)
    }
    
    /// Check if two elements are nearby (within threshold distance)
    private func areElementsNearby(_ a: UIElementModel, _ b: UIElementModel) -> Bool {
        // Expand frames slightly for overlap detection
        let expandedA = a.frame.insetBy(dx: -Self.clusterThreshold / 2, dy: -Self.clusterThreshold / 2)
        let expandedB = b.frame.insetBy(dx: -Self.clusterThreshold / 2, dy: -Self.clusterThreshold / 2)
        return expandedA.intersects(expandedB)
    }
    
    /// Assign keyboard labels to clusters
    private func assignClusterLabels(to clusters: inout [ClusterModel]) {
        let chars = Self.labelCharacters
        for (index, _) in clusters.enumerated() {
            if index < chars.count {
                clusters[index].label = String(chars[index]).uppercased()
            } else {
                clusters[index].label = "\(index + 1)"
            }
        }
    }
    
    /// Scan the frontmost application's window for scrollable elements
    func scanScrollableElements(maxElements: Int = 26) -> [UIElementModel] {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return [] }
        
        let pid = frontmostApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard result == .success, let windowElement = focusedWindow else { return [] }
        
        let axWindow = windowElement as! AXUIElement
        
        var elements: [UIElementModel] = []
        scanScrollableElement(axWindow, into: &elements, maxElements: maxElements)
        
        assignLabels(to: &elements)
        return elements
    }
    
    /// Recursively scan for scrollable elements
    private func scanScrollableElement(_ element: AXUIElement, into elements: inout [UIElementModel], maxElements: Int, depth: Int = 0) {
        guard depth < 20 else { return }
        guard elements.count < maxElements else { return }
        
        if element.isScrollable() && element.isVisible() && element.isEnabled() {
            if let frame = element.getFrame(), let role = element.getRole() {
                // Determine if this scroll area is large enough to be meaningful
                if frame.width > 50 && frame.height > 50 {
                   let uiElement = UIElementModel(
                       id: UUID(),
                       element: element,
                       frame: frame,
                       role: role,
                       title: element.getTitle(),
                       label: ""
                   )
                   elements.append(uiElement)
                }
            }
        }
        
        if let children = element.getChildren() {
            for child in children {
                scanScrollableElement(child, into: &elements, maxElements: maxElements, depth: depth + 1)
            }
        }
    }

    /// Find an element by its label
    func findElement(byLabel label: String, in elements: [UIElementModel]) -> UIElementModel? {
        return elements.first { $0.label.lowercased() == label.lowercased() }
    }
    
    /// Filter elements whose labels start with the given prefix
    func filterElements(byPrefix prefix: String, in elements: [UIElementModel]) -> [UIElementModel] {
        guard !prefix.isEmpty else { return elements }
        return elements.filter { $0.label.lowercased().hasPrefix(prefix.lowercased()) }
    }
    
    /// Get the frame of the focused window for a specific process
    func getFocusedWindowFrame(pid: pid_t) -> CGRect? {
        let appElement = AXUIElementCreateApplication(pid)
        
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard result == .success, let windowElement = focusedWindow else { return nil }
        
        let axWindow = windowElement as! AXUIElement
        return axWindow.getFrame()
    }
}
