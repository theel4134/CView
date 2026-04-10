// MARK: - ChatPanelView.swift
// CViewApp - 프리미엄 채팅 패널
// Design: Glass Morphism Dark Chat + Modern Layout
// 채팅 모드: side(사이드), overlay(화면 위), hidden(숨김)

import SwiftUI
import Combine
import CViewCore
import CViewChat
import CViewUI

// MARK: - Chat Panel (Header + Messages + Input)

struct ChatPanelView: View {
    let chatVM: ChatViewModel?
    let onOpenSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExportHovered = false
    @State private var isSettingsHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            chatHeader

            // Messages list — rebuilt scroll engine
            ChatMessagesView(viewModel: chatVM)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Input area
            ChatInputView(viewModel: chatVM)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(DesignTokens.Colors.surfaceBase)
        .sheet(isPresented: Binding(
            get: { chatVM?.showExportSheet ?? false },
            set: { chatVM?.showExportSheet = $0 }
        )) {
            ChatExportView()
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            
            Text("채팅")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            // 참여자 수 표시
            if let count = chatVM?.uniqueUserCount, count > 0 {
                Text("\(count)명")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignTokens.Colors.chzzkGreen.opacity(0.08), in: Capsule())
            }

            Spacer()

            // 채팅 모드 전환 메뉴
            chatModeMenu

            // Connection status pill — Glass
            HStack(spacing: 4) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 5, height: 5)
                    .shadow(color: connectionColor.opacity(0.6), radius: 3)

                Text(connectionText)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs + 1)
            // [GPU 최적화] Material blur → 솔리드 반투명 색상 (비디오 위 blur 매 프레임 재계산 방지)
            .background(DesignTokens.Colors.surfaceBase.opacity(0.8), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(connectionColor.opacity(0.35), lineWidth: 0.5)
            }
            .animation(DesignTokens.Animation.smooth, value: chatVM?.connectionState)

            // Chat export — [GPU 최적화] 28px 소형 원형에 Material blur 불필요 → surfaceElevated로 교체
            Button {
                chatVM?.showExportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(isExportHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                    .overlay {
                        Circle().strokeBorder(
                            isExportHovered ? DesignTokens.Colors.chzzkGreen.opacity(0.35) : DesignTokens.Glass.borderColor,
                            lineWidth: 0.5
                        )
                    }
                    .scaleEffect(isExportHovered ? 1.06 : 1.0)
                    .animation(DesignTokens.Animation.fast, value: isExportHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in isExportHovered = hovering }
            .help("채팅 내보내기")
            .disabled(chatVM?.chatHistory.isEmpty ?? true)

            // Chat settings — [GPU 최적화] 28px 소형 원형에 Material blur 불필요 → surfaceElevated로 교체
            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(isSettingsHovered ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                    .overlay {
                        Circle().strokeBorder(
                            isSettingsHovered ? DesignTokens.Colors.chzzkGreen.opacity(0.35) : DesignTokens.Glass.borderColor,
                            lineWidth: 0.5
                        )
                    }
                    .scaleEffect(isSettingsHovered ? 1.06 : 1.0)
                    .animation(DesignTokens.Animation.fast, value: isSettingsHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in isSettingsHovered = hovering }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, DesignTokens.Glass.dividerColor.opacity(0.5), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 0.5)
        }
    }

    // MARK: - Chat Mode Menu

    private var chatModeMenu: some View {
        Menu {
            ForEach(ChatDisplayMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        chatVM?.displayMode = mode
                    }
                } label: {
                    Label(mode.label, systemImage: mode.icon)
                }
                .disabled(chatVM?.displayMode == mode)
            }
        } label: {
            Image(systemName: chatVM?.displayMode.icon ?? "sidebar.right")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 26, height: 26)
                .background(DesignTokens.Colors.surfaceElevated, in: Circle())
                .overlay {
                    Circle().strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("채팅 표시 모드")
    }

    // MARK: - Connection State

    private var connectionColor: Color {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected(_): DesignTokens.Colors.chzzkGreen
        case .connecting, .reconnecting(_): DesignTokens.Colors.warning
        case .disconnected, .failed(_): DesignTokens.Colors.error
        }
    }

    private var connectionText: String {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected(_): "연결됨"
        case .connecting: "연결 중"
        case .reconnecting(_): "재연결 중"
        case .disconnected: "연결 끊김"
        case .failed(_): "연결 실패"
        }
    }
}

// MARK: - Chat Messages View (Rebuilt Scroll Engine)

struct ChatMessagesView: View {
    let viewModel: ChatViewModel?

    /// ScrollView가 화면에 표시 중인지 추적 — 백그라운드 전환에 의한 잘못된 replay mode 진입 방지
    @State private var isScrollViewVisible = true
    /// 프로그래밍적 스크롤 중 onScrollGeometryChange 오탐 방지 (카운터 기반)
    @State private var scrollSuppressionCount = 0
    /// ScrollView 컨테이너의 실제 너비 — LazyVStack 콘텐츠에 명시적 너비 제약 전달용
    @State private var containerWidth: CGFloat = 300
    /// ScrollView 컨테이너 높이 — 치지직 웹처럼 메시지를 하단 정렬하기 위한 minHeight
    @State private var containerHeight: CGFloat = 400

