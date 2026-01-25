import SwiftUI

/// Overlay content view displayed on top of all windows
struct OverlayContentView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        ZStack(alignment: .center) {
            // Semi-transparent background that captures taps
            Color.black.opacity(0.0000000001)
                .onTapGesture {
                    viewModel.hide()
                }
            
            if viewModel.mode == .windowSwitcher {
                // Window labels
                ForEach(viewModel.appWindows, id: \.uuid) { appWindow in
                    VStack {
                        Text(appWindow.key)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
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
                        x: appWindow.overlayViewFrame.origin.x,
                        y: appWindow.overlayViewFrame.origin.y
                    )
                }
            } else if viewModel.mode == .uiElement || viewModel.mode == .scrollTargetSelection {
                // UI Element labels with clustering support
                if viewModel.uiElementSubMode == .clusterSelection {
                    // Phase 1: Show clusters and isolated elements
                    
                    // Display clusters
                    ForEach(viewModel.clusters) { cluster in
                        ClusterLabelView(
                            cluster: cluster,
                            isSelected: false
                        )
                    }
                    
                    // Display isolated elements
                    ForEach(viewModel.isolatedElements) { element in
                        let isMatch = viewModel.inputBuffer.isEmpty || element.label.starts(with: viewModel.inputBuffer)
                        UIElementLabelView(element: element)
                            .opacity(isMatch ? 1.0 : 0.1)
                    }
                } else {
                    // Phase 2: Show elements within selected cluster (ZOOMED IN)
                    
                    // Dark overlay background
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                    
                    // Display zoomed screenshot of the cluster area
                    if let screenshot = viewModel.windowScreenshot,
                       let selectedCluster = viewModel.selectedCluster {
                        ZoomedScreenshotView(
                            screenshot: screenshot,
                            cluster: selectedCluster,
                            zoomScale: viewModel.zoomScale,
                            windowFrame: viewModel.windowFrame
                        )
                    }
                    
                    // Zoomed cluster info at top
                    VStack {
                        if let selectedCluster = viewModel.selectedCluster {
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
                    ForEach(viewModel.uiElements) { element in
                        let isMatch = viewModel.inputBuffer.isEmpty || element.label.starts(with: viewModel.inputBuffer)
                        UIElementLabelView(
                            element: element,
                            zoomScale: viewModel.zoomScale,
                            zoomCenter: viewModel.zoomCenter
                        )
                        .opacity(isMatch ? 1.0 : 0.1)
                    }
                }
            } else if viewModel.mode == .scroll {
                // Scroll Mode Indicator
                VStack(spacing: 20) {
                    Image(systemName: "scroll")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.white)
                    Text("Scroll Mode")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    HStack(spacing: 20) {
                        Label("H: Left", systemImage: "arrow.left")
                        Label("J: Down", systemImage: "arrow.down")
                        Label("K: Up", systemImage: "arrow.up")
                        Label("L: Right", systemImage: "arrow.right")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.gray)
                }
                .padding(40)
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
