// MARK: - MultiLiveView.swift
import SwiftUI
import CViewCore
import CViewPlayer
import CViewNetworking
import CViewUI

struct MultiLiveView: View {
    @Environment(AppState.self) private var appState
    /// AppState에서 공유된 매니저 — 화면 전환 시에도 채널 목록 유지
    private var manager: MultiLiveManager { appState.multiLiveManager }
    @State private var showAddChannel = false
    @State private var showSettings = false
    @State private var addError: String?
    // isGridLayout은 뷰 재생성 시 초기화 방지를 위해 manager에서 관리

    var body: some View {
        HStack(spacing: 0) {
            // ── 메인 영역 ──
            VStack(spacing: 0) {
                MLTabBar(
                    manager: manager,
                    isGridLayout: Binding(
                        get: { manager.isGridLayout },
                        set: { manager.isGridLayout = $0 }
                    ),
                    onAdd: { withAnimation(DesignTokens.Animation.snappy) {
                        showAddChannel.toggle()
                        if showAddChannel { showSettings = false }
                    }},
                    isAddPanelOpen: showAddChannel,
                    onSettings: { withAnimation(DesignTokens.Animation.snappy) {
                        showSettings.toggle()
                        if showSettings { showAddChannel = false }
                    }},
                    isSettingsPanelOpen: showSettings
                )

                // 탭 모드 세션 정보 바
                if !manager.isGridLayout || manager.sessions.count < 2,
                   let active = manager.selectedSession {
                    MLSessionInfoBar(session: active, manager: manager)
                }

                // ── 콘텐츠 ──
                ZStack {
                    if manager.sessions.isEmpty {
                        MLEmptyState(onAdd: {
                            withAnimation(DesignTokens.Animation.snappy) {
                                showAddChannel = true
                            }
                        })
                    } else if manager.isGridLayout && manager.sessions.count >= 2 {
                        MLGridLayout(manager: manager, appState: appState, onAdd: {
                            withAnimation(DesignTokens.Animation.snappy) {
                                showAddChannel = true
                            }
                        })
                    } else {
                        // [VLC 안정성] ForEach + opacity 전환 — drawable 연결 유지
                        ForEach(manager.sessions) { session in
                            let isActive = session.id == manager.selectedSessionId
                            MLPlayerPane(session: session, appState: appState, isActive: isActive)
                                .opacity(isActive ? 1 : 0)
                                .zIndex(isActive ? 1 : 0)
                                .allowsHitTesting(isActive)
                                .transaction { $0.animation = nil }
                        }
                        .animation(nil, value: manager.sessions.count)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // [Depth] 메인 콘텐츠가 슬라이딩 패널보다 앞에 떠 있는 느낌
            .shadow(color: .black.opacity(0.35), radius: 12, x: 4, y: 0)
            .zIndex(1)

            // ── 채널 추가 패널 (push slide) ──
            if showAddChannel {
                MLAddChannelPanel(
                    manager: manager,
                    appState: appState,
                    isPresented: $showAddChannel,
                    onError: { addError = $0 }
                )
                .environment(appState)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(DesignTokens.Animation.contentTransition, value: showAddChannel)
                .zIndex(0)
            }

            // ── 설정 패널 (push slide) ──
            if showSettings {
                MLSettingsPanel(
                    manager: manager,
                    settingsStore: appState.settingsStore,
                    isPresented: $showSettings
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(DesignTokens.Animation.contentTransition, value: showSettings)
                .zIndex(0)
            }
        }
        .background(manager.sessions.isEmpty ? DesignTokens.Colors.background : Color.black)
        .onKeyPress { handleMultiLiveShortcut($0) }
        .onKeyPress(.escape) {
            if showAddChannel {
                withAnimation(DesignTokens.Animation.contentTransition) { showAddChannel = false }
                return .handled
            }
            if showSettings {
                withAnimation(DesignTokens.Animation.contentTransition) { showSettings = false }
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

    // MARK: - Keyboard Shortcuts

    /// 활성 세션의 PlayerViewModel에 키보드 단축키를 적용
    private func handleMultiLiveShortcut(_ press: KeyPress) -> KeyPress.Result {
        let shortcuts = appState.settingsStore.keyboard

        // 활성 세션 결정: 탭 모드 → 선택된 세션, 그리드 모드 → 오디오 활성 세션
        let activeSession: MultiLiveSession? = if !manager.isGridLayout {
            manager.selectedSession
        } else {
            manager.sessions.first { $0.id == (manager.audioSessionId ?? manager.selectedSessionId) }
        }
        guard let session = activeSession else { return .ignored }
        let vm = session.playerViewModel

        for action in ShortcutAction.allCases {
            let binding = shortcuts.binding(for: action)
            guard matchesBinding(press, binding) else { continue }

            switch action {
            case .togglePlay:
                Task { await vm.togglePlayPause() }
            case .toggleMute:
                session.setMuted(!session.isMuted)
            case .toggleFullscreen:
                NSApp.keyWindow?.toggleFullScreen(nil)
            case .toggleChat:
                break // 채팅은 멀티채팅 패널에서 관리
            case .togglePiP:
                if let vlcEngine = vm.playerEngine as? VLCPlayerEngine {
                    PiPController.shared.startPiP(vlcEngine: vlcEngine)
                }
            case .screenshot:
                vm.takeScreenshot()
            case .volumeUp:
                vm.setVolume(min(1.0, vm.volume + 0.05))
                if session.isMuted { session.setMuted(false) }
            case .volumeDown:
                vm.setVolume(max(0.0, vm.volume - 0.05))
            }
            return .handled
        }
        return .ignored
    }

    /// KeyPress가 KeyBinding과 일치하는지 확인
    private func matchesBinding(_ press: KeyPress, _ binding: KeyBinding) -> Bool {
        let mods = binding.modifiers
        if mods.contains(.command)  != press.modifiers.contains(.command)  { return false }
        if mods.contains(.shift)    != press.modifiers.contains(.shift)    { return false }
        if mods.contains(.option)   != press.modifiers.contains(.option)   { return false }
        if mods.contains(.control)  != press.modifiers.contains(.control)  { return false }

        switch binding.key {
        case "space":      return press.key == .space
        case "upArrow":    return press.key == .upArrow
        case "downArrow":  return press.key == .downArrow
        case "leftArrow":  return press.key == .leftArrow
        case "rightArrow": return press.key == .rightArrow
        case "return":     return press.key == .return
        case "escape":     return press.key == .escape
        case "tab":        return press.key == .tab
        case "delete":     return press.key == .delete
        default:
            return press.characters.lowercased() == binding.key.lowercased()
        }
    }
}

