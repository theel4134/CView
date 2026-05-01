// MARK: - SettingsWorkspace.swift
// CView 설정 메뉴 전면 리디자인 — Settings Command Center (2026-04-29)
//
// 문서: docs/settings-menu-redesign-candidates-2026-04-28.md
//
// 구조:
//   ┌──────────────────────────────────────────────────────────┐
//   │ SettingsTopBar  (검색 / 최근 변경 / Inspector 토글)        │
//   ├──────────┬──────────────────────────────────┬────────────┤
//   │          │                                  │            │
//   │ Rail*    │ Group Content                    │ Inspector* │
//   │ (선택)   │ (overview/viewing/chat/multi/...) │ (옵션)      │
//   │          │                                  │            │
//   └──────────┴──────────────────────────────────┴────────────┘
//
// rail은 독립 Settings 윈도우(showRail: true)에서만 표시.
// 메인 앱 사이드바 모드에서는 사이드바가 rail 역할을 하므로 showRail: false.
//
// 검색·최근 변경·시나리오 프리셋은 모든 그룹에서 공유된다.
// Inspector는 overview 그룹의 "변경됨만 보기"에서 활성화된다.

import SwiftUI
import CViewCore
import CViewPersistence

// MARK: - Recent Change Tracking

/// 설정 변경 이력 한 줄 — 메모리 전용 (앱 재시작 시 사라짐)
struct SettingsChangeEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let groupId: String       // SettingsGroup.rawValue
    let label: String         // 사람이 읽을 수 있는 항목 라벨
    let summary: String       // "켜짐 → 꺼짐", "1080p → 자동" 등
    let icon: String
}

/// 최근 변경 추적기 — 마지막 N개 변경을 메모리에 보관
@Observable
@MainActor
final class SettingsRecentChangesTracker {
    private(set) var entries: [SettingsChangeEntry] = []
    private let maxEntries = 12

