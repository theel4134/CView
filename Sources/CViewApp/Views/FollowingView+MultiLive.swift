import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - FollowingView + Multi-Live Panel

extension FollowingView {

    var multiLiveInlinePanel: some View {
        VStack(spacing: 0) {
            // 통합 뷰: 비디오 + 사이드 채팅 (탭 분리 없음)
            mlVideoContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(!multiLiveManager.sessions.isEmpty ? DesignTokens.Colors.background : DesignTokens.Colors.background)
        // 비디오 영역은 패널 슬라이드 애니메이션 전파 차단 (Metal 렌더링 보호)
        .transaction { $0.animation = nil }
        .task {
            if multiLiveManager.sessions.isEmpty {
                await multiLiveManager.restoreState(appState: appState)
            }
        }
        .alert("채널 추가 실패", isPresented: Binding(
            get: { mlAddError != nil },
            set: { if !$0 { mlAddError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(mlAddError ?? "")
        }
    }

    // MARK: - ML Video Content (기존 멀티라이브)

    var mlVideoContent: some View {
        VStack(spacing: 0) {
            // 멀티라이브 탭 바
            MLTabBar(
                manager: multiLiveManager,
                isGridLayout: Binding(
                    get: { multiLiveManager.isGridLayout },
                    set: { multiLiveManager.isGridLayout = $0 }
                ),
                onAdd: {},
                isAddPanelOpen: true,
                showMultiChatToggle: true,
                isMultiChatOpen: showMultiChat,
                multiChatSessionCount: chatSessionManager.sessions.count,
                onMultiChatToggle: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showMultiChat.toggle()
                    }
                },
                includeWindowTopInset: false
            )

            // [중복 제거 2026-04-21] 탭 칩이 이미 채널명·라이브 제목·상태 도트를
            // 모두 표시하므로 SessionInfoBar 를 함께 노출하면 3중 중복이 발생한다.
            // 추가 상세 정보(시청자 수 등)는 영상 hover 시 MLControlOverlay 에서 노출.

            // 콘텐츠 영역
            mlVideoMainArea
        }
    }

    var mlVideoMainArea: some View {
        // [Light Live Hub] 설정 패널은 우측 Drawer로 분리되어 중앙 stage는 미디어만 렌더.
        mlVideoOnlyArea
            .transaction { $0.animation = nil }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 비디오 전용 영역 (채팅 제거됨 — 채팅은 멀티채팅 패널에서 관리)
    ///
    /// [프로세스 격리 2026-04-19] 라이브 메뉴 인라인 패널은 사용자가 부모 창 안에서
    /// 영상을 보기를 기대하므로, `useSeparateProcesses` 설정과 무관하게 항상
    /// 레거시 in-process MLGridLayout으로 렌더링한다 (자식 프로세스 분리 모드는 독립 창 컨텍스트용).
    /// `MultiLiveManager.addSession(…, presentationOverride: .embedded)` 이 launcher 경로를 건너뛰고
    /// `multiLiveManager.sessions` 에 세션을 추가 → 이 레이아웃이 VLC 플레이어를 직접 임베드.
    ///
    /// [Single View 2026-04-19] 탭 모드(`isGridLayout == false`) 일 때는 `MLSingleChannelStage`
    /// 로 라우팅 — 채널별 싱글 화면처럼 헤더 오버레이(채널명/제목/시청자수) 와 함께 풀 임베드.
    @ViewBuilder
    var mlVideoOnlyArea: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if multiLiveManager.sessions.isEmpty {
                    MLEmptyState(onAdd: {
                        withAnimation(DesignTokens.Animation.snappy) {
                            ps.followingSheetState = .expanded
                        }
                    })
                } else if !multiLiveManager.isGridLayout, let active = multiLiveManager.selectedSession {
                    MLSingleChannelStage(
                        session: active,
                        manager: multiLiveManager,
                        appState: appState,
                        onShowFollowingSheet: {
                            withAnimation(DesignTokens.Animation.snappy) {
                                ps.followingSheetState = .expanded
                            }
                        }
                    )
                } else {
                    MLGridLayout(manager: multiLiveManager, appState: appState, onAdd: {
                        withAnimation(DesignTokens.Animation.snappy) {
                            ps.followingSheetState = .expanded
                        }
                    })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // [2026-04-28 신규] Stage Tool Popover — 우측 상단
            if !multiLiveManager.sessions.isEmpty {
                stageToolBar
                    .padding(.top, DesignTokens.Spacing.sm)
                    .padding(.trailing, DesignTokens.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stage Tool Bar (우측 상단 floating)

    @ViewBuilder
    private var stageToolBar: some View {
        HStack(spacing: 6) {
            // 팔로잉 시트 on/off 토글
            Button {
                withAnimation(DesignTokens.Animation.snappy) {
                    ps.isFollowingSheetHidden.toggle()
                }
            } label: {
                Image(systemName: ps.isFollowingSheetHidden ? "rectangle.portrait" : "rectangle.bottomthird.inset.filled")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(ps.isFollowingSheetHidden ? .white.opacity(0.6) : DesignTokens.Colors.chzzkGreen)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(!ps.isFollowingSheetHidden ? DesignTokens.Colors.chzzkGreen.opacity(0.18) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .help(ps.isFollowingSheetHidden ? "팔로잉 시트 표시" : "팔로잉 시트 숨기기")

            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 0.5, height: 14)

            stageToolButton(.quality, icon: "slider.horizontal.3", help: "재생 품질")
            stageToolButton(.tools, icon: "wrench.and.screwdriver", help: "도구")
            stageToolButton(.layout, icon: "square.grid.2x2", help: "레이아웃")
            stageToolButton(.reconnect, icon: "arrow.triangle.2.circlepath", help: "재연결")
            stageToolButton(.network, icon: "network", help: "네트워크 모니터")
            stageToolButton(.metrics, icon: "chart.line.uptrend.xyaxis", help: "메트릭")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.black.opacity(0.42))
        )
        .overlay(
            Capsule()
                .strokeBorder(DesignTokens.Glass.borderColorLight.opacity(0.3), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func stageToolButton(_ tool: StageToolPopover, icon: String, help: String) -> some View {
        let isActive = ps.stageToolPopover == tool
        Button {
            // network/metrics는 별도 창 — popover 대신 즉시 창 열기
            switch tool {
            case .network:
                openWindow(id: "ml-network-window")
            case .metrics:
                openWindow(id: "ml-metrics-window")
            default:
                ps.stageToolPopover = isActive ? .none : tool
            }
        } label: {
            Image(systemName: icon)
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? DesignTokens.Colors.chzzkGreen : .white.opacity(0.85))
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? DesignTokens.Colors.chzzkGreen.opacity(0.18) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .popover(isPresented: Binding(
            get: { ps.stageToolPopover == tool && (tool == .quality || tool == .tools || tool == .layout || tool == .reconnect) },
            set: { if !$0 { ps.stageToolPopover = .none } }
        ), arrowEdge: .top) {
            stageToolPopoverContent(tool)
                .frame(width: 280)
                .padding(DesignTokens.Spacing.md)
        }
    }

    @ViewBuilder
    private func stageToolPopoverContent(_ tool: StageToolPopover) -> some View {
        switch tool {
        case .quality:
            VStack(alignment: .leading, spacing: 8) {
                Text("재생 품질")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Text("선택된 세션의 화질을 조정합니다. 자세한 설정은 도구 메뉴에서 확인하세요.")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Divider()
                Text("(개별 세션 컨트롤은 그리드의 채널 카드 hover 시 표시되는 컨트롤 오버레이를 사용합니다.)")
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        case .tools:
            VStack(alignment: .leading, spacing: 8) {
                Text("도구")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Button {
                    openWindow(id: "system-usage-window")
                    ps.stageToolPopover = .none
                } label: {
                    Label("시스템 사용률 모니터", systemImage: "cpu")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button {
                    openWindow(id: "statistics-window")
                    ps.stageToolPopover = .none
                } label: {
                    Label("통계 창", systemImage: "chart.bar.doc.horizontal")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider()
                Button {
                    Task { await multiLiveManager.stopAll() }
                    ps.stageToolPopover = .none
                } label: {
                    Label("모든 채널 해제", systemImage: "xmark.circle")
                        .foregroundStyle(DesignTokens.Colors.live)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        case .network, .metrics, .none:
            EmptyView()
        case .layout:
            // [2026-04-28] 디자인 사료 §2 — Stage Layout Popover
            VStack(alignment: .leading, spacing: 8) {
                Text("레이아웃")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Text("멀티라이브 그리드 모드를 전환합니다.")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Divider()
                Button {
                    multiLiveManager.isGridLayout = true
                    ps.stageToolPopover = .none
                } label: {
                    Label("그리드 (2×2)", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(multiLiveManager.isGridLayout ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textPrimary)
                }
                .buttonStyle(.plain)
                Button {
                    multiLiveManager.isGridLayout = false
                    ps.stageToolPopover = .none
                } label: {
                    Label("싱글 포커스", systemImage: "rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(!multiLiveManager.isGridLayout ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textPrimary)
                }
                .buttonStyle(.plain)
                Divider()
                Text("현재 \(multiLiveManager.sessions.count)개 세션 활성")
                    .font(DesignTokens.Typography.custom(size: 10.5, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        case .reconnect:
            // [2026-04-28] 디자인 사료 §2 — Stage Reconnect Popover
            VStack(alignment: .leading, spacing: 8) {
                Text("재연결")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                Text("스트림과 채팅 세션을 다시 연결합니다.")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Divider()
                Button {
                    Task {
                        guard let api = appState.apiClient else { return }
                        for s in multiLiveManager.sessions {
                            await s.refreshStream(using: api, appState: appState)
                        }
                    }
                    ps.stageToolPopover = .none
                } label: {
                    Label("모든 스트림 재연결", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button {
                    Task { await chatSessionManager.reconnectAll() }
                    ps.stageToolPopover = .none
                } label: {
                    Label("모든 채팅 재연결", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
