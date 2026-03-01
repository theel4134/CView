// MARK: - MultiLiveGridLayouts.swift
// CViewApp - 멀티라이브 그리드 레이아웃 관련 뷰
// MultiLivePlayerPane.swift에서 분리

import SwiftUI
import CViewCore
import CViewPlayer
import CViewPersistence

// MARK: - Preset Grid Layout (기존 고정 레이아웃 + 드래그 재정렬)
struct MLPresetGridLayout: View {
    let manager: MultiLiveSessionManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    var onAdd: (() -> Void)? = nil

    @State private var dragSourceIndex: Int? = nil
    @State private var dragOverIndex: Int? = nil

    var body: some View {
        let sessions = manager.sessions
        let count = sessions.count

        if count == 2 {
            HStack(spacing: 2) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, session in
                    MLDraggableGridCell(
                        session: session,
                        index: idx,
                        manager: manager,
                        appState: appState,
                        focusedSessionId: $focusedSessionId,
                        dragSourceIndex: $dragSourceIndex,
                        dragOverIndex: $dragOverIndex
                    )
                }
                if let onAdd, count < MultiLiveSessionManager.maxSessions {
                    addSlotView(onAdd: onAdd)
                }
            }
        } else {
            // 3개 이상: 2×2 그리드
            let cols = 2
            let rows = 2
            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<cols, id: \.self) { col in
                            let idx = row * cols + col
                            if idx < sessions.count {
                                MLDraggableGridCell(
                                    session: sessions[idx],
                                    index: idx,
                                    manager: manager,
                                    appState: appState,
                                    focusedSessionId: $focusedSessionId,
                                    dragSourceIndex: $dragSourceIndex,
                                    dragOverIndex: $dragOverIndex
                                )
                            } else if let onAdd, count < MultiLiveSessionManager.maxSessions {
                                addSlotView(onAdd: onAdd)
                            } else {
                                Color.black
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func addSlotView(onAdd: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(DesignTokens.Typography.custom(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))
                Text("채널 추가")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.white.opacity(0.13))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .white.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onAdd() }
    }
}

// MARK: - Draggable Grid Cell Wrapper
struct MLDraggableGridCell: View {
    let session: MultiLiveSession
    let index: Int
    let manager: MultiLiveSessionManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    @Binding var dragSourceIndex: Int?
    @Binding var dragOverIndex: Int?

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        let isDropTarget = dragOverIndex == index && dragSourceIndex != index

        MLGridCell(
            session: session,
            manager: manager,
            appState: appState,
            focusedSessionId: $focusedSessionId,
            isFocused: false
        )
        // [60fps 최적화] .opacity()/.scaleEffect() → 오프스크린 compositing 버퍼 강제 생성 제거
        // 경량 Color overlay로 대체하여 비디오 텍스처 재래스터화 방지
        .overlay(isDragging ? Color.black.opacity(0.4) : Color.clear)
        .offset(isDragging ? dragOffset : .zero)
        .zIndex(isDragging ? 10 : 0)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .stroke(
                    isDropTarget ? DesignTokens.Colors.chzzkGreen : Color.clear,
                    lineWidth: 2
                )
                .animation(DesignTokens.Animation.fast, value: isDropTarget)
        )
        // 드래그 재정렬 핸들 (셀 상단 끌기)
        .overlay(alignment: .topTrailing) {
            MLDragHandle()
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragSourceIndex = index
                            }
                            dragOffset = value.translation
                        }
                        .onEnded { _ in
                            if let source = dragSourceIndex, let target = dragOverIndex, source != target {
                                withAnimation(DesignTokens.Animation.indicator) {
                                    manager.swapSessions(source, target)
                                }
                            }
                            withAnimation(DesignTokens.Animation.snappy) {
                                isDragging = false
                                dragOffset = .zero
                                dragSourceIndex = nil
                                dragOverIndex = nil
                            }
                        }
                )
                .padding(DesignTokens.Spacing.xs)
        }
        // 드롭 타겟 감지
        .onContinuousHover { phase in
            if dragSourceIndex != nil {
                switch phase {
                case .active:
                    if dragOverIndex != index { dragOverIndex = index }
                case .ended:
                    if dragOverIndex == index { dragOverIndex = nil }
                }
            }
        }
    }
}

