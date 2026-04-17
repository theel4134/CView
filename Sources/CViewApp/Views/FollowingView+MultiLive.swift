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

            // 탭 모드 세션 정보 바
            if !multiLiveManager.isGridLayout || multiLiveManager.sessions.count < 2,
               let active = multiLiveManager.selectedSession {
                MLSessionInfoBar(session: active, manager: multiLiveManager)
            }

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
    @ViewBuilder
    var mlVideoOnlyArea: some View {
        ZStack {
            if multiLiveManager.sessions.isEmpty {
                MLEmptyState(onAdd: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showFollowingList = true
                    }
                })
            } else if multiLiveManager.isGridLayout && multiLiveManager.sessions.count >= 2 {
                MLGridLayout(manager: multiLiveManager, appState: appState, onAdd: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showFollowingList = true
                    }
                })
            } else {
                ForEach(multiLiveManager.sessions) { session in
                    let isActive = session.id == multiLiveManager.selectedSessionId
                    MLPlayerPane(session: session, manager: multiLiveManager, appState: appState, isActive: isActive)
                        .frame(
                            maxWidth: isActive ? .infinity : 0,
                            maxHeight: isActive ? .infinity : 0
                        )
                        .clipped()
                        .opacity(isActive ? 1 : 0)
                        .zIndex(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .transaction { $0.animation = nil }
                }
                .animation(nil, value: multiLiveManager.sessions.count)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
