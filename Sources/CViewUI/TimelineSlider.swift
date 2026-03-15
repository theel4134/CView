// MARK: - TimelineSlider.swift
// CViewUI - 재사용 가능한 타임라인 슬라이더

import SwiftUI
import CViewCore

/// VOD/클립 재생용 타임라인 슬라이더
public struct TimelineSlider: View {
    
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0
    @State private var isHovering = false
    @State private var hoverPosition: CGFloat = 0
    
    public init(
        currentTime: Binding<TimeInterval>,
        duration: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self._currentTime = currentTime
        self.duration = duration
        self.onSeek = onSeek
    }
    
    public var body: some View {
        VStack(spacing: 4) {
            // Timeline bar
            GeometryReader { geometry in
                let width = geometry.size.width
                let displayTime = isDragging ? dragTime : currentTime
                let progress = duration > 0 ? CGFloat(displayTime / duration) : 0
                
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: isHovering || isDragging ? 8 : 4)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.chzzkGreen)
                        .frame(width: max(0, min(width, width * progress)),
                               height: isHovering || isDragging ? 8 : 4)
                    
                    // Thumb (drag handle)
                    if isHovering || isDragging {
                        Circle()
                            .fill(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 14, height: 14)
                            .shadow(radius: 2)
                            .offset(x: max(0, min(width - 14, width * progress - 7)))
                    }
                    
                    // Hover time tooltip
                    if isHovering && !isDragging {
                        let hoverTime = duration * Double(max(0, min(1, hoverPosition / width)))
                        Text(formatTime(hoverTime))
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                            .offset(x: max(20, min(width - 50, hoverPosition - 25)), y: -24)
                    }
                }
                .frame(height: isHovering || isDragging ? 8 : 4)
                .contentShape(Rectangle().size(width: width, height: 20))
                .onHover { hovering in
                    withAnimation(DesignTokens.Animation.fast) {
                        isHovering = hovering
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverPosition = location.x
                    case .ended:
                        break
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = max(0, min(1, Double(value.location.x / width)))
                            dragTime = duration * fraction
                        }
                        .onEnded { value in
                            let fraction = max(0, min(1, Double(value.location.x / width)))
                            let seekTime = duration * fraction
                            onSeek(seekTime)
                            isDragging = false
                        }
                )
            }
            .frame(height: 20)
            
            // Time labels
            HStack {
                Text(formatTime(isDragging ? dragTime : currentTime))
                    .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