// MARK: - Drag Handle (드래그 핸들 아이콘)
struct MLDragHandle: View {
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(isHovered ? 0.8 : 0.35))
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Color.black.opacity(isHovered ? 0.65 : 0.4))
            )
            .onHover { isHovered = $0 }
            .animation(DesignTokens.Animation.micro, value: isHovered)
            .help("드래그하여 위치 변경")
    }
}

// MARK: - Custom Grid Layout (리사이즈 디바이더 포함)
struct MLCustomGridLayout: View {
    let manager: MultiLiveSessionManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let containerSize: CGSize
    var onAdd: (() -> Void)? = nil

    /// 디바이더 드래그 중 임시 비율
    @State private var tempHRatio: CGFloat? = nil
    @State private var tempVRatio: CGFloat? = nil

    // 드래그 재정렬
    @State private var dragSourceIndex: Int? = nil
    @State private var dragOverIndex: Int? = nil

    private var hRatio: CGFloat { tempHRatio ?? manager.layoutRatios.horizontalRatio }
    private var vRatio: CGFloat { tempVRatio ?? manager.layoutRatios.verticalRatio }

    private let dividerThickness: CGFloat = 6
    private let minPaneWidth: CGFloat = 200
    private let minPaneHeight: CGFloat = 150

    var body: some View {
        let sessions = manager.sessions
        let count = sessions.count

        if count <= 0 {
            // 세션 없음 — 빈 상태
            EmptyView()
        } else if count == 1 {
            // 1개: 단일 셀 + 추가 슬롯
            HStack(spacing: 0) {
                cellView(sessions[0], index: 0)
                if let onAdd, count < MultiLiveSessionManager.maxSessions {
                    MLResizeDivider(axis: .vertical) { _ in } onEnd: {}
                        .hidden()
                    addSlotView(onAdd: onAdd)
                }
            }
        } else if count == 2 {
            // 2개: 좌우 분할 + 수평 디바이더
            HStack(spacing: 0) {
                cellView(sessions[0], index: 0)
                    .frame(width: containerSize.width * hRatio - dividerThickness / 2)

                MLResizeDivider(axis: .vertical) { delta in
                    let newRatio = manager.layoutRatios.horizontalRatio + delta / containerSize.width
                    tempHRatio = clampH(newRatio)
                } onEnd: {
                    if let r = tempHRatio {
                        manager.layoutRatios.horizontalRatio = r
                        manager.layoutRatios.clampHorizontal()
                    }
                    tempHRatio = nil
                }

                cellView(sessions[1], index: 1)
                    .frame(width: containerSize.width * (1 - hRatio) - dividerThickness / 2)
            }
        } else if count == 3 {
            // 3개: 상단 2개 + 하단 1개 (수직 디바이더 + 상단 수평 디바이더)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cellView(sessions[0], index: 0)
                        .frame(width: containerSize.width * hRatio - dividerThickness / 2)

                    MLResizeDivider(axis: .vertical) { delta in
                        let newRatio = manager.layoutRatios.horizontalRatio + delta / containerSize.width
                        tempHRatio = clampH(newRatio)
                    } onEnd: {
                        if let r = tempHRatio {
                            manager.layoutRatios.horizontalRatio = r
                            manager.layoutRatios.clampHorizontal()
                        }
                        tempHRatio = nil
                    }

                    cellView(sessions[1], index: 1)
                        .frame(width: containerSize.width * (1 - hRatio) - dividerThickness / 2)
                }
                .frame(height: containerSize.height * vRatio - dividerThickness / 2)

                MLResizeDivider(axis: .horizontal) { delta in
                    let newRatio = manager.layoutRatios.verticalRatio + delta / containerSize.height
                    tempVRatio = clampV(newRatio)
                } onEnd: {
                    if let r = tempVRatio {
                        manager.layoutRatios.verticalRatio = r
                        manager.layoutRatios.clampVertical()
                    }
                    tempVRatio = nil
                }

                HStack(spacing: 0) {
                    cellView(sessions[2], index: 2)
                    if let onAdd, count < MultiLiveSessionManager.maxSessions {
                        MLResizeDivider(axis: .vertical) { _ in } onEnd: {}
                            .hidden()
                        addSlotView(onAdd: onAdd)
                    }
                }
                .frame(height: containerSize.height * (1 - vRatio) - dividerThickness / 2)
            }
        } else if count >= 4 {
            // 4개: 2×2 + 수평/수직 디바이더
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cellView(sessions[0], index: 0)
                        .frame(width: containerSize.width * hRatio - dividerThickness / 2)

                    MLResizeDivider(axis: .vertical) { delta in
                        let newRatio = manager.layoutRatios.horizontalRatio + delta / containerSize.width
                        tempHRatio = clampH(newRatio)
                    } onEnd: {
                        if let r = tempHRatio {
                            manager.layoutRatios.horizontalRatio = r
                            manager.layoutRatios.clampHorizontal()
                        }
                        tempHRatio = nil
                    }

                    cellView(sessions[1], index: 1)
                        .frame(width: containerSize.width * (1 - hRatio) - dividerThickness / 2)
                }
                .frame(height: containerSize.height * vRatio - dividerThickness / 2)

                MLResizeDivider(axis: .horizontal) { delta in
                    let newRatio = manager.layoutRatios.verticalRatio + delta / containerSize.height
                    tempVRatio = clampV(newRatio)
                } onEnd: {
                    if let r = tempVRatio {
                        manager.layoutRatios.verticalRatio = r
                        manager.layoutRatios.clampVertical()
                    }
                    tempVRatio = nil
                }

                HStack(spacing: 0) {
                    cellView(sessions[2], index: 2)
                        .frame(width: containerSize.width * hRatio - dividerThickness / 2)

                    MLResizeDivider(axis: .vertical) { delta in
                        let newRatio = manager.layoutRatios.horizontalRatio + delta / containerSize.width
                        tempHRatio = clampH(newRatio)
                    } onEnd: {
                        if let r = tempHRatio {
                            manager.layoutRatios.horizontalRatio = r
                            manager.layoutRatios.clampHorizontal()
                        }
                        tempHRatio = nil
                    }

                    cellView(sessions[3], index: 3)
                        .frame(width: containerSize.width * (1 - hRatio) - dividerThickness / 2)
                }
                .frame(height: containerSize.height * (1 - vRatio) - dividerThickness / 2)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ session: MultiLiveSession, index: Int) -> some View {
        let isDropTarget = dragOverIndex == index && dragSourceIndex != index

        MLGridCell(
            session: session,
            manager: manager,
            appState: appState,
            focusedSessionId: $focusedSessionId,
            isFocused: false
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    isDropTarget ? DesignTokens.Colors.chzzkGreen.opacity(0.8) : Color.clear,
                    lineWidth: 2
                )
                .animation(DesignTokens.Animation.fast, value: isDropTarget)
        )
        // 드래그 핸들
        .overlay(alignment: .topTrailing) {
            MLDragHandle()
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { _ in
                            if dragSourceIndex == nil {
                                dragSourceIndex = index
                            }
                        }
                        .onEnded { _ in
                            if let source = dragSourceIndex, let target = dragOverIndex, source != target {
                                withAnimation(DesignTokens.Animation.indicator) {
                                    manager.swapSessions(source, target)
                                }
                            }
                            withAnimation(DesignTokens.Animation.snappy) {
                                dragSourceIndex = nil
                                dragOverIndex = nil
                            }
                        }
                )
                .padding(DesignTokens.Spacing.xs)
        }
        .onContinuousHover { phase in
            if dragSourceIndex != nil {
                switch phase {
                case .active:
                    if dragOverIndex != index { dragOverIndex = index }
                case .ended:
                    if dragOverIndex == index { dragOverIndex = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func addSlotView(onAdd: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(DesignTokens.Typography.custom(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))
                Text("채널 추가")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.white.opacity(0.13))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onAdd() }
    }

    private func clampH(_ ratio: CGFloat) -> CGFloat {
        let minR = max(MultiLiveLayoutRatios.minRatio, minPaneWidth / containerSize.width)
        let maxR = min(MultiLiveLayoutRatios.maxRatio, 1.0 - minPaneWidth / containerSize.width)
        return min(maxR, max(minR, ratio))
    }

    private func clampV(_ ratio: CGFloat) -> CGFloat {
        let minR = max(MultiLiveLayoutRatios.minRatio, minPaneHeight / containerSize.height)
        let maxR = min(MultiLiveLayoutRatios.maxRatio, 1.0 - minPaneHeight / containerSize.height)
        return min(maxR, max(minR, ratio))
    }
}

// MARK: - Resize Divider (리사이즈 핸들)
struct MLResizeDivider: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var isCursorPushed = false

    private var thickness: CGFloat { 6 }

    var body: some View {
        ZStack {
            // 배경 — 호버/드래그 시 강조
            Rectangle()
                .fill(
                    isDragging
                        ? DesignTokens.Colors.chzzkGreen.opacity(0.35)
                        : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                )

            // 가운데 핸들 도트
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .fill(
                    isDragging
                        ? DesignTokens.Colors.chzzkGreen
                        : (isHovered ? Color.white.opacity(0.5) : Color.white.opacity(0.2))
                )
                .frame(
                    width: axis == .horizontal ? 32 : 3,
                    height: axis == .horizontal ? 3 : 32
                )
        }
        .frame(
            width: axis == .vertical ? thickness : nil,
            height: axis == .horizontal ? thickness : nil
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    isDragging = true
                    let delta = axis == .horizontal ? value.translation.height : value.translation.width
                    onDrag(delta)
                }
                .onEnded { _ in
                    isDragging = false
                    onEnd()
                }
        )
        .onHover { isHovered = $0 }
        // [60fps 최적화] .animation() 제거 — 드래그 중 매 픽셀마다 SwiftUI display list 업데이트 방지
        // 호버/드래그 색상 변경은 즉각 반영 (16.67ms 내 충분)
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if !isCursorPushed {
                    if axis == .horizontal {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.resizeLeftRight.push()
                    }
                    isCursorPushed = true
                }
            case .ended:
                if isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
        }
        #endif
    }
}