    func record(group: AppRouter.SettingsGroup, label: String, summary: String, icon: String) {
        let entry = SettingsChangeEntry(
            timestamp: Date(),
            groupId: group.rawValue,
            label: label,
            summary: summary,
            icon: icon
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func clear() { entries.removeAll() }
}

// MARK: - Settings Workspace (Top-level Container)

struct SettingsWorkspace: View {
    @Bindable var settings: SettingsStore
    @Binding var selectedGroup: AppRouter.SettingsGroup
    let showRail: Bool

    // 검색 / 인스펙터 / 변경됨만 보기 상태
    @State private var searchQuery: String = ""
    @State private var showInspector: Bool = false
    @State private var changedOnly: Bool = false

    // 최근 변경 추적 (워크스페이스 라이프사이클 동안 유지)
    @State private var recentChanges = SettingsRecentChangesTracker()

    // 시나리오 적용 전 스냅샷 (단일 단계 rollback)
    @State private var lastScenarioSnapshot: SettingsScenarioSnapshot?
    @State private var lastScenarioName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // [hiddenTitleBar 대응 2026-04-29] 메인 앱(showRail=false)에서는 부모
            // NavigationStack 이 .ignoresSafeArea(.container, edges: .top) 를 적용하므로
            // 상단 ~28pt 가 macOS 트래픽 라이트/드래그 영역과 겹쳐 SettingsTopBar 가
            // 가려지고 ScrollView 콘텐츠가 타이틀바 위로 올라가 보였다.
            // 독립 Settings 윈도우(showRail=true)는 정상 타이틀바를 가지므로 보정 불필요.
            // [Refine 2026-05-01] background 단색 + Divider 를 통일 menuTopChrome 으로 대체.
            VStack(spacing: 0) {
                if !showRail {
                    Color.clear
                        .frame(height: 28)
                }

                SettingsTopBar(
                    selectedGroup: selectedGroup,
                    searchQuery: $searchQuery,
                    showInspector: $showInspector,
                    changedOnly: $changedOnly,
                    recentChanges: recentChanges,
                    hasRollback: lastScenarioSnapshot != nil,
                    rollbackName: lastScenarioName,
                    onRollback: rollbackLastScenario
                )
            }
            .menuTopChrome()

            // 본문 — rail / content / inspector
            HStack(spacing: 0) {
                if showRail {
                    SettingsRail(selection: $selectedGroup)
                        .frame(width: 220)
                    Divider()
                }

                ZStack {
                    DesignTokens.Colors.background
                    SettingsGroupContent(
                        group: selectedGroup,
                        settings: settings,
                        searchQuery: searchQuery,
                        changedOnly: changedOnly,
                        recentChanges: recentChanges,
                        onSelectGroup: { selectedGroup = $0 },
                        onApplyScenario: applyScenario
                    )
                    .id(selectedGroup)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(DesignTokens.Animation.snappy, value: selectedGroup)

                if showInspector {
                    Divider()
                    SettingsInspectorPane(
                        group: selectedGroup,
                        settings: settings,
                        recentChanges: recentChanges,
                        onClose: { withAnimation(DesignTokens.Animation.snappy) { showInspector = false } }
                    )
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: 시나리오 적용/롤백

    private func applyScenario(_ scenario: SettingsScenario) {
        // 적용 전 스냅샷
        lastScenarioSnapshot = SettingsScenarioSnapshot(from: settings)
        lastScenarioName = scenario.title
        scenario.apply(to: settings)
        recentChanges.record(
            group: .overview,
            label: "시나리오 적용",
            summary: scenario.title,
            icon: scenario.icon
        )
        Task { await settings.save() }
    }

    private func rollbackLastScenario() {
        guard let snap = lastScenarioSnapshot else { return }
        snap.restore(to: settings)
        recentChanges.record(
            group: .overview,
            label: "시나리오 되돌림",
            summary: lastScenarioName,
            icon: "arrow.uturn.backward"
        )
        lastScenarioSnapshot = nil
        lastScenarioName = ""
        Task { await settings.save() }
    }
}

// MARK: - Top Bar

private struct SettingsTopBar: View {
    let selectedGroup: AppRouter.SettingsGroup
    @Binding var searchQuery: String
    @Binding var showInspector: Bool
    @Binding var changedOnly: Bool
    let recentChanges: SettingsRecentChangesTracker
    let hasRollback: Bool
    let rollbackName: String
    let onRollback: () -> Void

    @State private var isSearchFocused: Bool = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 그룹 타이틀
            HStack(spacing: 8) {
                Image(systemName: selectedGroup.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedGroup.color)
                    .frame(width: 24, height: 24)
                    .background(selectedGroup.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(selectedGroup.rawValue)
                    .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            .frame(width: 100, alignment: .leading)

            // 검색
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("설정 검색 (예: 화질, 프록시, App Secret)", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.custom(size: 12))
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignTokens.Glass.thin, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            )
            .frame(maxWidth: 360)

            Spacer(minLength: 8)

            // 최근 변경 pill
            if let last = recentChanges.entries.first {
                HStack(spacing: 6) {
                    Image(systemName: last.icon)
                        .font(.system(size: 10, weight: .medium))
                    Text("\(last.label): \(last.summary)")
                        .font(DesignTokens.Typography.custom(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignTokens.Colors.textPrimary.opacity(0.06), in: Capsule())
                .help("최근 변경: \(last.summary)")
                .transition(.opacity)
            }

            // 시나리오 되돌리기
            if hasRollback {
                Button(action: onRollback) {
                    Label("되돌리기", systemImage: "arrow.uturn.backward")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DesignTokens.Colors.accentOrange.opacity(0.12), in: Capsule())
                .foregroundStyle(DesignTokens.Colors.accentOrange)
                .help("\(rollbackName) 시나리오 적용 직전 상태로 되돌립니다")
            }

            // 변경됨만 보기 토글
            Toggle(isOn: $changedOnly) {
                Label("변경됨만", systemImage: "circle.lefthalf.filled")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("기본값과 다른 항목만 표시 (Inspector 정보 활성화)")

            // Inspector 토글
            Button {
                withAnimation(DesignTokens.Animation.snappy) { showInspector.toggle() }
            } label: {
                Image(systemName: showInspector ? "sidebar.right" : "sidebar.squares.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(showInspector ? DesignTokens.Colors.accentBlue : DesignTokens.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(showInspector ? "Inspector 닫기" : "Inspector 열기")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        // [Refine 2026-05-01] 높이 44pt → 48pt 로 라이브 메뉴 등 다른 메뉴 상단과 통일.
        // 자체 background 는 제거 — 부모(`SettingsWorkspace.body`)의 menuTopChrome 가 담당.
        .frame(height: 48)
        .animation(DesignTokens.Animation.smooth, value: hasRollback)
        .animation(DesignTokens.Animation.smooth, value: recentChanges.entries.first?.id)
    }
}

// MARK: - Rail (독립 윈도우용 좌측 목록)

private struct SettingsRail: View {
    @Binding var selection: AppRouter.SettingsGroup
    @State private var hovered: AppRouter.SettingsGroup?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "c.square.fill")
                    .font(DesignTokens.Typography.custom(size: 16))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("CView 설정")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.sm)

            Divider()
                .padding(.horizontal, DesignTokens.Spacing.sm)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(AppRouter.SettingsGroup.allCases) { group in
                        railRow(group)
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            }

            Spacer()
            Divider()
            footer
        }
        .frame(maxHeight: .infinity)
        .background(DesignTokens.Glass.sidebar)
    }

    @ViewBuilder
    private func railRow(_ group: AppRouter.SettingsGroup) -> some View {
        let isSelected = selection == group
        let isHovered = hovered == group
        Button {
            withAnimation(DesignTokens.Animation.snappy) { selection = group }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: group.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : group.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.rawValue)
                        .font(DesignTokens.Typography.custom(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : DesignTokens.Colors.textPrimary)
                    Text(group.subtitle)
                        .font(DesignTokens.Typography.custom(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.78) : DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor
                          : (isHovered ? DesignTokens.Colors.textPrimary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DesignTokens.Animation.micro) { hovered = h ? group : nil } }
        .padding(.horizontal, DesignTokens.Spacing.sm)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Text("CView v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")")
                .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

// MARK: - Group Content Switch

private struct SettingsGroupContent: View {
    let group: AppRouter.SettingsGroup
    @Bindable var settings: SettingsStore
    let searchQuery: String
    let changedOnly: Bool
    let recentChanges: SettingsRecentChangesTracker
    let onSelectGroup: (AppRouter.SettingsGroup) -> Void
    let onApplyScenario: (SettingsScenario) -> Void

    var body: some View {
        // 검색이 비어있을 때만 그룹별 화면 사용. 검색어가 있으면 검색 결과 화면으로.
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            SettingsSearchResults(
                settings: settings,
                query: searchQuery,
                onJump: onSelectGroup
            )
        } else {
            switch group {
            case .overview:
                SettingsOverviewContent(
                    settings: settings,
                    recentChanges: recentChanges,
                    changedOnly: changedOnly,
                    onSelectGroup: onSelectGroup,
                    onApplyScenario: onApplyScenario
                )
            case .viewing:
                ViewingGroupContent(settings: settings)
            case .chat:
                ChatSettingsTab(settings: settings)
            case .multi:
                MultiLiveSettingsTab(settings: settings)
            case .integration:
                IntegrationGroupContent(settings: settings)
            case .advanced:
                AdvancedGroupContent(settings: settings)
            }
        }
    }
}

// MARK: - 시청 그룹 (Player + Latency)

private struct ViewingGroupContent: View {
    @Bindable var settings: SettingsStore
    @State private var subTab: SubTab = .player

    enum SubTab: String, CaseIterable, Identifiable {
        case player = "재생"
        case latency = "레이턴시"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .player: "play.rectangle.fill"
            case .latency: "timer"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSubTabBar(items: SubTab.allCases, selection: $subTab)
            Divider()
            switch subTab {
            case .player:
                PlayerSettingsTab(settings: settings)
            case .latency:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                        SettingsPageHeader(
                            "레이턴시 동기화",
                            subtitle: "스트림 재생 지연을 웹 브라우저 수준으로 조절합니다")
                        LatencySettingsFull(settings: settings)
                    }
                    .padding(DesignTokens.Spacing.xl)
                }
            }
        }
    }
}

// MARK: - 연동 그룹 (Network + Metrics)

private struct IntegrationGroupContent: View {
    @Bindable var settings: SettingsStore
    @State private var subTab: SubTab = .network

    enum SubTab: String, CaseIterable, Identifiable {
        case network = "네트워크"
        case metrics = "메트릭"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .network: "network"
            case .metrics: "chart.line.uptrend.xyaxis"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSubTabBar(items: SubTab.allCases, selection: $subTab)
            Divider()
            switch subTab {
            case .network: NetworkSettingsTab(settings: settings)
            case .metrics: MetricsSettingsTab(settings: settings)
            }
        }
    }
}

// MARK: - 고급 그룹 (Performance + General apparel/keyboard)

private struct AdvancedGroupContent: View {
    @Bindable var settings: SettingsStore
    @State private var subTab: SubTab = .performance

    enum SubTab: String, CaseIterable, Identifiable {
        case performance = "성능"
        case general = "일반/단축키"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .performance: "gauge.with.dots.needle.33percent"
            case .general: "command"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsSubTabBar(items: SubTab.allCases, selection: $subTab)
            Divider()
            switch subTab {
            case .performance: PerformanceSettingsTab(settings: settings)
            case .general: GeneralSettingsTab(settings: settings)
            }
        }
    }
}

// MARK: - 작은 서브 탭 바 (segmented-like)

private struct SettingsSubTabBar<T: Identifiable & Hashable>: View where T: RawRepresentable, T.RawValue == String {
    let items: [T]
    @Binding var selection: T
    /// `T.icon` accessor — 외부에서 `iconKeyPath`로 접근하려면 별도 프로토콜을 추가해야 함.
    /// 본 구현에서는 동일 이름 메서드/프로퍼티 정의로 호출되므로 reflection 없이 안전하게 처리.

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(DesignTokens.Animation.snappy) { selection = item }
                } label: {
                    Text(item.rawValue)
                        .font(DesignTokens.Typography.custom(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(isSelected ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

// MARK: - Inspector Pane

private struct SettingsInspectorPane: View {
    let group: AppRouter.SettingsGroup
    @Bindable var settings: SettingsStore
    let recentChanges: SettingsRecentChangesTracker
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                Text("Inspector")
                    .font(DesignTokens.Typography.bodySemibold)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    // 영향 범위
                    inspectorSection(title: "영향 범위", icon: "scope") {
                        Text(group.impactDescription)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }

                    // 적용 상태
                    inspectorSection(title: "적용 상태", icon: "checkmark.seal.fill") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(group.applyTimingNotes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 4))
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                        .padding(.top, 6)
                                    Text(note)
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                }
                            }
                        }
                    }

                    // 위험 / 민감 항목
                    if !group.riskTags.isEmpty {
                        inspectorSection(title: "위험·민감 항목", icon: "exclamationmark.triangle.fill") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(group.riskTags, id: \.self) { tag in
                                    SettingsRiskBadge(level: tag.level, label: tag.label, hint: tag.hint)
                                }
                            }
                        }
                    }

