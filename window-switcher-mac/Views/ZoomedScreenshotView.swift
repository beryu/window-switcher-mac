//
//  ZoomedScreenshotView.swift
//  window-switcher-mac
//
//  Displays a cropped and zoomed portion of a window screenshot
//

import SwiftUI

struct ZoomedScreenshotView: View {
    let screenshot: NSImage
    let cluster: ClusterModel
    let zoomScale: CGFloat
    let windowFrame: CGRect  // Window frame in CG coordinates (top-left origin)
    var screenFrame: CGRect = .zero
    
    /// Calculate the crop rect for the cluster area relative to the window
    private var cropRect: CGRect {
        let padding: CGFloat = 20
        let clusterFrame = cluster.boundingFrame.insetBy(dx: -padding, dy: -padding)
        
        // Convert cluster frame from screen coordinates to window-relative coordinates
        // Cluster frame uses CG coordinates (top-left origin, same as window frame)
        let relativeX = clusterFrame.origin.x - windowFrame.origin.x
        let relativeY = clusterFrame.origin.y - windowFrame.origin.y
        
        return CGRect(
            x: relativeX,
            y: relativeY,
            width: clusterFrame.width,
            height: clusterFrame.height
        )
    }
    
    /// Screen center for positioning
    private var screenCenter: CGPoint {
        CGPoint(x: screenFrame.width / 2, y: screenFrame.height / 2)
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Crop the screenshot to the cluster area and display zoomed
            if let croppedImage = cropImage(screenshot, to: cropRect) {
                Image(nsImage: croppedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: cropRect.width * zoomScale,
                        height: cropRect.height * zoomScale
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20)
                    .position(x: screenCenter.x, y: screenCenter.y)
            }
        }
    }
    
    /// Crop the NSImage to the specified rect (rect is in window-relative coordinates)
    private func cropImage(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("ZoomedScreenshotView: Failed to get CGImage")
            return nil
        }
        
        // Calculate scale factor between image pixels and window logical points
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // The screenshot might be at a different scale (retina)
        // windowFrame is in points, image is in pixels
        let scaleX = imageWidth / windowFrame.width
        let scaleY = imageHeight / windowFrame.height
        
        print("ZoomedScreenshotView: Image \(imageWidth)x\(imageHeight), Window \(windowFrame), Scale \(scaleX)x\(scaleY)")
        print("ZoomedScreenshotView: Crop rect (window-relative): \(rect)")
        
        // Convert rect from window points to image pixels
        // Note: CGImage has origin at top-left, which matches CG screen coordinates
        let cropCGRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        
        print("ZoomedScreenshotView: Crop rect (pixels): \(cropCGRect)")
        
        // Clamp to image bounds
        let clampedRect = CGRect(
            x: max(0, cropCGRect.origin.x),
            y: max(0, cropCGRect.origin.y),
            width: min(cropCGRect.width, imageWidth - max(0, cropCGRect.origin.x)),
            height: min(cropCGRect.height, imageHeight - max(0, cropCGRect.origin.y))
        )
        
        // Ensure the rect is within bounds and valid
        let validRect = clampedRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard !validRect.isEmpty, validRect.width > 0, validRect.height > 0,
              let croppedCGImage = cgImage.cropping(to: validRect) else {
            print("ZoomedScreenshotView: Invalid crop rect or cropping failed")
            return nil
        }
        
        print("ZoomedScreenshotView: Valid crop rect: \(validRect)")
        return NSImage(cgImage: croppedCGImage, size: NSSize(width: validRect.width / scaleX, height: validRect.height / scaleY))
    }
}
