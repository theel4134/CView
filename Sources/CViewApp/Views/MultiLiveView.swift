// MARK: - MultiLiveView.swift
// CViewApp — 멀티라이브 메인 뷰
// AVPlayer 기반 최대 4채널 동시 시청 + 오른쪽 채팅 패널

import SwiftUI
import CViewCore
import CViewPlayer
import CViewChat

struct MultiLiveView: View {

    @Environment(AppState.self) private var appState
    @Namespace private var layoutNamespace
    @State private var showChatSettings = false

    private var manager: MultiLiveManager {
        appState.multiLiveManager
    }

    var body: some View {
        ZStack {
            if manager.sessions.isEmpty {
                emptyStateView
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                HStack(spacing: 0) {
                    // 왼쪽: 비디오 영역 + 탭바
                    VStack(spacing: 0) {
                        ZStack {
                            if manager.isGridLayout {
                                gridLayout
                                    .transition(.opacity)
                            } else {
                                tabLayout
                                    .transition(.opacity)
                            }
                        }
                        .animation(DesignTokens.Animation.contentTransition, value: manager.isGridLayout)

                        MultiLiveTabBar(manager: manager)
                    }

                    // 오른쪽: 채팅 패널
                    if manager.showChat, let selected = manager.selectedSession {
                        multiLiveChatPanel(session: selected)
                            .frame(width: 320)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(DesignTokens.Animation.spring, value: manager.showChat)
                .animation(DesignTokens.Animation.spring, value: manager.selectedSessionId)
                .transition(.opacity)
            }
        }
        .background(Color.black)
        .animation(DesignTokens.Animation.smooth, value: manager.sessions.isEmpty)
        .sheet(isPresented: Binding(
            get: { manager.showAddSheet },
            set: { manager.showAddSheet = $0 }
        )) {
            MultiLiveAddSheet(manager: manager)
        }
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - 탭 레이아웃 (선택 세션 전체 화면)

    @ViewBuilder
    private var tabLayout: some View {
        if let selected = manager.selectedSession {
            MultiLivePlayerPane(session: selected, isSelected: true, isCompact: false)
                .id(selected.id)
                .transition(.opacity)
        }
    }

    // MARK: - 그리드 레이아웃 (동적 배치)

    private var gridLayout: some View {
        GeometryReader { geo in
            let count = manager.sessions.count
            let cols = count <= 2 ? count : 2
            let rows = count <= 2 ? 1 : 2
            let gap: CGFloat = 2
            let cellHeight = (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(max(rows, 1))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: max(cols, 1)),
                spacing: gap
            ) {
                ForEach(manager.sessions) { session in
                    MultiLivePlayerPane(
                        session: session,
                        isSelected: session.id == manager.selectedSessionId,
                        isCompact: true
                    )
                    .frame(height: cellHeight)
                    .onTapGesture {
                        withAnimation(DesignTokens.Animation.snappy) {
                            manager.selectSession(id: session.id)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                }
            }
            .animation(DesignTokens.Animation.spring, value: manager.sessions.map(\.id))
        }
    }

    // MARK: - 빈 상태

    private var emptyStateView: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            multiLiveIcon
                .padding(.bottom, DesignTokens.Spacing.sm)

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("멀티라이브")
                    .font(.title.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text("최대 4개 채널을 동시에 시청하세요")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            Button {
                withAnimation(DesignTokens.Animation.spring) {
                    manager.showAddSheet = true
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "plus.circle.fill")
                    Text("채널 추가")
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Colors.chzzkGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var multiLiveIcon: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                iconCell(delay: 0)
                iconCell(delay: 0.15)
            }
            GridRow {
                iconCell(delay: 0.3)
                iconCell(delay: 0.45)
            }
        }
    }

    private func iconCell(delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: [DesignTokens.Colors.chzzkGreen.opacity(0.3), DesignTokens.Colors.chzzkGreen.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.3), lineWidth: 1)
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.6))
            }
            .frame(width: 48, height: 36)
    }

    // MARK: - 채팅 패널

    private func multiLiveChatPanel(session: MultiLiveSession) -> some View {
        VStack(spacing: 0) {
            // 채팅 헤더
            HStack(spacing: DesignTokens.Spacing.xs) {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen)
                    .frame(width: 6, height: 6)
                Text(session.channelName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Button {
                    withAnimation(DesignTokens.Animation.spring) {
                        manager.showChat = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(DesignTokens.Glass.borderOpacity))
                    .frame(height: 0.5)
            }

            // 채팅 콘텐츠
            ChatPanelView(chatVM: session.chatViewModel, onOpenSettings: {
                showChatSettings = true
            })
            .sheet(isPresented: $showChatSettings) {
                MultiLiveChatSettingsView(chatVM: session.chatViewModel)
            }
        }
        .background(DesignTokens.Colors.surfaceOverlay)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(DesignTokens.Glass.borderOpacity))
                .frame(width: 0.5)
        }
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if !manager.sessions.isEmpty {
                // 채팅 토글
                Button {
                    withAnimation(DesignTokens.Animation.spring) {
                        manager.showChat.toggle()
                    }
                } label: {
                    Image(systemName: manager.showChat ? "message.fill" : "message")
                }
                .help(manager.showChat ? "채팅 숨기기" : "채팅 보기")

                // 그리드/탭 토글
                Button {
                    withAnimation(DesignTokens.Animation.contentTransition) {
                        manager.isGridLayout.toggle()
                    }
                } label: {
                    Image(systemName: manager.isGridLayout ? "rectangle.split.1x2" : "rectangle.split.2x2")
                }
                .help(manager.isGridLayout ? "탭 모드" : "그리드 모드")

                // 전체 종료
                Button {
                    Task {
                        await manager.removeAllSessions()
                    }
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("모든 세션 종료")
            }

            Button {
                manager.showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("채널 추가")
            .disabled(!manager.canAddSession)
        }
    }
}