                    // 관련 컴포넌트
                    if !group.relatedComponents.isEmpty {
                        inspectorSection(title: "관련 런타임", icon: "puzzlepiece.extension.fill") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(group.relatedComponents, id: \.self) { name in
                                    Text(name)
                                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DesignTokens.Colors.textPrimary.opacity(0.05),
                                                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }
                        }
                    }

                    // 그룹 변경 이력
                    let changes = recentChanges.entries.filter { $0.groupId == group.rawValue }
                    if !changes.isEmpty {
                        inspectorSection(title: "최근 변경", icon: "clock.arrow.circlepath") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(changes.prefix(8)) { c in
                                    HStack(spacing: 6) {
                                        Image(systemName: c.icon)
                                            .font(.system(size: 10))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                        Text(c.label)
                                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                                        Text("·")
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                        Text(c.summary)
                                            .font(DesignTokens.Typography.custom(size: 11))
                                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }

                    // 기본값으로 되돌리기 (그룹 단위)
                    inspectorSection(title: "되돌리기", icon: "arrow.uturn.backward") {
                        Button {
                            resetGroupToDefaults()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                Text("이 그룹 기본값 복원")
                            }
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DesignTokens.Colors.live, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("이 그룹에 속한 모든 설정 도메인을 기본값으로 복원합니다")
                    }
                }
                .padding(DesignTokens.Spacing.lg)
            }
        }
        .background(DesignTokens.Colors.background)
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(title: String, icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            content()
        }
    }

    private func resetGroupToDefaults() {
        switch group {
        case .overview:
            settings.general = .default
            settings.appearance = .default
        case .viewing:
            settings.player = .default
        case .chat:
            settings.chat = .default
            settings.multiChat = .default
        case .multi:
            settings.multiLive = .default
        case .integration:
            settings.network = .default
            settings.metrics = .default
            settings.channelNotifications = .default
        case .advanced:
            settings.appearance = .default
            settings.keyboard = .default
        }
        Task { await settings.save() }
    }
}

