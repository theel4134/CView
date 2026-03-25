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
        Rectangle()
            .fill(handleColor)
            .frame(width: 5)
            .padding(.horizontal, 3)
            .contentShape(Rectangle().inset(by: -4))
            .customCursor(.resizeLeftRight)
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = currentWidth
                        }
                        // 왼쪽으로 드래그(음수) → 채팅 넓히기, 오른쪽(양수) → 좁히기
                        let newWidth = dragStartWidth - value.translation.width
                        onWidthChange(newWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onDragEnd?()
                    }
            )
            .animation(DesignTokens.Animation.fast, value: isHovering)
            .animation(DesignTokens.Animation.fast, value: isDragging)
    }

    private var handleColor: Color {
        if isDragging {
            return DesignTokens.Colors.chzzkGreen.opacity(0.6)
        } else if isHovering {
            return DesignTokens.Colors.chzzkGreen.opacity(0.35)
        } else {
            return Color.white.opacity(0.06)
        }
    }
}
