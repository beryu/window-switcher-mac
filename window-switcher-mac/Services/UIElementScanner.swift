//
//  UIElementScanner.swift
//  window-switcher-mac
//
//  Scans UI elements within windows using Accessibility API
//

import Cocoa
import ApplicationServices
import Foundation
import ScreenCaptureKit

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
        
        // Maximum dimension for a cluster (e.g. 500px) to prevent whole-window clusters
        let maxClusterDimension: CGFloat = 500.0
        
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
                // Check if merging would create a cluster too large
                // We need to track the bounding box of each group to do this efficiently
                // For now, simpler heuristic: don't merge if distant
                
                // Get bounds of both groups? 
                // Since 'parent' doesn't store bounds, we'd need a separate structure.
                // Let's rely on a simpler check: areElementsNearby is already local.
                // But transitively A-B-C-D can span a huge area.
                
                // We'll proceed with union, but later split large clusters? 
                // Or better: check combined bounds here.
                // Since this is O(N^2) anyway, let's keep it simple for now.
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
        
        // Max dimensions for a cluster to stay grouped
        let maxClusterSize: CGFloat = 800.0
        
        for (_, indices) in groups {
            if indices.count >= Self.minClusterSize {
                // Potential cluster
                let clusterElements = indices.map { elements[$0] }
                
                // Calculate bounds
                var minX = CGFloat.infinity, minY = CGFloat.infinity
                var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
                
                for el in clusterElements {
                    minX = min(minX, el.frame.minX)
                    minY = min(minY, el.frame.minY)
                    maxX = max(maxX, el.frame.maxX)
                    maxY = max(maxY, el.frame.maxY)
                }
                
                let width = maxX - minX
                let height = maxY - minY
                
                // Check if cluster is too large
                if width > maxClusterSize || height > maxClusterSize {
                    print("UIElementScanner: Cluster too large (\(width)x\(height)), subdividing...")
                    
                    // Initial region is the bounding box of the cluster
                    let initialRegion = CGRect(x: minX, y: minY, width: width, height: height)
                    
                    // Recursively subdivide the cluster
                    let subClusters = subdivideCluster(elements: clusterElements, region: initialRegion, maxDimension: maxClusterSize)
                    print("UIElementScanner: Subdivided into \(subClusters.count) clusters")
                    
                    for (subElements, subBounds) in subClusters {
                        let cluster = ClusterModel(
                            id: UUID(),
                            elements: subElements,
                            label: "",
                            customBounds: subBounds
                        )
                        clusters.append(cluster)
                    }
                } else {
                    // Valid cluster
                    let cluster = ClusterModel(
                        id: UUID(),
                        elements: clusterElements,
                        label: ""  // Will be assigned later
                    )
                    clusters.append(cluster)
                }
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
    
    /// Recursively subdivide a group of elements using geometric partitioning
    /// Returns list of tuples containing elements and their assigned geometric region
    private func subdivideCluster(elements: [UIElementModel], region: CGRect, maxDimension: CGFloat) -> [(elements: [UIElementModel], bounds: CGRect)] {
        guard !elements.isEmpty else { return [] }
        
        let width = region.width
        let height = region.height
        
        // If the current region fits within the limit, return as one cluster with this region
        if width <= maxDimension && height <= maxDimension {
            return [(elements, region)]
        }
        
        // Split geometric space into two halves
        var group1: [UIElementModel] = []
        var group2: [UIElementModel] = []
        var region1: CGRect
        var region2: CGRect
        
        // Determine split axis and pivot
        if width > height {
            // Split vertically
            let pivotX = region.minX + width / 2.0
            region1 = CGRect(x: region.minX, y: region.minY, width: width / 2.0, height: height)
            region2 = CGRect(x: pivotX, y: region.minY, width: width / 2.0, height: height) // Remainder width
            
            for el in elements {
                if el.frame.midX < pivotX {
                    group1.append(el)
                } else {
                    group2.append(el)
                }
            }
        } else {
            // Split horizontally
            let pivotY = region.minY + height / 2.0
            region1 = CGRect(x: region.minX, y: region.minY, width: width, height: height / 2.0)
            region2 = CGRect(x: region.minX, y: pivotY, width: width, height: height / 2.0) // Remainder height
            
            for el in elements {
                if el.frame.midY < pivotY {
                    group1.append(el)
                } else {
                    group2.append(el)
                }
            }
        }
        
        // Handle empty groups: if a split results in an empty group, allow the non-empty one to take its region
        // But we still need to recurse if it's too big.
        // Actually, if we force the region to match the split, we guarantee non-overlap.
        // If group1 is empty, we just don't return a cluster for region1.
        
        var results: [(elements: [UIElementModel], bounds: CGRect)] = []
        
        if !group1.isEmpty {
            results.append(contentsOf: subdivideCluster(elements: group1, region: region1, maxDimension: maxDimension))
        }
        if !group2.isEmpty {
            results.append(contentsOf: subdivideCluster(elements: group2, region: region2, maxDimension: maxDimension))
        }
        
        // Fallback: If for some reason we lost elements (shouldn't happen), or both empty
        if results.isEmpty && !elements.isEmpty {
            // This case implies logic error or strange state, fallback to returning current region
            return [(elements, region)]
        }
        
        return results
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
        return getFocusedWindowInfo(pid: pid)?.frame
    }
    
    /// Get window ID and frame of the focused window
    func getFocusedWindowInfo(pid: pid_t) -> (id: CGWindowID, frame: CGRect)? {
        let appElement = AXUIElementCreateApplication(pid)
        
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard result == .success, let windowElement = focusedWindow else { return nil }
        
        let axWindow = windowElement as! AXUIElement
        
        guard let frame = axWindow.getFrame() else { return nil }
        
        // Use CGWindowList to find the corresponding window ID
        // This is robust enough for finding the ID of the focused window
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        // Find windows belonging to the target process
        let targetWindows = windowList.filter { info in
            guard let windowPID = info[kCGWindowOwnerPID as String] as? Int32 else { return false }
            return windowPID == pid
        }
        
        // We need to match the window based on position/size
        // Allows for 1px tolerance due to potential float conversions
        for info in targetWindows {
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let x = boundsDict["X"] as? CGFloat,
               let y = boundsDict["Y"] as? CGFloat,
               let width = boundsDict["Width"] as? CGFloat,
               let height = boundsDict["Height"] as? CGFloat,
               let id = info[kCGWindowNumber as String] as? CGWindowID {
                
                let cgRect = CGRect(x: x, y: y, width: width, height: height)
                if abs(cgRect.origin.x - frame.origin.x) < 2 &&
                   abs(cgRect.origin.y - frame.origin.y) < 2 &&
                   abs(cgRect.width - frame.width) < 2 &&
                   abs(cgRect.height - frame.height) < 2 {
                    return (id, frame)
                }
            }
        }
        
        // Fallback: If exact match fails, take the first one (often the focused one is first)
        if let first = targetWindows.first,
           let id = first[kCGWindowNumber as String] as? CGWindowID {
             print("UIElementScanner: Exact frame match failed, using first window for PID \(pid)")
             return (id, frame)
        }
        
        return nil
    }
}

/// Service for capturing screen content using ScreenCaptureKit
final class ScreenRecorder {
    
    /// Capture a single screenshot of a specific window
    /// - Parameter windowID: The CGWindowID of the window to capture
    /// - Returns: NSImage of the captured window, or nil if capture failed
    static func captureWindow(windowID: CGWindowID) async throws -> NSImage? {
        // 1. Get available content
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // 2. Find the target window
        guard let window = availableContent.windows.first(where: { $0.windowID == windowID }) else {
            print("ScreenRecorder: Window with ID \(windowID) not found")
            return nil
        }
        
        // 3. Create content filter (target the window, exclude nothing else specifically as we want just the window)
        // desktopIndependentWindow filter creates a capture of just the window
        let filter = SCContentFilter(desktopIndependentWindow: window)
        
        // 4. Create configuration
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        config.showsCursor = false
        
        // 5. Capture image
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        
        // 6. Convert to NSImage
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