// MARK: - Focus Left Layout (1+N 레이아웃)
/// 메인 스트림(왼쪽 70%) + 나머지 스트림 세로 스택(오른쪽 30%)
/// 2개: 1+1 좌우, 3개: 1+2, 4개: 1+3
struct MLFocusLeftLayout: View {
    let manager: MultiLiveSessionManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let containerSize: CGSize
    var onAdd: (() -> Void)? = nil

    /// 메인/서브 영역 비율 (드래그로 조절 가능)
    @State private var mainRatio: CGFloat = 0.70

    static let minRatio: CGFloat = 0.35
    static let maxRatio: CGFloat = 0.85

    var body: some View {
        let sessions = manager.sessions
        if let mainSession = sessions.first {
            let subs = Array(sessions.dropFirst())
            HStack(spacing: 0) {
                // ── 왼쪽: 메인 스트림 ──
                MLGridCell(
                    session: mainSession,
                    manager: manager,
                    appState: appState,
                    focusedSessionId: $focusedSessionId,
                    isFocused: false
                )
                .frame(width: containerSize.width * mainRatio)

                // ── 리사이즈 디바이더 ──
                MLFocusDivider(ratio: $mainRatio, containerLength: containerSize.width)

                // ── 오른쪽: 서브 스트림 세로 스택 ──
                VStack(spacing: 2) {
                    ForEach(subs) { session in
                        MLGridCell(
                            session: session,
                            manager: manager,
                            appState: appState,
                            focusedSessionId: $focusedSessionId,
                            isFocused: false
                        )
                    }
                    // 빈 슬롯
                    if let onAdd, sessions.count < MultiLiveSessionManager.maxSessions {
                        ZStack {
                            Color.black.opacity(0.85)
                            VStack(spacing: 8) {
                                Image(systemName: "plus.circle")
                                    .font(DesignTokens.Typography.custom(size: 26, weight: .light))
                                    .foregroundStyle(.white.opacity(0.18))
                                Text("채널 추가")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(.white.opacity(0.13))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.08), .white.opacity(0.04)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onAdd() }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Focus Layout Divider (포커스 레이아웃 리사이즈 핸들)
struct MLFocusDivider: View {
    @Binding var ratio: CGFloat
    let containerLength: CGFloat

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : Color.white.opacity(0.08))
            .frame(width: isDragging ? 4 : 2)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newRatio = (containerLength * ratio + value.translation.width) / containerLength
                        ratio = min(MLFocusLeftLayout.maxRatio, max(MLFocusLeftLayout.minRatio, newRatio))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .animation(DesignTokens.Animation.micro, value: isDragging)
    }
}
