//
//  ClusterLabelView.swift
//  window-switcher-mac
//
//  Display component for cluster labels showing grouped elements
//

import SwiftUI

struct ClusterLabelView: View {
    let cluster: ClusterModel
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            Text(cluster.label)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
            Text("(\(cluster.count))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.black.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.orange : Color.yellow)
                .stroke(Color.black, lineWidth: 2)
        )
        .overlay(
            // Dashed border around cluster area
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    Color.yellow.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                )
                .frame(
                    width: cluster.boundingFrame.width + 10,
                    height: cluster.boundingFrame.height + 10
                )
                .position(
                    x: cluster.boundingFrame.midX - cluster.center.x + 15,
                    y: cluster.boundingFrame.midY - cluster.center.y + 15
                ),
            alignment: .center
        )
        .position(
            x: cluster.center.x,
            y: cluster.center.y
        )
    }
}