// MARK: - Inspector Metadata (그룹별 정적 정보)

extension AppRouter.SettingsGroup {
    var impactDescription: String {
        switch self {
        case .overview:    "앱의 기본 동작·테마·알림과 자주 쓰는 설정을 묶어 보여줍니다."
        case .viewing:     "라이브 스트림 재생 품질·엔진·레이턴시·스크린샷 동작에 영향을 줍니다."
        case .chat:        "단일 채팅과 멀티채팅 패널의 표시·입력·필터·TTS 동작에 영향을 줍니다."
        case .multi:       "멀티라이브 세션 수·프로세스 모드·대역폭·오디오·오버레이 정책을 결정합니다."
        case .integration: "외부 서버 연동(API·WebSocket·메트릭) 및 인증 키를 관리합니다."
        case .advanced:    "디코딩·메모리·캐시·디버그·전체 초기화 등 고급/민감 설정을 모아둡니다."
        }
    }

    var applyTimingNotes: [String] {
        switch self {
        case .overview:
            return ["테마 / 메뉴바: 즉시 반영", "자동 실행 / 알림: 다음 실행부터 반영"]
        case .viewing:
            return [
                "기본 화질·엔진: 다음 재생부터",
                "스트림 보정 모드: 활성 스트림 자동 재시작",
                "레이턴시 PID·프리셋: 즉시 반영"
            ]
        case .chat:
            return ["채팅 표시 옵션: 즉시 반영", "TTS 음성: 시스템 변경 시 즉시"]
        case .multi:
            return [
                "최대 동시 세션 / 레이아웃: 새 세션부터",
                "프로세스 분리 모드: 앱 재시작 권장"
            ]
        case .integration:
            return [
                "네트워크 프리셋: 새 요청부터",
                "메트릭 활성화·App Secret: 즉시 재구성",
                "프록시 강제: 활성 스트림 재시작"
            ]
        case .advanced:
            return [
                "하드웨어 디코딩 / 메모리 제한: 즉시",
                "디버그 모드: 즉시 (로그 부담↑)",
                "전체 초기화: 영구적 — 되돌릴 수 없음"
            ]
        }
    }

