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
        .background(!multiLiveManager.sessions.isEmpty ? Color.black : DesignTokens.Colors.background)
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
                onAdd: { withAnimation(DesignTokens.Animation.snappy) {
                    showMLAddChannel.toggle()
                    if showMLAddChannel { showMLSettings = false }
                }},
                isAddPanelOpen: showMLAddChannel,
                onSettings: { withAnimation(DesignTokens.Animation.snappy) {
                    showMLSettings.toggle()
                    if showMLSettings { showMLAddChannel = false }
                }},
                isSettingsPanelOpen: showMLSettings,
                hideFollowingList: hideFollowingList,
                onToggleFollowingList: {
                    withAnimation(DesignTokens.Animation.glassAppear) {
                        hideFollowingList = false
                    }
                }
            )

            // 콘텐츠 영역
            mlVideoMainArea
        }
    }

    var mlVideoMainArea: some View {
        HStack(spacing: 0) {
            // 비디오 영역 — 비디오 콘텐츠에는 애니메이션 전파 차단
            mlVideoOnlyArea
                .transaction { $0.animation = nil }

            // 채널 추가 슬라이드 패널
            if showMLAddChannel {
                MLAddChannelPanel(
                    manager: multiLiveManager,
                    appState: appState,
                    isPresented: Binding(
                        get: { ps.showMLAddChannel },
                        set: { ps.showMLAddChannel = $0 }
                    ),
                    onError: { mlAddError = $0 }
                )
                .environment(appState)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

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
        .animation(DesignTokens.Animation.contentTransition, value: showMLAddChannel)
        .animation(DesignTokens.Animation.contentTransition, value: showMLSettings)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 비디오 전용 영역 (채팅 제거됨 — 채팅은 멀티채팅 패널에서 관리)
    @ViewBuilder
    var mlVideoOnlyArea: some View {
        ZStack {
            if multiLiveManager.sessions.isEmpty {
                MLEmptyState(onAdd: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showMLAddChannel = true
                    }
                })
            } else if multiLiveManager.isGridLayout && multiLiveManager.sessions.count >= 2 {
                MLGridLayout(manager: multiLiveManager, appState: appState, onAdd: {
                    withAnimation(DesignTokens.Animation.snappy) {
                        showMLAddChannel = true
                    }
                })
            } else {
                ForEach(multiLiveManager.sessions) { session in
                    let isActive = session.id == multiLiveManager.selectedSessionId
                    MLPlayerPane(session: session, appState: appState, isActive: isActive)
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