// MARK: - MultiLive 채팅 설정 뷰

private struct MultiLiveChatSettingsView: View {
    let chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("채팅 설정", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.subhead)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // 글꼴 크기
                    settingsRow(label: "글꼴 크기", icon: "textformat") {
                        HStack(spacing: 6) {
                            Text("가").font(.system(size: 10)).foregroundStyle(DesignTokens.Colors.textTertiary)
                            Slider(value: Binding(
                                get: { chatVM.fontSize },
                                set: { chatVM.fontSize = $0 }
                            ), in: 10...24, step: 1)
                            .tint(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 110)
                            Text("가").font(.system(size: 17)).foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("\(Int(chatVM.fontSize))pt")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                .frame(width: 34)
                        }
                    }

                    // 뱃지 표시
                    settingsRow(label: "뱃지 표시", icon: "shield.fill") {
                        Toggle("", isOn: Binding(
                            get: { chatVM.showBadge },
                            set: { chatVM.showBadge = $0 }
                        ))
                        .toggleStyle(.switch)
                        .tint(DesignTokens.Colors.chzzkGreen)
                    }

                    // 후원 메시지만 표시
                    settingsRow(label: "후원 메시지만", icon: "gift.fill") {
                        Toggle("", isOn: Binding(
                            get: { chatVM.showDonationsOnly },
                            set: { chatVM.showDonationsOnly = $0 }
                        ))
                        .toggleStyle(.switch)
                        .tint(DesignTokens.Colors.chzzkGreen)
                    }

                    // 타임스탬프 표시
                    settingsRow(label: "타임스탬프 표시", icon: "clock") {
                        Toggle("", isOn: Binding(
                            get: { chatVM.showTimestamp },
                            set: { chatVM.showTimestamp = $0 }
                        ))
                        .toggleStyle(.switch)
                        .tint(DesignTokens.Colors.chzzkGreen)
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
        }
        .frame(width: 380, height: 350)
    }

    @ViewBuilder
    private func settingsRow<Control: View>(label: String, icon: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(DesignTokens.Typography.bodySemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            control()
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }
}