    var riskTags: [SettingsRiskTag] {
        switch self {
        case .viewing:
            return [
                .init(level: .caution, label: "항상 최고 화질 유지", hint: "ABR 자동 하향 차단 — 멀티라이브에서 끊김↑"),
                .init(level: .info, label: "스트림 보정 모드 (실험)", hint: "Direct/SystemProxy 모드는 일부 환경에서 인증 실패")
            ]
        case .multi:
            return [
                .init(level: .caution, label: "프로세스 분리 모드", hint: "메모리 격리는 강해지나 메모리 사용량 증가"),
                .init(level: .info, label: "최대 6개 동시 세션", hint: "고사양 Mac 외에는 4개 이하 권장")
            ]
        case .integration:
            return [
                .init(level: .sensitive, label: "App Secret", hint: "유출 시 메트릭 인증이 우회됨 — 외부 공유 금지"),
                .init(level: .caution, label: "스트림 프록시 강제", hint: "프록시 호환성 문제가 있는 환경에서 재생 실패 가능")
            ]
        case .advanced:
            return [
                .init(level: .danger, label: "전체 초기화", hint: "모든 설정·세션·캐시가 사라집니다 — 되돌릴 수 없음"),
                .init(level: .caution, label: "디버그 모드", hint: "로그 양 증가 — 일반 사용 시 끄세요")
            ]
        case .overview, .chat:
            return []
        }
    }

