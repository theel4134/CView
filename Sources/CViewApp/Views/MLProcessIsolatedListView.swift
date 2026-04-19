// MARK: - MLProcessIsolatedListView.swift
// "멀티라이브 프로세스 격리" 모드(Settings → useSeparateProcesses) 가 켜져 있을 때
// 메인 윈도우의 멀티라이브 영역에 표시되는 컨트롤러 뷰.
// in-process 그리드 대신 launcher 가 띄운 자식 인스턴스(별도 프로세스) 카드 리스트를 보여줍니다.

import SwiftUI
import AppKit
import CViewCore
import CViewUI

struct MLProcessIsolatedListView: View {
    @Environment(AppState.self) private var appState
    let onAdd: () -> Void

    @State private var selectedTabInstanceId: String?

    private var launcher: MultiLiveProcessLauncher { appState.multiLiveLauncher }

    private var layoutMode: MultiLiveProcessLayoutMode {
        appState.settingsStore.multiLive.processLayoutMode
    }

    private var presentationMode: MultiLiveProcessPresentation {
        appState.settingsStore.multiLive.effectivePresentation
    }

    var body: some View {
        let instances = launcher.instances.values.sorted { $0.launchedAt < $1.launchedAt }

        VStack(spacing: 0) {
            // 헤더
            header

            Divider().background(DesignTokens.Glass.borderColor)

            if instances.isEmpty {
                emptyState
            } else if presentationMode == .embedded {
                embeddedStage(instances: instances)
            } else if layoutMode == .tab {
                tabContent(instances: instances)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: DesignTokens.Spacing.md)],
                        spacing: DesignTokens.Spacing.md
                    ) {
                        ForEach(instances) { inst in
                            MLProcessInstanceCard(instance: inst, launcher: launcher)
                        }
                    }
                    .padding(DesignTokens.Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
        .onChange(of: layoutMode) { _, newMode in
            applyLayoutChange(mode: newMode)
        }
        .onChange(of: presentationMode) { _, _ in
            applyLayoutChange(mode: layoutMode)
        }
        .onChange(of: launcher.instances.count) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                launcher.applyLayout(mode: layoutMode, selectedInstanceId: selectedTabInstanceId, presentation: presentationMode)
            }
        }
    }

    private func applyLayoutChange(mode: MultiLiveProcessLayoutMode) {
        if mode == .tab, selectedTabInstanceId == nil {
            selectedTabInstanceId = launcher.instances.values.sorted { $0.launchedAt < $1.launchedAt }.first?.id
        }
        launcher.applyLayout(mode: mode, selectedInstanceId: selectedTabInstanceId, presentation: presentationMode)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "rectangle.split.3x1.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentPurple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentationMode == .standalone ? "분리 인스턴스 모드" : "단일 인스턴스 모드")
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(presentationMode == .standalone
                         ? "각 채널이 독립된 CView 인스턴스(앱)로 실행됩니다 · \(launcher.instances.count)개 활성"
                         : "부모 창 안에 채널별 자식 프로세스로 임베드됩니다 · \(launcher.instances.count)개 활성")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()

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
                    .background(
                        Capsule().fill(DesignTokens.Colors.accentPurple)
                    )
                }
                .buttonStyle(.plain)
            }

            // 창 배치 picker (표시 방식은 설정 · 프로세스 모드에서 제어)
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text("창 배치")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

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
                .frame(maxWidth: 360)

                Spacer()

                Button(action: { launcher.applyLayout(mode: layoutMode, selectedInstanceId: selectedTabInstanceId, presentation: presentationMode) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .padding(6)
                        .background(Circle().fill(DesignTokens.Colors.surfaceElevated))
                }
                .buttonStyle(.plain)
                .help("현재 배치 다시 적용")
                .disabled(launcher.instances.isEmpty)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    // MARK: - Tab Content (탭 모드 — 채널 선택 칩 + 단일 카드)

    @ViewBuilder
    private func tabContent(instances: [MultiLiveChildInstance]) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // 채널 선택 칩
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(instances) { inst in
                        let isActive = selectedTabInstanceId == inst.id
                        Button {
                            selectedTabInstanceId = inst.id
                            launcher.applyLayout(mode: .tab, selectedInstanceId: inst.id, presentation: presentationMode)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isActive ? DesignTokens.Colors.accentPurple : DesignTokens.Colors.textTertiary)
                                    .frame(width: 6, height: 6)
                                Text(inst.channelName)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(isActive ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
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
                .padding(.horizontal, DesignTokens.Spacing.lg)
            }
            .padding(.top, DesignTokens.Spacing.md)

            // 선택된 인스턴스 카드
            if let selectedId = selectedTabInstanceId ?? instances.first?.id,
               let selected = instances.first(where: { $0.id == selectedId }) {
                MLProcessInstanceCard(instance: selected, launcher: launcher)
                    .frame(maxWidth: 480)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            Spacer()
        }
        .onAppear {
            if selectedTabInstanceId == nil {
                selectedTabInstanceId = instances.first?.id
            }
        }
    }

    @ViewBuilder
    private func embeddedStage(instances: [MultiLiveChildInstance]) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                            .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                    )
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: layoutMode == .tab ? "rectangle.stack.fill" : "rectangle.inset.filled")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.accentPurple)
                    Text("부모 앱 화면 모드")
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(.white)
                    Text("실제 영상은 이 영역 안에 별도 프로세스 창으로 정렬되어 표시됩니다")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .allowsHitTesting(false)

                EmbeddedHostFrameReporter { frame in
                    launcher.embeddedHostFrame = frame
                    if !instances.isEmpty {
                        launcher.applyLayout(mode: layoutMode, selectedInstanceId: selectedTabInstanceId, presentation: .embedded)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(instances) { inst in
                        let isActive = selectedTabInstanceId == inst.id
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
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isActive ? DesignTokens.Colors.accentPurple.opacity(0.18) : DesignTokens.Colors.surfaceElevated)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            if let selectedId = selectedTabInstanceId ?? instances.first?.id,
               let selected = instances.first(where: { $0.id == selectedId }) {
                MLProcessInstanceCard(instance: selected, launcher: launcher)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            Spacer()
        }
        .onAppear {
            if selectedTabInstanceId == nil {
                selectedTabInstanceId = instances.first?.id
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("실행 중인 자식 인스턴스가 없습니다")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(presentationMode == .standalone
                     ? "채널 추가 버튼을 누르면 해당 채널이 별도 CView 앱 창으로 열립니다.\n각 인스턴스는 독립된 프로세스에서 실행되어 안정성과 리소스 분산에 유리합니다."
                     : "채널 추가 버튼을 누르면 각 채널이 독립 프로세스로 실행되면서도\n부모 앱 화면 영역 안에 정렬되어 표시됩니다.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            Button(action: onAdd) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("첫 번째 채널 추가")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(DesignTokens.Colors.accentPurple)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Embedded Host Frame Reporter

struct EmbeddedHostFrameReporter: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> EmbeddedTrackingNSView {
        let view = EmbeddedTrackingNSView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: EmbeddedTrackingNSView, context: Context) {
        nsView.onChange = onChange
        // 다음 런루프에서 보고 — updateNSView 도중 동기 콜백 시
        // @Observable 상태 변경이 SwiftUI 재렌더를 유발해 layout 재진입을 일으킴.
        DispatchQueue.main.async { [weak nsView] in
            nsView?.reportFrameIfPossible()
        }
    }
}

/// 호스트 영역 프레임 리포터 — 변경 시에만 콜백 호출 (재진입 layout 방지)
final class EmbeddedTrackingNSView: NSView {
    var onChange: ((CGRect) -> Void)?
    private var lastReportedFrame: CGRect = .null

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleReport()
    }

    override func layout() {
        super.layout()
        // [Crash fix 2026-04-19] layout() 도중 콜백을 동기 호출하면
        // @Observable 변경 → SwiftUI 재렌더 → layout 재진입 사이클로
        // AppKit `_postWindowNeedsLayout` 가 NSException 을 던짐. 비동기 디스패치로 해소.
        scheduleReport()
    }

    private func scheduleReport() {
        DispatchQueue.main.async { [weak self] in
            self?.reportFrameIfPossible()
        }
    }

    func reportFrameIfPossible() {
        guard let window else { return }
        let localRect = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(localRect)
        // 동일 프레임이면 스킵 — @Observable 무의미한 갱신 방지
        if approxEqual(screenRect, lastReportedFrame) { return }
        lastReportedFrame = screenRect
        onChange?(screenRect)
    }

    private func approxEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        guard !a.isNull, !b.isNull else { return false }
        return abs(a.minX - b.minX) < tolerance
            && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance
            && abs(a.height - b.height) < tolerance
    }
}

// MARK: - 자식 인스턴스 카드

struct MLProcessInstanceCard: View {
    let instance: MultiLiveChildInstance
    let launcher: MultiLiveProcessLauncher

    @State private var isHovered = false
    @State private var muted = false
    @State private var volume: Float = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 상단: 채널 정보
            HStack(spacing: DesignTokens.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.accentPurple.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.accentPurple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.channelName)
                        .font(DesignTokens.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("PID \(instance.pid > 0 ? String(instance.pid) : "—")")
                            .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Circle()
                            .fill(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 5, height: 5)
                        Text(uptimeText)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.sm)

            Divider().background(DesignTokens.Glass.borderColor)

            // 컨트롤
            VStack(spacing: DesignTokens.Spacing.sm) {
                // 음량 슬라이더 + 뮤트
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button {
                        muted.toggle()
                        launcher.setMuted(muted, for: instance.id)
                    } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(muted ? Color.red : DesignTokens.Colors.textSecondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)

                    Slider(value: Binding(
                        get: { Double(volume) },
                        set: { newVal in
                            volume = Float(newVal)
                            launcher.setVolume(volume, for: instance.id)
                        }
                    ), in: 0...1)
                    .controlSize(.small)
                    .disabled(muted)

                    Text("\(Int(volume * 100))")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(width: 28, alignment: .trailing)
                }

                // 액션 버튼
                HStack(spacing: DesignTokens.Spacing.xs) {
                    actionButton("창 활성화", icon: "macwindow.on.rectangle", color: DesignTokens.Colors.accentBlue) {
                        launcher.activate(instanceId: instance.id)
                    }
                    actionButton("종료", icon: "xmark.circle.fill", color: Color.red) {
                        launcher.terminateChild(instanceId: instance.id)
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.surfaceBase.opacity(isHovered ? 0.95 : 0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .strokeBorder(
                            isHovered ? DesignTokens.Colors.accentPurple.opacity(0.4) : DesignTokens.Glass.borderColor,
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(isHovered ? 0.20 : 0.10), radius: isHovered ? 8 : 4, y: isHovered ? 6 : 3)
        )
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Animation.fast, value: isHovered)
    }

    private var uptimeText: String {
        let elapsed = Int(Date().timeIntervalSince(instance.launchedAt))
        let m = elapsed / 60
        let s = elapsed % 60
        if m > 0 {
            return "\(m)분 \(s)초"
        }
        return "\(s)초"
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(DesignTokens.Typography.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}
