// MARK: - ChatResizeHandle.swift
// CViewApp - 채팅 패널 리사이즈 드래그 핸들

import SwiftUI
import CViewCore

/// 채팅 패널 왼쪽 경계에 표시되는 드래그 핸들
/// 좌우 드래그로 채팅 패널 너비를 조절할 수 있다.
/// `currentWidth` 기반 절대 좌표 방식 — 드래그 시작 시점의 너비를 기억하고
/// translation.width를 직접 빼서 새 너비를 계산한다. delta 누적 오차 없음.
struct ChatResizeHandle: View {
    @Binding var isDragging: Bool
    /// 현재 채팅 패널 너비 (절대 좌표 계산용)
    let currentWidth: CGFloat
    /// 새 너비를 전달하는 콜백
    let onWidthChange: (_ newWidth: CGFloat) -> Void
    /// 드래그 종료 시 호출 (AppStorage 저장 등)
    var onDragEnd: (() -> Void)?

    @State private var isHovering = false
    /// 드래그 시작 시점의 채팅 너비
    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        ZStack {
            // 시각적 라인: 평상시 1px hairline → hover/drag 시 네온 그린으로 확장
            Rectangle()
                .fill(handleColor)
                .frame(width: handleWidth)
                .animation(DesignTokens.Animation.fast, value: isHovering)
                .animation(DesignTokens.Animation.fast, value: isDragging)

            // Grip 표식: hover/drag 시 중앙에 작은 Chzzk 그린 원 3개
            if isHovering || isDragging {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 2, height: 2)
                    }
                }
                .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.6), radius: 3)
                .transition(.opacity)
            }
        }
        // 넓은 히트 존 (보이는 라인보다 훨씬 넓게 — 커서 그랩 안정성)
        .frame(width: MSTokens.splitHandleHitSize)
        .contentShape(Rectangle())
        .customCursor(.resizeLeftRight)
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartWidth = currentWidth
                    }
                    let newWidth = dragStartWidth - value.translation.width
                    onWidthChange(newWidth)
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnd?()
                }
        )
        .transaction { $0.animation = nil }
    }

    private var handleWidth: CGFloat {
        if isDragging { return MSTokens.splitHandleHoverThickness }
        if isHovering { return MSTokens.splitHandleHoverThickness - 2 }
        return MSTokens.splitHandleThickness
    }

    private var handleColor: Color {
        if isDragging {
            return DesignTokens.Colors.chzzkGreen
        } else if isHovering {
            return DesignTokens.Colors.chzzkGreen.opacity(0.55)
        } else {
            return DesignTokens.Glass.borderColor
        }
    }
}
