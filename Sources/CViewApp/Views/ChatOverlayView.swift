// MARK: - ChatOverlayView.swift
// CViewApp - 비디오 위 오버레이 채팅 뷰
// 반투명 배경 위에 채팅 메시지를 표시하고, 드래그로 위치 조절 가능

import SwiftUI
import CViewCore

// MARK: - Chat Overlay View

struct ChatOverlayView: View {
    let chatVM: ChatViewModel?
    let containerSize: CGSize

    @State private var position: CGPoint = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isHovering = false
    @State private var isResizing = false
    @State private var resizeStart: CGSize = .zero
    @State private var isSideHovered = false
    @State private var isHideHovered = false

    private var overlayWidth: CGFloat { chatVM?.overlayWidth ?? 340 }
    private var overlayHeight: CGFloat { chatVM?.overlayHeight ?? 400 }
    private var chatOpacity: Double { chatVM?.opacity ?? 0.8 }
    private var bgOpacity: Double { chatVM?.overlayBackgroundOpacity ?? 0.5 }
    private var showInput: Bool { chatVM?.overlayShowInput ?? false }

    var body: some View {
        VStack(spacing: 0) {
            // 드래그 핸들 + 모드 전환 버튼 (호버 시만 표시)
            if isHovering {
                overlayHeader
            }

            // 채팅 메시지 영역
            ChatOverlayMessagesView(viewModel: chatVM)

            // 입력 영역 (설정에 따라)
            if showInput {
                ChatInputView(viewModel: chatVM)
                    .background(.black.opacity(0.5))
            }
        }
        .frame(width: overlayWidth, height: overlayHeight)
        .background {
            // [GPU 최적화] Material blur → 솔리드 반투명 색상으로 교체
            // Material(.ultraThinMaterial)은 아래 레이어(비디오)가 변할 때마다 blur 커널을
            // 재계산하므로, 60fps 라이브 비디오 위에서 매 프레임 GPU blur pass 발생.
            // 솔리드 Color는 GPU blur 연산 없이 alpha compositing만 수행 → GPU 사용량 대폭 감소.
            Color(white: 0.1, opacity: bgOpacity * 0.85)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(.white.opacity(isHovering ? 0.2 : 0.08), lineWidth: 0.5)
        }
        // [GPU 최적화] shadow radius 12 → 4로 축소 — blur radius가 클수록 offscreen pass 비용 증가
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .opacity(chatOpacity)
        .position(currentPosition)
        .gesture(dragGesture)
        .onHover { hovering in
            withAnimation(DesignTokens.Animation.fast) { isHovering = hovering }
        }
        .onAppear {
            // 초기 위치: 우측 하단
            if position == .zero {
                position = CGPoint(
                    x: containerSize.width - overlayWidth / 2 - DesignTokens.Spacing.lg,
                    y: containerSize.height - overlayHeight / 2 - DesignTokens.Spacing.lg
                )
            }
        }
        .onChange(of: containerSize) { _, newSize in
            // 컨테이너 크기 변경 시 오버레이가 밖으로 나가지 않도록 clamp
            position = clampPosition(position, in: newSize)
        }

        // 리사이즈 핸들
        .overlay(alignment: .bottomTrailing) {
            if isHovering {
                resizeHandle
            }
        }
    }

    // MARK: - Header

    private var overlayHeader: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "line.3.horizontal")
                .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)

            // 사이드 모드로 전환
            Button {
                chatVM?.displayMode = .side
            } label: {
                Image(systemName: "sidebar.right")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(isSideHovered ? 0.95 : 0.7))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(isSideHovered ? 0.18 : 0.1), in: Circle())
                    .scaleEffect(isSideHovered ? 1.08 : 1.0)
                    .animation(DesignTokens.Animation.fast, value: isSideHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in isSideHovered = hovering }
            .help("사이드 모드로 전환")

            // 채팅 숨기기
            Button {
                chatVM?.displayMode = .hidden
            } label: {
                Image(systemName: "eye.slash")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHideHovered ? 0.95 : 0.7))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(isHideHovered ? 0.18 : 0.1), in: Circle())
                    .scaleEffect(isHideHovered ? 1.08 : 1.0)
                    .animation(DesignTokens.Animation.fast, value: isHideHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in isHideHovered = hovering }
            .help("채팅 숨기기")
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 4)
        .background(.black.opacity(0.3))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Resize Handle

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            resizeStart = CGSize(width: overlayWidth, height: overlayHeight)
                        }
                        let newWidth = max(240, min(600, resizeStart.width + value.translation.width))
                        let newHeight = max(200, min(800, resizeStart.height + value.translation.height))
                        chatVM?.overlayWidth = newWidth
                        chatVM?.overlayHeight = newHeight
                    }
                    .onEnded { _ in
                        isResizing = false
                    }
            )
            .padding(4)
            .transition(.opacity)
    }

    // MARK: - Drag

    private var currentPosition: CGPoint {
        CGPoint(
            x: position.x + dragOffset.width,
            y: position.y + dragOffset.height
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // 드래그 시작 시 hover 숨기기 — hover 레이어 재렌더 방지
                if isHovering { isHovering = false }
                dragOffset = value.translation
            }
            .onEnded { value in
                let newPos = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )
                position = clampPosition(newPos, in: containerSize)
                dragOffset = .zero
            }
    }

    private func clampPosition(_ pos: CGPoint, in size: CGSize) -> CGPoint {
        let halfW = overlayWidth / 2
        let halfH = overlayHeight / 2
        return CGPoint(
            x: max(halfW, min(size.width - halfW, pos.x)),
            y: max(halfH, min(size.height - halfH, pos.y))
        )
    }
}