    var relatedComponents: [String] {
        switch self {
        case .overview:    ["AppearanceSettings", "GeneralSettings", "AppRouter"]
        case .viewing:     ["StreamCoordinator", "PlayerEngine", "LowLatencyController", "AVPlayerEngine"]
        case .chat:        ["ChatViewModel", "MultiChatStore", "TTSService"]
        case .multi:       ["MultiLiveCoordinator", "ProcessSessionHost", "BandwidthCoordinator"]
        case .integration: ["APIClient", "WebSocketClient", "MetricsForwarder", "StreamProxy"]
        case .advanced:    ["DataStore", "ImageCache", "Log", "MemoryManager"]
        }
    }
}

// MARK: - Risk Badge

enum SettingsRiskLevel {
    case info, caution, danger, sensitive

    var color: Color {
        switch self {
        case .info: DesignTokens.Colors.accentBlue
        case .caution: DesignTokens.Colors.accentOrange
        case .danger: DesignTokens.Colors.live
        case .sensitive: DesignTokens.Colors.accentPurple
        }
    }

    var icon: String {
        switch self {
        case .info: "info.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .sensitive: "lock.shield.fill"
        }
    }

    var displayName: String {
        switch self {
        case .info: "참고"
        case .caution: "주의"
        case .danger: "위험"
        case .sensitive: "민감"
        }
    }
}

struct SettingsRiskTag: Hashable {
    let level: SettingsRiskLevel
    let label: String
    let hint: String
}

