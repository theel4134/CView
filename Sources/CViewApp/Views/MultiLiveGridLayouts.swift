// MARK: - MultiLiveGridLayouts.swift
// MLPresetGridLayout, MLCustomGridLayout, MLFocusLeftLayout 등
// MultiLivePlayerPane.swift에서 분리된 그리드 레이아웃 뷰

import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - MLPresetGridLayout
/// 프리셋 그리드: 세션 수에 따라 자동 배치 (2x1, 2x2 등)
struct MLPresetGridLayout: View {
    let manager: MultiLiveManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    var onAdd: (() -> Void)? = nil

    var body: some View {
        let sessions = manager.sessions
        let count = sessions.count

        GeometryReader { geo in
            if count <= 2 {
                // 2개 이하: 가로 분할
                HStack(spacing: 1) {
                    ForEach(sessions) { session in
                        MLGridCell(
                            session: session,
                            manager: manager,
                            appState: appState,
                            focusedSessionId: $focusedSessionId,
                            isFocused: false
                        )
                    }
                    // 빈 슬롯에 추가 버튼 (최대 2칸)
                    if count < 2, let onAdd {
                        MLEmptySlotButton(onAdd: onAdd)
                    }
                }
            } else {
                // 3~4개: 2x2 그리드
                let rows = 2
                let cols = 2
                VStack(spacing: 1) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 1) {
                            ForEach(0..<cols, id: \.self) { col in
                                let idx = row * cols + col
                                if idx < count {
                                    MLGridCell(
                                        session: sessions[idx],
                                        manager: manager,
                                        appState: appState,
                                        focusedSessionId: $focusedSessionId,
                                        isFocused: false
                                    )
                                } else if idx == count, let onAdd {
                                    MLEmptySlotButton(onAdd: onAdd)
                                } else {
                                    Color.black
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - MLCustomGridLayout
/// 커스텀 그리드: 리사이즈 디바이더로 비율 조절 가능
struct MLCustomGridLayout: View {
    let manager: MultiLiveManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let containerSize: CGSize
    var onAdd: (() -> Void)? = nil

    var body: some View {
        let sessions = manager.sessions
        let count = sessions.count

        if count <= 1 {
            if let session = sessions.first {
                MLGridCell(
                    session: session,
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    isFocused: false
                )
            }
        } else if count == 2 {
            HStack(spacing: 0) {
                MLGridCell(
                    session: sessions[0],
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    isFocused: false
                )
                .frame(width: containerSize.width * manager.layoutRatios.horizontalRatio)

                MLResizeDivider(isHorizontal: true) { delta in
                    let ratio = manager.layoutRatios.horizontalRatio + delta / containerSize.width
                    manager.layoutRatios.horizontalRatio = ratio
                    manager.layoutRatios.clampHorizontal()
                }

                MLGridCell(
                    session: sessions[1],
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    isFocused: false
                )
            }
        } else {
            // 3~4개: 상하 분할 + 좌우 분할
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    ForEach(0..<min(2, count), id: \.self) { i in
                        MLGridCell(
                            session: sessions[i],
                            manager: manager,
                            appState: appState,
                            focusedSessionId: $focusedSessionId,
                            isFocused: false
                        )
                    }
                }
                .frame(height: containerSize.height * manager.layoutRatios.verticalRatio)

                MLResizeDivider(isHorizontal: false) { delta in
                    let ratio = manager.layoutRatios.verticalRatio + delta / containerSize.height
                    manager.layoutRatios.verticalRatio = ratio
                    manager.layoutRatios.clampVertical()
                }

                HStack(spacing: 1) {
                    ForEach(2..<count, id: \.self) { i in
                        MLGridCell(
                            session: sessions[i],
                            manager: manager,
                            appState: appState,
                            focusedSessionId: $focusedSessionId,
                            isFocused: false
                        )
                    }
                    // 빈 슬롯에 추가 버튼 (4번째 슬롯)
                    if count == 3, let onAdd {
                        MLEmptySlotButton(onAdd: onAdd)
                    }
                }
            }
        }
    }
}

// MARK: - MLFocusLeftLayout
/// 포커스 레이아웃: 왼쪽 메인(70%) + 오른쪽 서브 스트립(30%)
struct MLFocusLeftLayout: View {
    let manager: MultiLiveManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let containerSize: CGSize
    var onAdd: (() -> Void)? = nil

    var body: some View {
        let sessions = manager.sessions
        guard let first = sessions.first else { return AnyView(EmptyView()) }
        let others = Array(sessions.dropFirst())

        return AnyView(
            HStack(spacing: 1) {
                // 메인 패인 (70%)
                MLGridCell(
                    session: first,
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    isFocused: true
                )
                .frame(width: containerSize.width * 0.7)

                // 서브 스트립 (30%)
                VStack(spacing: 1) {
                    ForEach(others) { session in
                        MLGridCell(
                            session: session,
                            manager: manager,
                            appState: appState,
                            focusedSessionId: $focusedSessionId,
                            isFocused: false
                        )
                    }
                    // 빈 슬롯에 추가 버튼
                    if others.count < 3, let onAdd {
                        MLEmptySlotButton(onAdd: onAdd)
                    }
                }
            }
        )
    }
}

// MARK: - MLResizeDivider
/// 커스텀 레이아웃용 리사이즈 디바이더
struct MLResizeDivider: View {
    let isHorizontal: Bool
    let onDrag: (CGFloat) -> Void

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? DesignTokens.Colors.chzzkGreen.opacity(0.6) : Color.white.opacity(0.1))
            .frame(
                width: isHorizontal ? 4 : nil,
                height: isHorizontal ? nil : 4
            )
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let delta = isHorizontal ? value.translation.width : value.translation.height
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                if hovering {
                    (isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - MLEmptySlotButton
/// 빈 슬롯에 표시되는 채널 추가 버튼
private struct MLEmptySlotButton: View {
    let onAdd: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(isHovered ? DesignTokens.Colors.chzzkGreen : .white.opacity(0.4))
                Text("채널 추가")
                    .font(DesignTokens.Typography.footnoteMedium)
                    .foregroundStyle(isHovered ? .white.opacity(0.8) : .white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isHovered ? Color.white.opacity(0.04) : Color.black.opacity(0.3))
            .overlay {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(
                        isHovered ? DesignTokens.Colors.chzzkGreen.opacity(0.4) : .white.opacity(0.08),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}
