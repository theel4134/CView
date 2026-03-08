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
        .background(.black.opacity(bgOpacity * chatOpacity))
        .background(.ultraThinMaterial.opacity(bgOpacity * 0.6 * chatOpacity))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(.white.opacity(isHovering ? 0.2 : 0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
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
                    x: containerSize.width - overlayWidth / 2 - 16,
                    y: containerSize.height - overlayHeight / 2 - 16
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
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .help("사이드 모드로 전환")

            // 채팅 숨기기
            Button {
                chatVM?.displayMode = .hidden
            } label: {
                Image(systemName: "eye.slash")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
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
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let maxScrollY = geometry.contentSize.height - geometry.containerSize.height
                guard maxScrollY > 0 else { return true }
                let distanceFromBottom = maxScrollY - geometry.contentOffset.y
                return distanceFromBottom <= 80
            } action: { _, isNearBottom in
                guard isScrollViewVisible, !isScrollSuppressed else { return }
                viewModel?.onScrollPositionChanged(isNearBottom: isNearBottom)
            }
            .onAppear {
                isScrollViewVisible = true
                if viewModel?.isAutoScrollEnabled == true,
                   let lastId = viewModel?.messages.last?.id {
                    scrollSuppressionCount += 1
                    proxy.scrollTo(lastId, anchor: .bottom)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.scrollSuppressionCount = max(0, self.scrollSuppressionCount - 1)
                    }
                }
            }
            .onDisappear {
                isScrollViewVisible = false
            }
            .onChange(of: viewModel?.messages.last?.id) { _, _ in
                guard viewModel?.isAutoScrollEnabled == true else { return }
                if let lastId = viewModel?.messages.last?.id {
                    scrollSuppressionCount += 1
                    proxy.scrollTo(lastId, anchor: .bottom)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.scrollSuppressionCount = max(0, self.scrollSuppressionCount - 1)
                    }
                }
            }
            // 리플레이 모드 표시 (간소화)
            .overlay(alignment: .bottom) {
                if let vm = viewModel, vm.isReplayMode {
                    Button {
                        vm.exitReplayMode()
                        if let lastId = vm.messages.last?.id {
                            scrollSuppressionCount += 1
                            proxy.scrollTo(lastId, anchor: .bottom)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.scrollSuppressionCount = max(0, self.scrollSuppressionCount - 1)
                            }
                        }
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
