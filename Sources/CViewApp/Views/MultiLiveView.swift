// MARK: - MultiLiveView.swift
import SwiftUI
import CViewCore
import CViewPlayer
import CViewNetworking
import CViewUI

struct MultiLiveView: View {
    @Environment(AppState.self) private var appState
    /// AppState에서 공유된 매니저 — 화면 전환 시에도 채널 목록 유지
    private var manager: MultiLiveSessionManager { appState.multiLiveManager }
    @State private var showAddChannel = false
    @State private var addError: String?
    // isGridLayout은 뷰 재생성 시 초기화 방지를 위해 manager에서 관리

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.ignoresSafeArea()

            // ── 메인 콘텐츠 ──────────────────────────────────────
            VStack(spacing: 0) {
                MLTabBar(
                    manager: manager,
                    isGridLayout: Binding(
                        get: { manager.isGridLayout },
                        set: { manager.isGridLayout = $0 }
                    ),
                    onAdd: { withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showAddChannel.toggle()
                    }},
                    isAddPanelOpen: showAddChannel
                )
                ZStack {
                    if manager.sessions.isEmpty {
                        MLEmptyState(onAdd: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                showAddChannel = true
                            }
                        })
                    } else if manager.isGridLayout && manager.sessions.count >= 2 {
                        MLGridLayout(manager: manager, appState: appState, onAdd: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                showAddChannel = true
                            }
                        })
                    } else {
                        // 선택된 세션만 렌더링 — .opacity(0) 방식은 SwiftUI가 모든 숨겨진
                        // 패널에 대해 오프스크린 GPU 버퍼를 유지하므로 조건부 렌더링으로 교체.
                        // 언더라이닝 PlayerViewModel·NSView 는 session 객체에 종속되므로
                        // 탭 전환 후에도 재생이 유지됨.
                        if let selected = manager.sessions.first(where: { $0.id == manager.selectedSessionId }) {
                            MLPlayerPane(session: selected, appState: appState)
                                .id(selected.id)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // ── 슬라이드 패널 뒷배경 (탭으로 닫기) ───────────────
            if showAddChannel {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            showAddChannel = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
            }

            // ── 채널 추가 슬라이드 패널 ───────────────────────────
            if showAddChannel {
                MLAddChannelPanel(
                    manager: manager,
                    appState: appState,
                    isPresented: $showAddChannel,
                    onError: { addError = $0 }
                )
                .environment(appState)
                .transition(.asymmetric(
                    insertion:  .move(edge: .trailing).combined(with: .opacity),
                    removal:    .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(11)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showAddChannel)
        .frame(minWidth: 740, minHeight: 520)
        // ESC 키로 패널 닫기
        .onKeyPress(.escape) {
            if showAddChannel {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showAddChannel = false }
                return .handled
            }
            return .ignored
        }
        .alert("채널 추가 실패", isPresented: Binding(
            get: { addError != nil },
            set: { if !$0 { addError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(addError ?? "")
        }
    }
}