struct SettingsRiskBadge: View {
    let level: SettingsRiskLevel
    let label: String
    let hint: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: level.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(level.color)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(level.displayName)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(level.color, in: Capsule())
                    Text(label)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                Text(hint)
                    .font(DesignTokens.Typography.custom(size: 10))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(level.color.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(level.color.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - 검색 결과 (간이 — label/description 기반 fuzzy)

private struct SettingsSearchResults: View {
    @Bindable var settings: SettingsStore
    let query: String
    let onJump: (AppRouter.SettingsGroup) -> Void

    var body: some View {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let matches = SettingsSearchIndex.allEntries.filter { e in
            e.label.localizedCaseInsensitiveContains(q)
                || e.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
                || e.group.rawValue.localizedCaseInsensitiveContains(q)
        }

        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                SettingsPageHeader(
                    "\"\(query)\" 검색 결과",
                    subtitle: "\(matches.count)개 항목 일치 — 클릭하면 해당 그룹으로 이동합니다"
                )

                if matches.isEmpty {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("일치하는 설정이 없습니다")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                        Text("다른 키워드로 시도해보세요")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(matches) { entry in
                            Button { onJump(entry.group) } label: {
                                resultRow(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }

    @ViewBuilder
    private func resultRow(_ entry: SettingsSearchIndex.Entry) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: entry.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(entry.group.color)
                .frame(width: 28, height: 28)
                .background(entry.group.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("\(entry.group.rawValue) · \(entry.tags.joined(separator: ", "))")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 8)
        .background(DesignTokens.Glass.thin, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }
}

// MARK: - Search Index (정적 메타데이터)

enum SettingsSearchIndex {
    struct Entry: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let tags: [String]
        let icon: String
        let group: AppRouter.SettingsGroup
    }

    nonisolated(unsafe) static let allEntries: [Entry] = [
        // Overview / General
        .init(id: "theme", label: "테마", tags: ["라이트", "다크", "시스템", "appearance"], icon: "paintpalette.fill", group: .overview),
        .init(id: "launchAtLogin", label: "시작 시 자동 실행", tags: ["로그인", "auto launch"], icon: "power", group: .overview),
        .init(id: "menuBar", label: "메뉴바 표시", tags: ["menubar"], icon: "menubar.rectangle", group: .overview),
        .init(id: "alwaysOnTop", label: "항상 최상위", tags: ["pin"], icon: "macwindow.on.rectangle", group: .overview),
        .init(id: "notifications", label: "알림 활성화", tags: ["라이브 알림"], icon: "bell.badge.fill", group: .overview),
        // Viewing / Player
        .init(id: "quality", label: "기본 화질", tags: ["1080p", "auto", "abr"], icon: "4k.tv.fill", group: .viewing),
        .init(id: "engine", label: "재생 엔진", tags: ["VLC", "AVPlayer"], icon: "cpu", group: .viewing),
        .init(id: "streamProxy", label: "스트림 보정 모드", tags: ["프록시", "MP2T", "Content-Type"], icon: "network", group: .viewing),
        .init(id: "forceHQ", label: "항상 최고 화질 유지", tags: ["1080p60", "ABR 차단"], icon: "4k.tv.fill", group: .viewing),
        .init(id: "autoplay", label: "자동 재생", tags: ["autoplay"], icon: "play.fill", group: .viewing),
        .init(id: "background", label: "백그라운드 재생", tags: [], icon: "play.slash.fill", group: .viewing),
        .init(id: "latency", label: "레이턴시 프리셋", tags: ["저지연", "webSync", "PID"], icon: "timer", group: .viewing),
        .init(id: "screenshot", label: "스크린샷 경로/포맷", tags: ["png", "jpeg"], icon: "camera.fill", group: .viewing),
        // Chat
        .init(id: "chatPanel", label: "채팅 패널 너비", tags: [], icon: "sidebar.right", group: .chat),
        .init(id: "chatOverlay", label: "채팅 오버레이", tags: ["overlay", "투명"], icon: "rectangle.on.rectangle", group: .chat),
        .init(id: "tts", label: "TTS 읽기", tags: ["음성", "speaker"], icon: "waveform", group: .chat),
        .init(id: "filter", label: "차단 키워드/사용자", tags: ["block", "filter"], icon: "hand.raised.fill", group: .chat),
        // Multi
        .init(id: "maxSessions", label: "최대 동시 세션", tags: ["멀티라이브"], icon: "number.square.fill", group: .multi),
        .init(id: "separateProcess", label: "프로세스 분리 모드", tags: ["격리", "메모리"], icon: "rectangle.split.3x1.fill", group: .multi),
        .init(id: "multiAudio", label: "멀티오디오", tags: ["sound"], icon: "speaker.wave.3.fill", group: .multi),
        .init(id: "bwCoord", label: "대역폭 조정", tags: ["abr", "bandwidth"], icon: "antenna.radiowaves.left.and.right", group: .multi),
        // Integration
        .init(id: "preset", label: "네트워크 프리셋", tags: ["balanced", "stability", "lowLatency"], icon: "wand.and.stars", group: .integration),
        .init(id: "timeout", label: "연결 타임아웃", tags: ["timeout"], icon: "timer", group: .integration),
        .init(id: "websocket", label: "WebSocket 설정", tags: ["ws"], icon: "antenna.radiowaves.left.and.right", group: .integration),
        .init(id: "proxy", label: "스트림 프록시", tags: ["proxy"], icon: "shield.lefthalf.filled", group: .integration),
        .init(id: "metricsServer", label: "메트릭 서버 URL", tags: ["server"], icon: "server.rack", group: .integration),
        .init(id: "appSecret", label: "App Secret", tags: ["인증", "비밀키"], icon: "key.fill", group: .integration),
        .init(id: "metricsEnabled", label: "메트릭 전송 활성화", tags: ["telemetry"], icon: "antenna.radiowaves.left.and.right", group: .integration),
        // Advanced
        .init(id: "hwDecode", label: "하드웨어 디코딩", tags: ["GPU"], icon: "memorychip", group: .advanced),
        .init(id: "memLimit", label: "메모리 제한", tags: ["cache", "image"], icon: "memorychip.fill", group: .advanced),
        .init(id: "compact", label: "콤팩트 모드", tags: [], icon: "rectangle.compress.vertical", group: .advanced),
        .init(id: "sidebar", label: "사이드바 너비", tags: [], icon: "sidebar.left", group: .advanced),
        .init(id: "debug", label: "디버그 모드", tags: ["log"], icon: "ant.fill", group: .advanced),
        .init(id: "cache", label: "캐시 정리", tags: ["clear cache"], icon: "trash.fill", group: .advanced),
        .init(id: "reset", label: "전체 초기화", tags: ["reset", "factory"], icon: "exclamationmark.arrow.circlepath", group: .advanced),
        .init(id: "shortcuts", label: "키보드 단축키", tags: ["keyboard", "shortcut"], icon: "command", group: .advanced),
    ]
}