// MARK: - Overlay Messages View (simplified, no header)

struct ChatOverlayMessagesView: View {
    let viewModel: ChatViewModel?

    @State private var isScrollViewVisible = true
    @State private var scrollSuppressionCount = 0
    @State private var containerHeight: CGFloat = 300

    private var isScrollSuppressed: Bool { scrollSuppressionCount > 0 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let viewModel {
                        ForEach(viewModel.messages) { message in
                            OverlayChatMessageRow(message: message, fontSize: viewModel.fontSize)
                                .id(message.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: containerHeight, alignment: .bottom)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                if newHeight > 0 { containerHeight = newHeight }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let maxScrollY = geometry.contentSize.height - geometry.containerSize.height
                guard maxScrollY > 0 else { return true }
                let distanceFromBottom = maxScrollY - geometry.contentOffset.y
                // 컨테이너 높이 10% 기반 적응형 임계값 (40~120px)
                let threshold = max(40.0, min(geometry.containerSize.height * 0.1, 120.0))
                return distanceFromBottom <= threshold
            } action: { oldValue, isNearBottom in
                guard oldValue != isNearBottom else { return }
                guard isScrollViewVisible, !isScrollSuppressed else { return }
                viewModel?.onScrollPositionChanged(isNearBottom: isNearBottom)
            }
            .onAppear {
                isScrollViewVisible = true
                overlayScrollToLatest(proxy: proxy)
            }
            .onDisappear {
                isScrollViewVisible = false
            }
            .onChange(of: viewModel?.messages.last?.id) { _, _ in
                guard viewModel?.isAutoScrollEnabled == true,
                      viewModel?.isReplayMode != true else { return }
                overlayScrollToLatest(proxy: proxy)
            }
            // 리플레이 모드 표시 (간소화)
            .overlay(alignment: .bottom) {
                if let vm = viewModel, vm.isReplayMode {
                    Button {
                        vm.exitReplayMode()
                        overlayScrollToLatest(proxy: proxy)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                            if vm.unreadCount > 0 {
                                Text("\(vm.unreadCount)")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignTokens.Colors.chzzkGreen.opacity(0.8), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Scroll Helpers

    private func overlayScrollToLatest(proxy: ScrollViewProxy) {
        guard let lastId = viewModel?.messages.last?.id else { return }
        viewModel?.cancelReplayDebounce()
        scrollSuppressionCount += 1
        withAnimation(DesignTokens.Animation.chatScroll) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.scrollSuppressionCount = max(0, self.scrollSuppressionCount - 1)
        }
    }
}

// MARK: - Overlay Chat Message Row (compact, shadow text for readability)

struct OverlayChatMessageRow: View {
    let message: ChatMessageItem
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            // 닉네임
            Text(message.nickname)
                .font(.system(size: fontSize - 1, weight: .bold))
                .foregroundStyle(nicknameColor)
                .lineLimit(1)

            // 메시지 내용
            Text(message.content)
                .font(.system(size: fontSize - 1))
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(.black.opacity(0.2))
        )
        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
    }

    private var nicknameColor: Color {
        let colors: [Color] = [
            .green, .cyan, .yellow, .orange, .pink,
            .mint, .teal, .indigo, .purple, .blue
        ]
        let hash = abs(message.userId.hashValue)
        return colors[hash % colors.count]
    }
}
