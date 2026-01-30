import SwiftUI

/// Overlay content view displayed on top of all windows
struct OverlayContentView: View {
    @ObservedObject var viewModel: ViewModel
    var screenFrame: CGRect = .zero
    
    var body: some View {
        ZStack(alignment: .center) {
            // Semi-transparent background that captures taps
            Color.black.opacity(0.0000000001)
                .onTapGesture {
                    viewModel.hide()
                }
            
            if viewModel.mode == .windowSwitcher {
                // Window labels
                ForEach(viewModel.appWindows.filter {
                    let frame = $0.overlayViewFrame
                    // Check intersection with screen frame (allowing some margin/tolerance if needed)
                    // Simple check: does the center point lie within this screen?
                    // Or precise intersection. Let's start with intersection.
                    return frame.intersects(screenFrame)
                }, id: \.uuid) { appWindow in
                    VStack {
                        Text(appWindow.key)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.2)
                        HStack {
                            if let image = appWindow.image {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            }
                            Text(appWindow.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.gray)
                                .minimumScaleFactor(0.1)
                        }
                    }
                    .padding(8)
                    .frame(width: appWindow.overlayViewFrame.width, height: appWindow.overlayViewFrame.height)
                    .backgroundStyle(.secondary)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(10)
                    .position(
                        x: appWindow.overlayViewFrame.origin.x - screenFrame.origin.x,
                        y: appWindow.overlayViewFrame.origin.y - screenFrame.origin.y
                    )
                }
            } else if viewModel.mode == .uiElement {
                // UI Element labels with clustering support
                if viewModel.uiElementSubMode == .clusterSelection {
                    // Phase 1: Show clusters and isolated elements
                    
                    // Display clusters
                    ForEach(viewModel.clusters.filter { $0.boundingFrame.intersects(screenFrame) }) { cluster in
                        ClusterLabelView(
                            cluster: cluster,
                            isSelected: false,
                            screenFrame: screenFrame
                        )
                    }
                    
                    // Display isolated elements
                    ForEach(viewModel.isolatedElements.filter { $0.frame.intersects(screenFrame) }) { element in
                        let isMatch = viewModel.inputBuffer.isEmpty || element.label.starts(with: viewModel.inputBuffer)
                        UIElementLabelView(
                            element: element,
                            screenFrame: screenFrame
                        )
                        .opacity(isMatch ? 1.0 : 0.1)
                    }
                } else {
                    // Phase 2: Show elements within selected cluster (ZOOMED IN)
                    
                    // Dark overlay background
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                    
                    // Display zoomed screenshot of the cluster area
                    if let screenshot = viewModel.windowScreenshot,
                       let selectedCluster = viewModel.selectedCluster,
                       selectedCluster.boundingFrame.intersects(screenFrame) {
                        ZoomedScreenshotView(
                            screenshot: screenshot,
                            cluster: selectedCluster,
                            zoomScale: viewModel.zoomScale,
                            windowFrame: viewModel.windowFrame,
                            screenFrame: screenFrame
                        )
                    }
                    
                    // Zoomed cluster info at top
                    VStack {
                        if let selectedCluster = viewModel.selectedCluster,
                           selectedCluster.boundingFrame.intersects(screenFrame) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Cluster \(selectedCluster.label) - \(selectedCluster.count) elements")
                                Text("(\(String(format: "%.1f", viewModel.zoomScale))x)")
                                    .foregroundStyle(.gray)
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(8)
                        }
                        Spacer()
                    }
                    .padding(.top, 40)
                    
                    // Show elements in the selected cluster with zoom
                    // Only show if the loop itself is for elements that belong to this screen if we pushed filtering down
                    // But here viewModel.uiElements contains ALL elements in the cluster.
                    // We need to render them only on the screen that intersects the cluster.
                    // Since Phase 2 is "Zoomed into ONE cluster", all elements are likely on the same screen (unless cluster spans screens, which we try to avoid).
                    
                    if let selectedCluster = viewModel.selectedCluster,
                       selectedCluster.boundingFrame.intersects(screenFrame) {
                        
                        ForEach(viewModel.uiElements) { element in
                            let isMatch = viewModel.inputBuffer.isEmpty || element.label.starts(with: viewModel.inputBuffer)
                            UIElementLabelView(
                                element: element,
                                zoomScale: viewModel.zoomScale,
                                zoomCenter: viewModel.zoomCenter,
                                screenFrame: screenFrame
                            )
                            .opacity(isMatch ? 1.0 : 0.1)
                        }
                    }
                }
            } else if viewModel.mode == .scrollTargetSelection {
                // Scroll Target Selection - Show all elements directly (no clustering)
                ForEach(viewModel.uiElements.filter { $0.frame.intersects(screenFrame) }) { element in
                    let isMatch = viewModel.inputBuffer.isEmpty || element.label.starts(with: viewModel.inputBuffer)
                    
                    // Highlight border
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.green, lineWidth: 4)
                        .frame(width: element.frame.width, height: element.frame.height)
                        .position(
                            x: element.frame.midX - screenFrame.origin.x,
                            y: element.frame.midY - screenFrame.origin.y
                        )
                        .opacity(isMatch ? 0.8 : 0.1)
                        
                    UIElementLabelView(
                        element: element,
                        screenFrame: screenFrame
                    )
                    .opacity(isMatch ? 1.0 : 0.1)
                }
            } else if viewModel.mode == .scroll {
                // Scroll Mode Indicator
                // Scroll Mode Indicator
                // Position at the bottom-right of the target window
                
                // Determine the frame to position relative to
                // If windowFrame is valid, use it. Otherwise use screenFrame (fallback)
                let refFrame = (viewModel.windowFrame != .zero && viewModel.windowFrame.intersects(screenFrame)) 
                    ? viewModel.windowFrame.intersection(screenFrame) 
                    : screenFrame
                
                // Convert to local coordinates within the overlay
                let localFrame = CGRect(
                    x: refFrame.minX - screenFrame.minX,
                    y: refFrame.minY - screenFrame.minY,
                    width: refFrame.width,
                    height: refFrame.height
                )
                
                ZStack(alignment: .bottomTrailing) {
                    // Empty container to define the area
                    Color.clear
                    
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "scroll")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                            Text("Scroll Mode")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        HStack(spacing: 12) {
                            Text("H: ←  J: ↓  K: ↑  L: →")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .padding(20) // Margin from edges
                }
                .frame(width: localFrame.width, height: localFrame.height)
                .position(x: localFrame.midX, y: localFrame.midY)
            } else if viewModel.mode == .textSearch {
                // Text Search Mode
                
                // Highlight matching elements
                // Highlight matching elements
                ForEach(Array(viewModel.uiElements.enumerated()), id: \.element.id) { index, element in
                    if element.frame.intersects(screenFrame) {
                        let isSelected = index == viewModel.selectedTextElementIndex
                        let showSelection = isSelected && viewModel.isTextSearchSelectionMode

                        // Highlight border
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(showSelection ? Color.green : Color.yellow, lineWidth: showSelection ? 5 : 2)
                            .frame(width: element.frame.width, height: element.frame.height)
                            .position(
                                x: element.frame.midX - screenFrame.origin.x,
                                y: element.frame.midY - screenFrame.origin.y
                            )
                            .zIndex(showSelection ? 100 : 0) // Bring selected to front
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