    /// 스크롤 억제 중인지 여부
    private var isScrollSuppressed: Bool { scrollSuppressionCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned message banner
            if let pinned = viewModel?.pinnedMessage {
                pinnedMessageBanner(pinned)
            }

            ScrollViewReader { proxy in
                // 렌더링 설정값을 값 타입으로 스냅샷 — config 미변경 시 기존 행 재렌더링 방지
                let renderConfig = viewModel.map(ChatRenderConfig.init(from:)) ?? .default
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let viewModel {
                            if viewModel.messages.isEmpty {
                                chatEmptyState
                            } else {
                                ForEach(viewModel.messages) { message in
                                    EquatableChatMessageRow(message: message, config: renderConfig, chatVM: viewModel)
                                        .equatable()
                                        .id(message.id)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: containerHeight, alignment: .bottom)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }
                .scrollIndicators(.hidden)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    if newWidth > 0 { containerWidth = newWidth }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    if newHeight > 0 { containerHeight = newHeight }
                }
                .defaultScrollAnchor(.bottom)
                // Rebuilt scroll detection — 적응형 거리 기반 하단 감지
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let maxScrollY = geometry.contentSize.height - geometry.containerSize.height
                    guard maxScrollY > 0 else { return true }
                    let distanceFromBottom = maxScrollY - geometry.contentOffset.y
                    // 컨테이너 높이 10% 기반 적응형 임계값 (40~120px)
                    let threshold = max(40.0, min(geometry.containerSize.height * 0.1, 120.0))
                    return distanceFromBottom <= threshold
                } action: { oldValue, isNearBottom in
                    // oldValue == newValue → contentSize 변경에 의한 재계산, 실제 스크롤 아님
                    guard oldValue != isNearBottom else { return }
                    guard isScrollViewVisible, !isScrollSuppressed else { return }
                    viewModel?.onScrollPositionChanged(isNearBottom: isNearBottom)
                }
                .onAppear {
                    isScrollViewVisible = true
                    scrollToLatest(proxy: proxy)
                }
                .onDisappear {
                    isScrollViewVisible = false
                }
                // 새 메시지 도착 시 자동 스크롤 — isAutoScrollEnabled 기반 (shouldScrollToLatest 레이스컨디션 제거)
                .onChange(of: viewModel?.messages.last?.id) { _, _ in
                    guard viewModel?.isAutoScrollEnabled == true,
                          viewModel?.isReplayMode != true else { return }
                    scrollToLatest(proxy: proxy)
                }
                // 앱이 다시 포그라운드로 돌아올 때 자동 스크롤 복원
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    guard viewModel?.isAutoScrollEnabled == true,
                          viewModel?.isReplayMode != true else { return }
                    scrollToLatest(proxy: proxy)
                }
                // Floating scroll-to-bottom button
                .overlay(alignment: .bottom) {
                    Group {
                        if let vm = viewModel, vm.isReplayMode {
                            replayModeButton(vm: vm, proxy: proxy)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(DesignTokens.Animation.snappy, value: viewModel?.isReplayMode)
                }
                // Esc 키로 replay mode 해제 + 하단 복귀
                .onKeyPress(.escape) {
                    guard let vm = viewModel, vm.isReplayMode else { return .ignored }
                    vm.exitReplayMode()
                    scrollToLatest(proxy: proxy)
                    return .handled
                }
            }
        } // VStack
    }

    // MARK: - Scroll Helpers

    /// 최하단으로 프로그래밍적 스크롤 — 억제 카운터로 onScrollGeometryChange 오탐 방지
    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let lastId = viewModel?.messages.last?.id else { return }
        // replay mode debounce 타스크가 대기 중이면 취소 — 프로그래밍적 스크롤 중 잘못된 진입 방지
        viewModel?.cancelReplayDebounce()
        scrollSuppressionCount += 1
        withAnimation(DesignTokens.Animation.chatScroll) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
        // 스크롤 완료 후 억제 해제 — 배치 간격(100ms) + 렌더링 여유(80ms)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            self.scrollSuppressionCount = max(0, self.scrollSuppressionCount - 1)
        }
    }

    // MARK: - Pinned Message

    private func pinnedMessageBanner(_ pinned: ChatMessageItem) -> some View {
        HStack(spacing: 0) {
            DesignTokens.Colors.accentOrange
                .frame(width: 3)

            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
                    .rotationEffect(.degrees(-45))

                Text(pinned.nickname)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)

                Text(pinned.content)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                Button {
                    viewModel?.unpinMessage()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs + 2)
        }
        .background(DesignTokens.Colors.accentOrange.opacity(0.06))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Replay Mode Button

    private func replayModeButton(vm: ChatViewModel, proxy: ScrollViewProxy) -> some View {
        Button {
            vm.exitReplayMode()
            scrollToLatest(proxy: proxy)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.down")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                if vm.unreadCount > 0 {
                    Text("새 메시지 \(vm.unreadCount)개")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                } else {
                    Text("맨 아래로")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(vm.unreadCount > 0 ? DesignTokens.Colors.onPrimary : DesignTokens.Colors.textPrimary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 6)
            .background {
                if vm.unreadCount > 0 {
                    Capsule()
                        .fill(DesignTokens.Colors.chzzkGreen)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                } else {
                    Capsule()
                        .fill(DesignTokens.Colors.surfaceElevated)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                }
            }
            .overlay {
                if vm.unreadCount == 0 {
                    Capsule()
                        .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, DesignTokens.Spacing.sm)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.06))
                    .frame(width: 72, height: 72)
                Circle()
                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.10), lineWidth: 0.5)
                    .frame(width: 72, height: 72)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(DesignTokens.Typography.custom(size: 28, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.45))
            }

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("채팅에 연결 중...")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Text("메시지가 도착하면 여기에 표시됩니다")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}
