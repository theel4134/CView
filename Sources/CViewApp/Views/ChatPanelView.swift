// MARK: - ChatPanelView.swift
// CViewApp - 프리미엄 채팅 패널
// Design: Glass Morphism Dark Chat + Modern Layout

import SwiftUI
import Combine
import CViewCore
import CViewChat
import CViewUI

// MARK: - Chat Panel (Header + Messages + Input)

struct ChatPanelView: View {
    let chatVM: ChatViewModel?
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            chatHeader

            // Messages list
            ChatMessagesView(viewModel: chatVM)

            // Input area
            ChatInputView(viewModel: chatVM)
        }
        .background(DesignTokens.Colors.surfaceBase.opacity(0.85))
        .background(.ultraThinMaterial)
        .sheet(isPresented: Binding(
            get: { chatVM?.showExportSheet ?? false },
            set: { chatVM?.showExportSheet = $0 }
        )) {
            ChatExportView()
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            
            Text("채팅")
                .font(DesignTokens.Typography.bodySemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            // Connection status pill — Glass
            HStack(spacing: 5) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: connectionColor.opacity(0.6), radius: 4)

                Text(connectionText)
                    .font(DesignTokens.Typography.footnoteMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs + 1)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(connectionColor.opacity(0.25), lineWidth: 0.5)
            }

            // Chat export — Glass circle
            Button {
                chatVM?.showExportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .help("채팅 내보내기")
            .disabled(chatVM?.chatHistory.isEmpty ?? true)

            // Chat settings — Glass circle
            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.border.opacity(0.15))
                .frame(height: 0.5)
        }
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

// MARK: - Chat Messages View

struct ChatMessagesView: View {
    let viewModel: ChatViewModel?

    /// ScrollView가 화면에 표시 중인지 추적 — 백그라운드 전환에 의한 잘못된 replay mode 진입 방지
    @State private var isScrollViewVisible = true

    var body: some View {
        VStack(spacing: 0) {
            // Pinned message banner
            if let pinned = viewModel?.pinnedMessage {
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let viewModel {
                            if viewModel.messages.isEmpty {
                                chatEmptyState
                            } else {
                                ForEach(viewModel.messages) { message in
                                    EquatableChatMessageRow(message: message, chatVM: viewModel)
                                        .id(message.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.xxs)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                }
                .defaultScrollAnchor(.bottom)
                // onScrollGeometryChange: 실제 스크롤 위치 기반 감지
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let maxScrollY = geometry.contentSize.height - geometry.containerSize.height
                    guard maxScrollY > 0 else { return true }
                    let distanceFromBottom = maxScrollY - geometry.contentOffset.y
                    return distanceFromBottom <= 80
                } action: { _, isNearBottom in
                    guard isScrollViewVisible else { return }
                    viewModel?.onScrollPositionChanged(isNearBottom: isNearBottom)
                }
                .onAppear {
                    isScrollViewVisible = true
                    if viewModel?.isAutoScrollEnabled == true,
                       let lastId = viewModel?.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                .onDisappear {
                    isScrollViewVisible = false
                }
                // 새 메시지 도착 시 자동 스크롤 (애니메이션 없이 즉시 이동 — 치지직 방식)
                .onChange(of: viewModel?.messages.last?.id) { _, _ in
                    if viewModel?.isAutoScrollEnabled == true && viewModel?.isReplayMode != true {
                        if let lastId = viewModel?.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                // 앱이 다시 포그라운드로 돌아올 때 자동 스크롤 복원
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    guard viewModel?.isAutoScrollEnabled == true,
                          viewModel?.isReplayMode != true,
                          let lastId = viewModel?.messages.last?.id else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
                // Floating scroll-to-bottom button
                .overlay(alignment: .bottom) {
                    if let vm = viewModel, vm.isReplayMode {
                        Button {
                            vm.exitReplayMode()
                            if let lastId = vm.messages.last?.id {
                                withAnimation(DesignTokens.Animation.chatScroll) {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
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
                            .foregroundStyle(vm.unreadCount > 0 ? Color.black : DesignTokens.Colors.textPrimary)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, 6)
                            .background {
                                if vm.unreadCount > 0 {
                                    Capsule()
                                        .fill(DesignTokens.Colors.chzzkGreen)
                                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                                } else {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                                }
                            }
                            .overlay {
                                if vm.unreadCount == 0 {
                                    Capsule()
                                        .strokeBorder(.white.opacity(DesignTokens.Glass.borderOpacityLight), lineWidth: 0.5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, DesignTokens.Spacing.sm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DesignTokens.Animation.snappy, value: viewModel?.isReplayMode)
            }
        } // VStack
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.08))
                    .frame(width: 72, height: 72)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(DesignTokens.Typography.custom(size: 28, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.5))
            }

            VStack(spacing: 6) {
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
