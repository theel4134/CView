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
                onSettings: { withAnimation(DesignTokens.Animation.snappy) {
                    showMLSettings.toggle()
                }},
                isSettingsPanelOpen: showMLSettings,
                showFollowingList: showFollowingList,
                onFollowingToggle: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showFollowingList.toggle()
                    }
                },
                showMultiChatToggle: true,
                isMultiChatOpen: showMultiChat,
                multiChatSessionCount: chatSessionManager.sessions.count,
                onMultiChatToggle: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showMultiChat.toggle()
                    }
                }
            )

            // [중복 제거 2026-04-21] 탭 칩이 이미 채널명·라이브 제목·상태 도트를
            // 모두 표시하므로 SessionInfoBar 를 함께 노출하면 3중 중복이 발생한다.
            // 추가 상세 정보(시청자 수 등)는 영상 hover 시 MLControlOverlay 에서 노출.

            // 콘텐츠 영역
            mlVideoMainArea
        }
    }

    var mlVideoMainArea: some View {
        HStack(spacing: 0) {
            // 비디오 영역 — 비디오 콘텐츠에는 애니메이션 전파 차단
            mlVideoOnlyArea
                .transaction { $0.animation = nil }

            // 설정 슬라이드 패널
            if showMLSettings {
                MLSettingsPanel(
                    manager: multiLiveManager,
                    settingsStore: appState.settingsStore,
                    isPresented: Binding(
                        get: { ps.showMLSettings },
                        set: { ps.showMLSettings = $0 }
                    )
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // [60fps] 패널 슬라이드는 withAnimation 호출부에서 제어 — 비디오 영역 전파 방지
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
        ZStack {
            if multiLiveManager.sessions.isEmpty {
                MLEmptyState(onAdd: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showFollowingList = true
                    }
                })
            } else if !multiLiveManager.isGridLayout, let active = multiLiveManager.selectedSession {
                MLSingleChannelStage(session: active, manager: multiLiveManager, appState: appState)
            } else {
                MLGridLayout(manager: multiLiveManager, appState: appState, onAdd: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showFollowingList = true
                    }
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
