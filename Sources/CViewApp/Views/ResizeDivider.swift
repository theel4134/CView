// MARK: - ResizeDivider.swift
// CViewApp — 공통 리사이즈 디바이더 컴포넌트
// 3단계 시각 피드백 (기본/호버/드래그) + 더블클릭 리셋 + ±6pt 히트 영역

import SwiftUI
import CViewCore

/// 패널 간 리사이즈 디바이더 — 모든 분할 뷰에서 통일된 UX 제공
struct ResizeDivider: View {
    /// 디바이더 방향: true = 수평 분할(좌우), false = 수직 분할(상하)
    let isHorizontal: Bool
    /// 드래그 중 실시간 offset 전달 (GestureState 바인딩)
    @Binding var dragOffset: CGFloat
    /// 드래그 종료 시 최종 translation 전달
    let onDragEnd: (CGFloat) -> Void
    /// 더블클릭 시 기본값 복귀 콜백 (nil이면 비활성)
    var onDoubleClick: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isDragging = false

    private let handleLength: CGFloat = 36
    private let hitAreaInset: CGFloat = -6

    private var handleWidth: CGFloat {
        isDragging ? 5 : (isHovered ? 4 : 3)
    }

    private var handleColor: Color {
        if isDragging {
            return DesignTokens.Colors.chzzkGreen.opacity(0.6)
        } else if isHovered {
            return DesignTokens.Colors.textSecondary.opacity(0.5)
        } else {
            return DesignTokens.Colors.textTertiary.opacity(0.3)
        }
    }

    private var lineColor: Color {
        if isDragging {
            return DesignTokens.Colors.chzzkGreen.opacity(0.5)
        } else if isHovered {
            return DesignTokens.Glass.dividerColor.opacity(0.5)
        } else {
            return DesignTokens.Glass.dividerColor.opacity(0.3)
        }
    }

    var body: some View {
        Rectangle()
            .fill(lineColor)
            .frame(width: isHorizontal ? 1 : nil, height: isHorizontal ? nil : 1)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(handleColor)
                    .frame(
                        width: isHorizontal ? handleWidth : handleLength,
                        height: isHorizontal ? handleLength : handleWidth
                    )
            }
            .contentShape(Rectangle().inset(by: hitAreaInset))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    (isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = isHorizontal ? value.translation.width : value.translation.height
                    }
                    .onEnded { value in
                        let translation = isHorizontal ? value.translation.width : value.translation.height
                        isDragging = false
                        dragOffset = 0
                        onDragEnd(translation)
                    }
            )
            .onTapGesture(count: 2) {
                if let onDoubleClick {
                    withAnimation(DesignTokens.Animation.normal) {
                        onDoubleClick()
                    }
                }
            }
            .animation(DesignTokens.Animation.micro, value: isDragging)
            .animation(DesignTokens.Animation.micro, value: isHovered)
            .help("드래그하여 패널 크기 조절 · 더블클릭으로 기본값 복원")
    }
}
