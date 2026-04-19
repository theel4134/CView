// MARK: - MLEmbeddedProcessStage.swift
// "단일 인스턴스" 모드 (Settings → useSeparateProcesses == false) 에서
// 부모 앱 멀티라이브 영역 안에 자식 프로세스 창들을 그리드/탭 으로 정렬해서 표시하는 스테이지.
//
// 기존 in-process MLEmptyState/MLGridLayout/MLPlayerPane 자리를 차지하지만 실제 영상 렌더링은
// MultiLiveProcessLauncher 가 띄운 자식 프로세스 NSWindow 가 담당한다.
// (각 채널은 별도 프로세스 → 안정성 + 리소스 분산 유지)

import SwiftUI
import AppKit
import CViewCore
import CViewUI

struct MLEmbeddedProcessStage: View {
    @Environment(AppState.self) private var appState
    let onAdd: () -> Void

    @State private var selectedTabInstanceId: String?

    private var launcher: MultiLiveProcessLauncher { appState.multiLiveLauncher }

    private var layoutMode: MultiLiveProcessLayoutMode {
        appState.settingsStore.multiLive.processLayoutMode
    }

    var body: some View {
        let instances = launcher.instances.values.sorted { $0.launchedAt < $1.launchedAt }

        ZStack {
            // [Crash fix 2026-04-19] reporter 는 단 하나만 마운트한다.
            // 두 개를 동시에 마운트하면 layout() 콜백이 중첩 발생 →
            // @Observable 변경이 누적되어 SwiftUI/AppKit 레이아웃 재진입 사이클을 유발.
            if instances.isEmpty {
                // 첫 launch 이전: stage 전체 영역을 host frame 으로 사용 (자식 창 배치 좌표 산출용)
                EmbeddedHostFrameReporter { frame in
                    launcher.embeddedHostFrame = frame
                }
                .allowsHitTesting(false)

                MLEmptyState(onAdd: onAdd)
            } else {
                VStack(spacing: 0) {
                    // 탭 칩 + 레이아웃 picker (그리드/탭 전환)
                    headerControls(instances: instances)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.sm)

                    Divider().background(DesignTokens.Glass.borderColor)

                    // 실제 자식 프로세스 창이 정렬될 호스트 영역 — 헤더/구분선을 뺀 정확한 좌표
                    ZStack {
                        Color.black.opacity(0.92)
                        EmbeddedHostFrameReporter { frame in
                            launcher.embeddedHostFrame = frame
                            launcher.applyLayout(
                                mode: layoutMode,
                                selectedInstanceId: selectedTabInstanceId,
                                presentation: .embedded
                            )
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
        .onChange(of: layoutMode) { _, newMode in
            if newMode == .tab, selectedTabInstanceId == nil {
                selectedTabInstanceId = instances.first?.id
            }
            launcher.applyLayout(mode: newMode, selectedInstanceId: selectedTabInstanceId, presentation: .embedded)
        }
        .onChange(of: launcher.instances.count) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                launcher.applyLayout(
                    mode: layoutMode,
                    selectedInstanceId: selectedTabInstanceId,
                    presentation: .embedded
                )
            }
        }
        .onAppear {
            if selectedTabInstanceId == nil {
                selectedTabInstanceId = instances.first?.id
            }
        }
    }

    @ViewBuilder
    private func headerControls(instances: [MultiLiveChildInstance]) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 탭 칩 (선택 채널 강조)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(instances) { inst in
                        let isActive = (selectedTabInstanceId ?? instances.first?.id) == inst.id
                        Button {
                            selectedTabInstanceId = inst.id
                            if layoutMode == .tab {
                                launcher.applyLayout(mode: .tab, selectedInstanceId: inst.id, presentation: .embedded)
                            } else {
                                launcher.activate(instanceId: inst.id)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isActive ? DesignTokens.Colors.accentPurple : DesignTokens.Colors.textTertiary)
                                    .frame(width: 6, height: 6)
                                Text(inst.channelName)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(isActive ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                                Button {
                                    launcher.terminateChild(instanceId: inst.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .help("채널 닫기")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(isActive ? DesignTokens.Colors.accentPurple.opacity(0.18) : DesignTokens.Colors.surfaceElevated)
                            )
                            .overlay(
                                Capsule().stroke(isActive ? DesignTokens.Colors.accentPurple.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // 그리드/탭 picker
            Picker("", selection: Binding(
                get: { appState.settingsStore.multiLive.processLayoutMode },
                set: { newValue in
                    var s = appState.settingsStore.multiLive
                    s.processLayoutMode = newValue
                    appState.settingsStore.multiLive = s
                }
            )) {
                ForEach(MultiLiveProcessLayoutMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()

            Button(action: onAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("채널 추가")
                        .font(DesignTokens.Typography.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(DesignTokens.Colors.accentPurple))
            }
            .buttonStyle(.plain)
        }
    }
}
