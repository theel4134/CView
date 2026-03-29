// MARK: - MultiLiveGridLayouts.swift
// MLPresetGridLayout, MLCustomGridLayout, MLFocusLeftLayout 등
// MultiLivePlayerPane.swift에서 분리된 그리드 레이아웃 뷰

import SwiftUI
import CViewCore
import CViewPlayer

private let gridGap: CGFloat = 1

// MARK: - MLPresetGridLayout
/// 프리셋 그리드: 세션 수에 따라 자동 배치 (2x1, 2x2 등)
struct MLPresetGridLayout: View {
    let manager: MultiLiveManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    var containerSize: CGSize = .zero
    var onAdd: (() -> Void)? = nil

    /// 2채널일 때 컨테이너 비율에 따라 세로/가로 분할 자동 전환
    /// 가로가 충분히 넓으면(>2.8:1) 가로 분할, 아니면 세로 분할로 letterbox 최소화
    private var use2ChannelVerticalStack: Bool {
        guard containerSize.height > 0 else { return false }
        let ratio = containerSize.width / containerSize.height
        // 16:9 ≈ 1.78, 2채널 가로 배치 시 각 셀 ~0.89 → letterbox 심함
        // 세로 배치 시 각 셀 ~1.78:0.5 = 3.56 → 너무 넓음
        // 임계값 2.8 이하에서는 세로 분할이 letterbox를 줄임
        return ratio < 2.8
    }

    var body: some View {
        let sessions = manager.sessions
        let count = sessions.count

        // GeometryReader 제거 — geo 미참조, 리사이즈마다 불필요한 자식 뷰 트리 재렌더링 유발
        if count <= 2 {
            // 2개 이하: 컨테이너 비율에 따라 자동 분할 방향 결정
            if use2ChannelVerticalStack {
                VStack(spacing: gridGap) {
                    ForEach(sessions) { session in
                        MLGridCell(
                            session: session,
                            manager: manager,
                            appState: appState,
                            focusedSessionId: $focusedSessionId,
                            isFocused: false
                        )
                    }
                    if count < 2, let onAdd {
                        MLEmptySlotButton(onAdd: onAdd)
                    }
                }
            } else {
                HStack(spacing: gridGap) {
                    ForEach(sessions) { session in
                        MLGridCell(
                            session: session,
                            manager: manager,
                            appState: appState,
                            focusedSessionId: $focusedSessionId,
                            isFocused: false
                        )
                    }
                    if count < 2, let onAdd {
                        MLEmptySlotButton(onAdd: onAdd)
                    }
                }
            }
        } else {
            // 3~4개: 2x2 그리드
            let rows = 2
            let cols = 2
            VStack(spacing: gridGap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gridGap) {
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
                                DesignTokens.Colors.background
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

                MLResizeDivider(
                    isHorizontal: true,
                    containerLength: containerSize.width,
                    currentRatio: manager.layoutRatios.horizontalRatio,
                    onRatioChange: { newRatio in
                        manager.layoutRatios.horizontalRatio = newRatio
                    }
                )

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
                HStack(spacing: gridGap) {
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

                MLResizeDivider(
                    isHorizontal: false,
                    containerLength: containerSize.height,
                    currentRatio: manager.layoutRatios.verticalRatio,
                    onRatioChange: { newRatio in
                        manager.layoutRatios.verticalRatio = newRatio
                    }
                )

                HStack(spacing: gridGap) {
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
            HStack(spacing: gridGap) {
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
                VStack(spacing: gridGap) {
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
/// `startRatio` 패턴: 드래그 시작 시 ratio를 기억하고 누적 translation으로 절대 계산 → delta 오차 없음
struct MLResizeDivider: View {
    let isHorizontal: Bool
    /// 컨테이너 크기 (translation → ratio 변환용)
    let containerLength: CGFloat
    /// 현재 ratio 읽기용
    let currentRatio: CGFloat
    /// 새 ratio를 전달하는 콜백 (절대값)
    let onRatioChange: (CGFloat) -> Void
    /// 드래그 종료 시 호출 (저장 등)
    var onDragEnd: (() -> Void)? = nil

    @State private var isDragging = false
    /// 드래그 시작 시점의 ratio
    @State private var dragStartRatio: CGFloat = 0

    private let dividerThickness: CGFloat = 3
    private let hitAreaInset: CGFloat = -6

    var body: some View {
        ZStack {
            // 히트 영역 (투명, 넓은 터치 영역)
            Rectangle()
                .fill(Color.clear)
                .frame(
                    width: isHorizontal ? dividerThickness + 12 : nil,
                    height: isHorizontal ? nil : dividerThickness + 12
                )
                .contentShape(Rectangle())

            // 시각적 디바이더
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    isDragging
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.8)
                        : DesignTokens.Glass.dividerColor
                )
                .frame(
                    width: isHorizontal ? dividerThickness : nil,
                    height: isHorizontal ? nil : dividerThickness
                )
                .shadow(
                    color: isDragging ? DesignTokens.Colors.chzzkGreen.opacity(0.3) : .clear,
                    radius: 4
                )
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartRatio = currentRatio
                    }
                    guard containerLength > 0 else { return }
                    let translation = isHorizontal ? value.translation.width : value.translation.height
                    let newRatio = dragStartRatio + translation / containerLength
                    let clamped = min(MultiLiveLayoutRatios.maxRatio, max(MultiLiveLayoutRatios.minRatio, newRatio))
                    onRatioChange(clamped)
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnd?()
                }
        )
        .transaction { $0.animation = nil }
        .onHover { hovering in
            if hovering {
                (isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(DesignTokens.Animation.fast, value: isDragging)
    }
}

// MARK: - MLEmptySlotButton
/// 빈 슬롯에 표시되는 채널 추가 버튼
private struct MLEmptySlotButton: View {
    let onAdd: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: DesignTokens.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(
                            isHovered
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.15)
                                : Color.white.opacity(0.06)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(
                            isHovered
                                ? DesignTokens.Colors.chzzkGreen
                                : DesignTokens.Colors.textTertiary
                        )
                }

                Text("채널 추가")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(
                        isHovered
                            ? DesignTokens.Colors.textSecondary
                            : DesignTokens.Colors.textTertiary
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(DesignTokens.Colors.background.opacity(0.6))
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(
                        isHovered
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.4)
                            : DesignTokens.Colors.border.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }
}
