// MARK: - MetricsDashboardView.swift
// CView 서버 대시보드 — Modern Dashboard UI
//
// [Redesign 2026-04-28]
// docs/metrics-menu-redesign-candidates-2026-04-28.md 의 "1안 Metrics Command Center" 적용.
// - hero/serverOverview → 단일 status strip
// - Overview / Channels / Monitoring 탭 구조 (Monitoring 은 P2 placeholder)
// - Overview = compact KPI(4) + 차트 + 문제 채널 + 액션 + DB drawer
// - Channels = 기존 channelDetailSection 재사용

import SwiftUI
import Charts
import CViewCore
import CViewUI

// MARK: - Tab Mode (Redesign 2026-04-28)

enum MetricsDashboardTab: String, CaseIterable, Identifiable, Sendable, Codable {
    case overview
    case channels
    case monitoring
    var id: String { rawValue }
    var label: String {
        switch self {
        case .overview:   return "개요"
        case .channels:   return "채널"
        case .monitoring: return "모니터링"
        }
    }
    var icon: String {
        switch self {
        case .overview:   return "square.grid.2x2.fill"
        case .channels:   return "antenna.radiowaves.left.and.right"
        case .monitoring: return "waveform.path.ecg"
        }
    }
}

// [Channels Inspector 2026-04-28] table 정렬/필터.
enum ChannelInspectorSort: String, CaseIterable, Identifiable {
    case deltaDesc      // 동기화 편차 큰 순 (기본)
    case samplesDesc    // 샘플 많은 순
    case nameAsc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .deltaDesc:   return "편차 큰 순"
        case .samplesDesc: return "샘플 많은 순"
        case .nameAsc:     return "채널명"
        }
    }
}

enum ChannelInspectorFilter: String, CaseIterable, Identifiable {
    case all        // 전체
    case withWeb    // 웹 데이터 있음
    case withApp    // 앱 데이터 있음
    case waiting    // 웹 데이터 대기
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:     return "전체"
        case .withWeb: return "웹"
        case .withApp: return "앱"
        case .waiting: return "대기"
        }
    }
    var icon: String {
        switch self {
        case .all:     return "square.grid.2x2"
        case .withWeb: return "globe"
        case .withApp: return "desktopcomputer"
        case .waiting: return "hourglass"
        }
    }
}

struct MetricsDashboardView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @State private var appearAnimated = false
    @State private var dbHealthExpanded = false

    // [Channels Inspector 2026-04-28] 우측 inspector 에 표시할 선택 채널.
    @State private var selectedChannelId: String? = nil
    @State private var channelSearchText: String = ""
    @State private var channelFilter: ChannelInspectorFilter = .all
    @State private var channelSort: ChannelInspectorSort = .deltaDesc

    @AppStorage("metrics.dashboard.tab")
    private var tabRaw: String = MetricsDashboardTab.overview.rawValue
    private var tab: MetricsDashboardTab {
        MetricsDashboardTab(rawValue: tabRaw) ?? .overview
    }

    var body: some View {
        VStack(spacing: 0) {
            statusStrip
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.top, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.md)
            forwarderStatusBanner
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.bottom, DesignTokens.Spacing.sm)
            tabPicker
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.bottom, DesignTokens.Spacing.md)
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    switch tab {
                    case .overview:   overviewContent
                    case .channels:   channelsContent
                    case .monitoring: monitoringContent
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.lg)
            }
        }
        .background(DesignTokens.Colors.surfaceBase)
        .task {
            await viewModel.loadServerStats()
            await viewModel.loadSystemStats()
            withAnimation(DesignTokens.Animation.smooth) {
                appearAnimated = true
            }
        }
        .refreshable {
            await viewModel.loadServerStats()
            await viewModel.loadSystemStats()
        }
    }

    // MARK: - Status Strip (Redesign 2026-04-28)
    // 기존 heroHeader + serverOverviewBar 를 한 줄로 압축.

    private var statusStrip: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // 좌: 서버 명/상태 dot
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(viewModel.isMetricsServerOnline ? DesignTokens.Colors.chzzkGreen : .red)
                        .frame(width: 9, height: 9)
                    if viewModel.isMetricsServerOnline {
                        Circle()
                            .fill(DesignTokens.Colors.chzzkGreen.opacity(0.4))
                            .frame(width: 9, height: 9)
                            .scaleEffect(appearAnimated ? 2.2 : 1.0)
                            .opacity(appearAnimated ? 0 : 0.6)
                            .animation(DesignTokens.Animation.pulse, value: appearAnimated)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("CView 서버")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("cv.dododo.app")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }

            statusDivider

            // 가운데: WS 배지 + 마지막 수신
            connectionBadge
            if let lastUpdate = viewModel.serverLastUpdate {
                Text(lastUpdate, format: .dateTime.hour().minute().second())
                    .font(DesignTokens.Typography.monoMedium)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            statusDivider

            // DB compact health badge (자세한 정보는 Overview drawer)
            dbCompactBadge

            statusDivider

            // 활성 채널 카운트 (요약)
            HStack(spacing: 4) {
                Image(systemName: "play.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentCyan)
                Text("\(viewModel.serverChannelStats.count) 채널")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .contentTransition(.numericText())
            }

            Spacer()

            // 우: 액션 menu + 새로고침
            actionsMenu
            Button {
                Task {
                    await viewModel.loadServerStats()
                    await viewModel.loadSystemStats()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    .frame(width: 28, height: 28)
                    .background(DesignTokens.Colors.chzzkGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }
            .buttonStyle(.plain)
            .help("새로고침")
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(DesignTokens.Glass.borderColor)
            .frame(width: 0.5, height: 22)
    }

    // MARK: - Forwarder Status Banner
    //
    // 메트릭 전송 토글이 OFF 면 dashboard 화면 자체가 모두 비어 보이므로
    // 1-탭으로 활성화할 수 있는 인라인 배너를 보여준다.
    @ViewBuilder
    private var forwarderStatusBanner: some View {
        @Bindable var settingsBindable = appState.settingsStore
        if !settingsBindable.metrics.metricsEnabled {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("메트릭 전송이 비활성화되어 있습니다")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text("라이브 시청 중에도 cv.dododo.app 으로 데이터가 전송되지 않아 활성 채널이 0으로 표시됩니다.")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer(minLength: 8)
                Button {
                    Task {
                        settingsBindable.metrics.metricsEnabled = true
                        await appState.applyMetricsSettings()
                        try? await Task.sleep(for: .milliseconds(800))
                        await viewModel.loadServerStats()
                    }
                } label: {
                    Label("활성화", systemImage: "power")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DesignTokens.Colors.chzzkGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    router.selectSidebar(.settings)
                    router.selectSettingsGroup(.integration)
                } label: {
                    Label("설정 열기", systemImage: "gearshape")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(.orange.opacity(0.4), lineWidth: 0.6)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if viewModel.serverChannelStats.isEmpty,
                  viewModel.isMetricsServerOnline {
            // 전송 활성화 + 서버 응답에 채널이 비어있는 상태 — 첫 전송 대기 안내.
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentCyan)
                Text("재생 중인 채널 메트릭이 처음 도착하기까지 최대 \(Int(appState.settingsStore.metrics.forwardInterval))초 정도 걸립니다")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Button {
                    Task {
                        await viewModel.loadServerStats()
                        await viewModel.loadSystemStats()
                    }
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.accentCyan)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.accentCyan.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(DesignTokens.Colors.accentCyan.opacity(0.3), lineWidth: 0.6)
            }
            .transition(.opacity)
        }
    }
    /// 좁은 strip 용 DB 헬스 배지 — 모두 정상이면 dot 1개, 비정상이면 비정상 DB만 빨강.
    /// 클릭 시 Overview 탭으로 이동하고 'DB 상세' disclosure 자동 펼침.
    /// [Shape Tolerance 2026-04-28] cv.dododo.app 처럼 services 맵만 주는 서버는
    /// influxdb/postgres/redis 가 모두 nil 이므로 services map 으로 통합 표시한다.
    @ViewBuilder
    private var dbCompactBadge: some View {
        let sys = viewModel.systemStats
        let mode = dbBadgeMode(sys)
        Button {
            withAnimation(DesignTokens.Animation.snappy) {
                tabRaw = MetricsDashboardTab.overview.rawValue
                dbHealthExpanded = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.allOk ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(mode.allOk ? DesignTokens.Colors.chzzkGreen : .orange)
                Text(mode.label)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .tracking(0.5)
                if !mode.dots.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(mode.dots.enumerated()), id: \.offset) { _, ok in
                            Circle().fill(ok ? DesignTokens.Colors.chzzkGreen : .red).frame(width: 5, height: 5)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.tooltip)
    }

    private struct DBBadgeMode {
        let label: String
        let dots: [Bool]
        let allOk: Bool
        let tooltip: String
    }

    private func dbBadgeMode(_ sys: MetricsSystemData?) -> DBBadgeMode {
        // 1순위: 명시적 InfluxDB/Postgres/Redis breakdown.
        if let sys, sys.influxdb != nil || sys.redis != nil || sys.postgres != nil {
            let influx = isHealthy(sys.influxdb?.status)
            let postgres = isHealthy(sys.postgres)
            let redis = isHealthy(sys.redis?.status)
            return DBBadgeMode(
                label: "DB",
                dots: [influx, postgres, redis],
                allOk: influx && postgres && redis,
                tooltip: "InfluxDB / PostgreSQL / Redis 상태 — 클릭 시 'DB 상세' 펼침"
            )
        }
        // 2순위: services 맵.
        if let services = sys?.services, !services.isEmpty {
            let dots = services.values.map { isHealthy($0) }
            let allOk = dots.allSatisfy { $0 }
            let names = services.keys.sorted().joined(separator: " / ")
            return DBBadgeMode(
                label: "SVC",
                dots: dots,
                allOk: allOk,
                tooltip: "\(names) 상태 — 클릭 시 'DB 상세' 펼침"
            )
        }
        // 3순위: 시스템 데이터 자체 미수신.
        return DBBadgeMode(
            label: "DB",
            dots: [],
            allOk: false,
            tooltip: "시스템 상태 미수신"
        )
    }

    private func isHealthy(_ status: String?) -> Bool {
        guard let s = status?.lowercased() else { return false }
        return s == "connected" || s == "ok" || s == "healthy"
    }

    /// 설정 / 전송 상태 / 분석 대시보드 진입 액션 menu.
    private var actionsMenu: some View {
        Menu {
            Button {
                openWindow(id: "ml-metrics-window")
            } label: {
                Label("전송 상태 창", systemImage: "paperplane.circle")
            }
            Button {
                openURL(analyticsDashboardURL)
            } label: {
                Label("분석 대시보드 열기", systemImage: "chart.line.uptrend.xyaxis")
            }
            Divider()
            Text("메트릭 설정은 사이드바 '설정 ▸ 메트릭'")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(DesignTokens.Colors.surfaceBase, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("메트릭 액션")
    }

    /// [2026-04-29] Grafana 전환 후: 메트릭 대시보드 탭은 `cview-app-player` 를
    /// 기본으로 연다. 운영 nginx 가 root 에 Grafana 를 mount.
    private var analyticsDashboardURL: URL {
        analyticsURL(path: "/d/cview-app-player")
    }

    /// 특정 채널의 player 대시보드 deeplink (`var-channel=<id>` templating).
    private func analyticsURL(forChannel channelId: String) -> URL {
        analyticsURL(path: "/d/cview-app-player", query: ["var-channel": channelId])
    }

    private func analyticsURL(path: String, query: [String: String] = [:]) -> URL {
        let raw = MetricsSettings.normalizeServerURL(appState.settingsStore.metrics.serverURL)
        if var components = URLComponents(string: raw), let host = components.host {
            components.scheme = "https"
            components.host = host
            components.port = nil
            components.path = path
            components.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.key, value: $0.value) }
            components.fragment = nil
            if let url = components.url { return url }
        }
        return URL(string: "https://cv.dododo.app\(path)")!
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 6) {
            ForEach(MetricsDashboardTab.allCases) { mode in
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        tabRaw = mode.rawValue
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.label)
                            .font(DesignTokens.Typography.captionSemibold)
                    }
                    .foregroundStyle(tab == mode
                                     ? DesignTokens.Colors.textPrimary
                                     : DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, 6)
                    .background {
                        if tab == mode {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.16))
                        }
                    }
                    .overlay {
                        if tab == mode {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.4), lineWidth: 0.6)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Tab Contents

    @ViewBuilder
    private var overviewContent: some View {
        compactKPISection
        serverSnapshotRow
        analyticsSection
        problemChannelsSection
        dbHealthDisclosure
    }

    @ViewBuilder
    private var channelsContent: some View {
        channelsInspectorView
    }

    // MARK: - Channels Inspector (Redesign 2026-04-28, P1)
    // 좌측 row table + 우측 선택 채널 inspector. 좁은 창은 row 위, 상세 아래 fallback.

    private static let channelInspectorSplitWidth: CGFloat = 1080

    @State private var inspectorContentWidth: CGFloat = 1024

    private var inspectorIsSplit: Bool {
        inspectorContentWidth >= Self.channelInspectorSplitWidth
    }

    /// 정렬/필터/검색 적용된 채널 목록.
    private var filteredChannels: [ChannelStatsItem] {
        let q = channelSearchText.lowercased()
        let base = viewModel.serverChannelStats.filter { stat in
            // 필터
            switch channelFilter {
            case .all: break
            case .withWeb: if stat.web == nil { return false }
            case .withApp: if stat.app == nil { return false }
            case .waiting: if stat.web != nil { return false }
            }
            // 검색
            if q.isEmpty { return true }
            let name = (stat.channelName ?? "").lowercased()
            let title = (stat.broadcast?.title ?? "").lowercased()
            return name.contains(q) || title.contains(q) || stat.channelId.lowercased().contains(q)
        }
        return sortChannelStats(base, by: channelSort)
    }

    private func sortChannelStats(_ list: [ChannelStatsItem], by mode: ChannelInspectorSort) -> [ChannelStatsItem] {
        switch mode {
        case .deltaDesc:
            return list.sorted { lhs, rhs in
                let lv = abs(lhs.delta?.current ?? 0)
                let rv = abs(rhs.delta?.current ?? 0)
                if lv != rv { return lv > rv }
                return lhs.channelId < rhs.channelId
            }
        case .samplesDesc:
            return list.sorted { lhs, rhs in
                let lv = (lhs.web?.samples ?? 0) + (lhs.app?.samples ?? 0)
                let rv = (rhs.web?.samples ?? 0) + (rhs.app?.samples ?? 0)
                if lv != rv { return lv > rv }
                return lhs.channelId < rhs.channelId
            }
        case .nameAsc:
            return list.sorted { lhs, rhs in
                let ln = lhs.channelName ?? lhs.channelId
                let rn = rhs.channelName ?? rhs.channelId
                if ln != rn { return ln < rn }
                return lhs.channelId < rhs.channelId
            }
        }
    }

    private var selectedChannel: ChannelStatsItem? {
        guard let id = selectedChannelId else { return nil }
        return viewModel.serverChannelStats.first { $0.channelId == id }
    }

    @ViewBuilder
    private var channelsInspectorView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            channelInspectorToolbar
            if viewModel.serverChannelStats.isEmpty {
                emptyChannelInspector
            } else if inspectorIsSplit {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    channelInspectorTable
                        .frame(width: 360)
                    channelInspectorPane
                        .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    channelInspectorTable
                        .frame(maxHeight: 320)
                    channelInspectorPane
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // 50px quantize
            let q = (width / 50).rounded() * 50
            if abs(inspectorContentWidth - q) >= 50 {
                inspectorContentWidth = q
            }
        }
        .onAppear { autoSelectInspectorChannel() }
        // [Fix M-3] Equatable 적용 → map(\.channelId) 불필요, 배열 전체 equality diff
        .onChange(of: viewModel.serverChannelStats) { _, _ in
            autoSelectInspectorChannel()
        }
    }

    private func autoSelectInspectorChannel() {
        if let id = selectedChannelId,
           viewModel.serverChannelStats.contains(where: { $0.channelId == id }) {
            return
        }
        selectedChannelId = filteredChannels.first?.channelId
    }

    private var channelInspectorToolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // 검색
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                TextField("채널/제목 검색", text: $channelSearchText)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 220)
            .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
            .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5) }

            // 필터 (segmented)
            HStack(spacing: 4) {
                ForEach(ChannelInspectorFilter.allCases) { f in
                    Button {
                        withAnimation(DesignTokens.Animation.snappy) { channelFilter = f }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: f.icon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(f.label)
                                .font(DesignTokens.Typography.micro)
                        }
                        .foregroundStyle(channelFilter == f ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if channelFilter == f {
                                Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.16))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // 정렬 menu
            Menu {
                ForEach(ChannelInspectorSort.allCases) { mode in
                    Button {
                        withAnimation(DesignTokens.Animation.snappy) { channelSort = mode }
                    } label: {
                        if channelSort == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text(channelSort.label)
                        .font(DesignTokens.Typography.micro)
                }
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                .overlay { Capsule().strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5) }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Text("\(filteredChannels.count) / \(viewModel.serverChannelStats.count)")
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .monospacedDigit()
        }
    }

    private var emptyChannelInspector: some View {
        HStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                Text("활성 채널이 없습니다")
                    .font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("스트림을 시청하면 자동으로 메트릭이 수집됩니다")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
            }
            Spacer()
        }
        .frame(height: 120)
    }

    private var channelInspectorTable: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filteredChannels) { stat in
                    channelInspectorRow(stat)
                }
                if filteredChannels.isEmpty {
                    Text("필터 조건에 맞는 채널이 없습니다")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(.vertical, DesignTokens.Spacing.lg)
                }
            }
            .padding(.vertical, 4)
        }
        .background(DesignTokens.Colors.surfaceElevated.opacity(0.4), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    private func channelInspectorRow(_ stat: ChannelStatsItem) -> some View {
        let isSelected = selectedChannelId == stat.channelId
        let qualityGrade = perChannelQualityGrade(stat)
        let deltaCur = stat.delta?.current
        return Button {
            selectedChannelId = stat.channelId
        } label: {
            HStack(spacing: 8) {
                // accent
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(qualityGrade.color)
                    .frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.channelName ?? stat.channelId.prefix(12).description)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text(qualityGrade.label)
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(qualityGrade.color)
                        if stat.web == nil {
                            Text("· 웹대기")
                                .font(DesignTokens.Typography.micro)
                                .foregroundStyle(.orange)
                        } else if stat.app == nil {
                            Text("· 앱대기")
                                .font(DesignTokens.Typography.micro)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                Spacer(minLength: 4)
                if let cur = deltaCur {
                    Text(String(format: "%+.0fms", cur))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(abs(cur) >= 100 ? .orange : DesignTokens.Colors.textSecondary)
                        .frame(minWidth: 60, alignment: .trailing)
                } else {
                    Text("—")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Colors.chzzkGreen.opacity(0.14))
                }
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct QualityGrade {
        let label: String
        let color: Color
    }

    private func perChannelQualityGrade(_ stat: ChannelStatsItem) -> QualityGrade {
        if stat.web == nil { return QualityGrade(label: "웹대기", color: .orange) }
        guard let cur = stat.delta?.current else {
            return QualityGrade(label: "측정중", color: .gray)
        }
        let abs_cur = abs(cur)
        if abs_cur < 50 { return QualityGrade(label: "양호", color: DesignTokens.Colors.chzzkGreen) }
        if abs_cur < 150 { return QualityGrade(label: "주의", color: .yellow) }
        if abs_cur < 300 { return QualityGrade(label: "이상", color: .orange) }
        return QualityGrade(label: "심각", color: .red)
    }

    @ViewBuilder
    private var channelInspectorPane: some View {
        if let stat = selectedChannel {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                channelInspectorHeader(stat)
                channelInspectorActions(stat)
                channelDetailCard(stat)
            }
        } else {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "hand.point.left")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                    Text("왼쪽에서 채널을 선택해 주세요")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                Spacer()
            }
            .frame(minHeight: 200)
        }
    }

    private func channelInspectorHeader(_ stat: ChannelStatsItem) -> some View {
        let grade = perChannelQualityGrade(stat)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(grade.color)
                .frame(width: 4, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.channelName ?? stat.channelId.prefix(12).description)
                    .font(DesignTokens.Typography.custom(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(stat.channelId)
                    .font(DesignTokens.Typography.monoMedium)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
            Text(grade.label)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(grade.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(grade.color.opacity(0.16), in: Capsule())
        }
    }

    private func channelInspectorActions(_ stat: ChannelStatsItem) -> some View {
        HStack(spacing: 8) {
            Button {
                router.navigate(to: .live(channelId: stat.channelId))
            } label: {
                Label("단일 라이브 열기", systemImage: "play.rectangle.fill")
                    .font(DesignTokens.Typography.captionSemibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(DesignTokens.Colors.chzzkGreen)

            Button {
                Task {
                    await appState.multiLiveManager.addSession(
                        channelId: stat.channelId,
                        presentationOverride: .embedded
                    )
                }
            } label: {
                Label("멀티라이브 추가", systemImage: "plus.rectangle.on.rectangle")
                    .font(DesignTokens.Typography.captionSemibold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                router.navigate(to: .channelDetail(channelId: stat.channelId))
            } label: {
                Label("채널 상세", systemImage: "info.circle")
                    .font(DesignTokens.Typography.captionSemibold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button {
                openURL(analyticsURL(forChannel: stat.channelId))
            } label: {
                Label("Analytics", systemImage: "chart.line.uptrend.xyaxis")
                    .font(DesignTokens.Typography.captionSemibold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Grafana app-player 대시보드에서 이 채널만 필터링")
        }
    }

    @ViewBuilder
    private var monitoringContent: some View {
        opsTimelineView
    }

    // MARK: - Ops Timeline (Monitoring tab P2 — derived snapshot)
    // 별도 이벤트 buffer 없이 현재 상태에서 즉시 도출 가능한 신호만 라인업.
    // (latencyHistory 스파이크 / WS 끊김 / 채널 편차 / DB 비정상 / 웹 대기)

    private struct OpsEvent: Identifiable {
        enum Severity { case info, warn, error
            var color: Color {
                switch self {
                case .info: return DesignTokens.Colors.accentCyan
                case .warn: return .orange
                case .error: return .red
                }
            }
            var icon: String {
                switch self {
                case .info: return "info.circle.fill"
                case .warn: return "exclamationmark.triangle.fill"
                case .error: return "xmark.octagon.fill"
                }
            }
            var label: String {
                switch self { case .info: return "INFO"; case .warn: return "WARN"; case .error: return "ERR" }
            }
        }
        let id: String
        let severity: Severity
        let title: String
        let detail: String
        let timestamp: Date?
    }

    private var opsEvents: [OpsEvent] {
        var out: [OpsEvent] = []
        let now = Date()

        // WS 상태
        if viewModel.isWebSocketConnected {
            out.append(OpsEvent(
                id: "ws-ok",
                severity: .info,
                title: "WebSocket 연결됨",
                detail: "메시지 \(viewModel.wsMessageCount.formatted())건 누적",
                timestamp: viewModel.serverLastUpdate
            ))
        } else {
            out.append(OpsEvent(
                id: "ws-down",
                severity: .error,
                title: "WebSocket 끊김",
                detail: "30초 폴백 폴링 사용 중. 자동 재연결 시도",
                timestamp: nil
            ))
        }

        // DB 비정상
        let sys = viewModel.systemStats
        if let sys {
            if let s = sys.influxdb?.status, !isHealthy(s) {
                out.append(OpsEvent(id: "db-influx", severity: .error, title: "InfluxDB 이상", detail: "status=\(s)", timestamp: nil))
            }
            if let s = sys.postgres, !isHealthy(s) {
                out.append(OpsEvent(id: "db-pg", severity: .error, title: "PostgreSQL 이상", detail: "status=\(s)", timestamp: nil))
            }
            if let s = sys.redis?.status, !isHealthy(s) {
                out.append(OpsEvent(id: "db-redis", severity: .warn, title: "Redis 이상", detail: "status=\(s)", timestamp: nil))
            }
        }

        // latency 스파이크 (history 최근 60초 내 |delta|>200ms)
        let recent = viewModel.latencyHistory.suffix(120)
        let spikes = recent.compactMap { entry -> (Date, Double)? in
            guard let w = entry.webLatency, let a = entry.appLatency else { return nil }
            let d = a - w
            return abs(d) >= 200 ? (entry.timestamp, d) : nil
        }
        if let last = spikes.last, now.timeIntervalSince(last.0) < 600 {
            out.append(OpsEvent(
                id: "spike-latest",
                severity: .warn,
                title: "최근 지연 스파이크",
                detail: String(format: "Δ %+0.0fms (총 %d회 in 2분)", last.1, spikes.count),
                timestamp: last.0
            ))
        }

        // 편차 큰 채널
        let problemDelta = viewModel.serverChannelStats.filter { abs($0.delta?.current ?? 0) >= 150 }
        if !problemDelta.isEmpty {
            let top = problemDelta
                .sorted { abs($0.delta?.current ?? 0) > abs($1.delta?.current ?? 0) }
                .prefix(3)
                .map { stat -> String in
                    let name = stat.channelName ?? stat.channelId.prefix(8).description
                    let cur = stat.delta?.current ?? 0
                    return String(format: "%@ %+0.0fms", name, cur)
                }
                .joined(separator: " · ")
            out.append(OpsEvent(
                id: "delta-channels",
                severity: .warn,
                title: "\(problemDelta.count)개 채널 편차 ≥150ms",
                detail: top,
                timestamp: nil
            ))
        }

        // 웹 대기
        let waiting = viewModel.serverChannelStats.filter { $0.web == nil }
        if !waiting.isEmpty {
            out.append(OpsEvent(
                id: "waiting",
                severity: .info,
                title: "\(waiting.count)개 채널 웹 데이터 대기",
                detail: "수집기 미부착 또는 신규 채널",
                timestamp: nil
            ))
        }

        // 마지막 server update 신선도
        if let last = viewModel.serverLastUpdate {
            let age = now.timeIntervalSince(last)
            if age >= 60 {
                out.append(OpsEvent(
                    id: "stale",
                    severity: .warn,
                    title: "서버 데이터 \(Int(age))초 미수신",
                    detail: "WebSocket 또는 폴백 응답 지연",
                    timestamp: last
                ))
            }
        }

        return out
    }

    @ViewBuilder
    private var opsTimelineView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentCyan)
                Text("운영 타임라인")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Text("현재 상태 기반 · 영구 buffer 미사용")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }

            let events = opsEvents
            if events.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.7))
                        Text("이상 신호 없음")
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                        Text("시스템·동기화·채널 모두 정상 범위")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.xl)
                .frame(maxWidth: .infinity)
                .background(DesignTokens.Colors.surfaceElevated.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(events) { event in
                        opsEventRow(event)
                    }
                }
            }

            // 라이브 latency 스파크라인 (compact)
            if !viewModel.latencyHistory.isEmpty {
                latencySparkBlock
            }
        }
    }

    private func opsEventRow(_ event: OpsEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.severity.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(event.severity.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.severity.label)
                        .font(DesignTokens.Typography.custom(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(event.severity.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(event.severity.color.opacity(0.16), in: Capsule())
                    Text(event.title)
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer(minLength: 4)
                    if let ts = event.timestamp {
                        Text(opsRelativeTime(ts))
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .monospacedDigit()
                    }
                }
                Text(event.detail)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surfaceElevated.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(event.severity.color.opacity(0.25), lineWidth: 0.5)
        }
    }

    private func opsRelativeTime(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "방금" }
        if s < 60 { return "\(s)초 전" }
        if s < 3600 { return "\(s/60)분 전" }
        return "\(s/3600)시간 전"
    }

    @ViewBuilder
    private var latencySparkBlock: some View {
        let recent = Array(viewModel.latencyHistory.suffix(60))
        let deltas = recent.compactMap { e -> Double? in
            guard let w = e.webLatency, let a = e.appLatency else { return nil }
            return a - w
        }
        if !deltas.isEmpty {
            let maxAbs = max(deltas.map(abs).max() ?? 1, 50)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.accentCyan)
                    Text("최근 \(deltas.count)포인트 Δ (App−Web)")
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Spacer()
                    Text(String(format: "최대 ±%.0fms", maxAbs))
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let count = max(deltas.count, 1)
                    let stepX = w / CGFloat(max(count - 1, 1))
                    Path { path in
                        for (i, d) in deltas.enumerated() {
                            let x = CGFloat(i) * stepX
                            let norm = CGFloat(d / maxAbs)
                            let y = h/2 - norm * (h/2 - 2)
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(DesignTokens.Colors.accentCyan, lineWidth: 1.2)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h/2))
                        path.addLine(to: CGPoint(x: w, y: h/2))
                    }
                    .stroke(DesignTokens.Colors.textTertiary.opacity(0.25), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
                .frame(height: 36)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesignTokens.Colors.surfaceElevated.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            }
        }
    }

    // MARK: - Compact KPI (Overview)

    private var compactKPISection: some View {
        let cview = viewModel.serverStats?.cviewSummary
        let grade = cview?.aggregate?.qualityGrade
        let waitingChannels = cview?.aggregate?.waitingChannels ?? 0

        return HStack(spacing: DesignTokens.Spacing.sm) {
            metricTile(
                title: "활성 채널",
                value: "\(viewModel.serverChannelStats.count)",
                subtitle: viewModel.activeAppChannelCount > 0 ? "\(viewModel.activeAppChannelCount) 시청 중" : nil,
                icon: "play.circle",
                color: DesignTokens.Colors.accentCyan
            )
            if let grade, grade != "-" {
                metricTile(
                    title: "동기화 품질",
                    value: grade,
                    subtitle: cview.map { cviewAggregateSubtitle($0) },
                    icon: "gauge.with.needle",
                    color: gradeColor(grade)
                )
            } else if waitingChannels > 0 {
                metricTile(
                    title: "동기화 품질",
                    value: "–",
                    subtitle: "웹 데이터 대기 \(waitingChannels)채널",
                    icon: "gauge.with.needle",
                    color: .orange
                )
            } else {
                metricTile(
                    title: "동기화 품질",
                    value: "—",
                    subtitle: "대기 중",
                    icon: "gauge.with.needle",
                    color: .gray
                )
            }
            metricTile(
                title: "웹 레이턴시",
                value: viewModel.avgWebLatency.map { String(format: "%.0fms", $0) } ?? "—",
                subtitle: viewModel.avgWebLatency != nil ? "평균" : "데이터 없음",
                icon: "globe",
                color: viewModel.avgWebLatency != nil ? DesignTokens.Colors.accentCyan : .gray
            )
            metricTile(
                title: "CView 레이턴시",
                value: viewModel.avgAppLatency.map { String(format: "%.0fms", $0) } ?? "—",
                subtitle: viewModel.avgAppLatency != nil ? "평균" : "데이터 없음",
                icon: "desktopcomputer",
                color: viewModel.avgAppLatency != nil ? DesignTokens.Colors.chzzkGreen : .gray
            )
        }
    }

    // MARK: - Server Snapshot Row (always-on)
    //
    // 활성 채널 0이거나 라이브 트래픽이 없는 시점에도 cv.dododo.app 누적 데이터를
    // 4-tile 로 항상 표시한다. overview/system 응답을 그대로 사용.

    private var serverSnapshotRow: some View {
        let sys = viewModel.systemStats
        let overview = viewModel.serverStats
        // overview 의 totalMetrics 는 alias 디코더에 의해 totalMetrics24h 가 매핑되어 들어온다.
        let total24h = viewModel.serverTotalReceived
        let recordsTotal = sys?.recordsTotal
        let dbBytes = sys?.dbSizeBytes
        // CView 클라이언트 수가 0 이면 좀 더 의미있는 우상귀: connectedClients 폴백 → 24h 평균 레이턴시 → 업타임
        let connClients = overview?.cviewSummary?.connectedClients ?? 0
        let uptimeStr = viewModel.formattedUptime

        return HStack(spacing: DesignTokens.Spacing.sm) {
            metricTile(
                title: "24시간 메트릭",
                value: total24h > 0 ? formatLargeNumber(total24h) : "—",
                subtitle: total24h > 0 ? "최근 24h 수집" : "데이터 대기",
                icon: "chart.bar.fill",
                color: DesignTokens.Colors.accentBlue
            )
            metricTile(
                title: "누적 레코드",
                value: recordsTotal.map { formatLargeNumber($0) } ?? "—",
                subtitle: recordsTotal != nil ? "전체 데이터베이스" : "수집 대기",
                icon: "tray.full.fill",
                color: DesignTokens.Colors.accentPurple
            )
            metricTile(
                title: "DB 크기",
                value: dbBytes.map { formatBytes($0) } ?? "—",
                subtitle: dbBytes != nil ? "디스크 사용량" : "측정 대기",
                icon: "internaldrive.fill",
                color: DesignTokens.Colors.accentOrange
            )
            metricTile(
                title: connClients > 0 ? "CView 클라이언트" : "서버 가동",
                value: connClients > 0 ? "\(connClients)" : (uptimeStr.isEmpty ? "—" : uptimeStr),
                subtitle: connClients > 0 ? "실시간 연결" : (viewModel.isMetricsServerOnline ? "온라인" : "오프라인"),
                icon: connClients > 0 ? "person.2.fill" : "clock.fill",
                color: viewModel.isMetricsServerOnline ? DesignTokens.Colors.chzzkGreen : .gray
            )
        }
    }

    // MARK: - Problem Channels (Overview)
    // delta 큰 채널 / 웹 데이터 없는 채널 / 동기화 추천(speed_up, slow_down, hold) 채널만 추림.

    private struct ProblemChannel: Identifiable {
        let stat: ChannelStatsItem
        let kind: Kind
        var id: String { stat.channelId + kind.rawValue }
        enum Kind: String { case latencyDelta, webMissing, syncAction }
    }

    private var problemChannels: [ProblemChannel] {
        let stats = viewModel.serverChannelStats
        guard !stats.isEmpty else { return [] }
        let syncMap: [String: String] = Dictionary(
            uniqueKeysWithValues: (viewModel.serverStats?.cviewSummary?.syncChannels ?? [])
                .compactMap { entry -> (String, String)? in
                    guard let cid = entry.channelId,
                          let action = entry.recommendation?.action,
                          action != "hold" else { return nil }
                    return (cid, action)
                }
        )
        var seen = Set<String>()
        var result: [ProblemChannel] = []
        for stat in stats {
            // 1) latency delta 큼 (절대값 100ms 이상)
            if let cur = stat.delta?.current, abs(cur) >= 100, !seen.contains(stat.channelId) {
                result.append(ProblemChannel(stat: stat, kind: .latencyDelta))
                seen.insert(stat.channelId)
                continue
            }
            // 2) 동기화 액션 권고 있음
            if syncMap[stat.channelId] != nil, !seen.contains(stat.channelId) {
                result.append(ProblemChannel(stat: stat, kind: .syncAction))
                seen.insert(stat.channelId)
                continue
            }
            // 3) 웹 데이터 missing (앱 데이터는 있는데 웹은 없음)
            if stat.web == nil, stat.app != nil, !seen.contains(stat.channelId) {
                result.append(ProblemChannel(stat: stat, kind: .webMissing))
                seen.insert(stat.channelId)
                continue
            }
        }
        return result
    }

    @ViewBuilder
    private var problemChannelsSection: some View {
        let problems = problemChannels
        sectionContainer(title: "문제 채널", icon: "exclamationmark.triangle") {
            if problems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("이상 징후가 감지된 채널이 없습니다")
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            } else {
                VStack(spacing: 6) {
                    ForEach(problems.prefix(8)) { problem in
                        problemChannelRow(problem)
                    }
                    if problems.count > 8 {
                        HStack {
                            Spacer()
                            Button {
                                tabRaw = MetricsDashboardTab.channels.rawValue
                            } label: {
                                Text("+\(problems.count - 8)개 더 보기 → 채널 탭")
                                    .font(DesignTokens.Typography.micro)
                                    .foregroundStyle(DesignTokens.Colors.accentCyan)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func problemChannelRow(_ problem: ProblemChannel) -> some View {
        let stat = problem.stat
        let (label, tint, detail): (String, Color, String) = {
            switch problem.kind {
            case .latencyDelta:
                let cur = stat.delta?.current ?? 0
                return ("레이턴시 편차", .orange, String(format: "%+.0fms", cur))
            case .webMissing:
                return ("웹 데이터 대기", .yellow, "수집기 확인 필요")
            case .syncAction:
                let action = (viewModel.serverStats?.cviewSummary?.syncChannels ?? [])
                    .first { $0.channelId == stat.channelId }?.recommendation?.action
                return ("동기화 권고", .pink, cviewActionLabel(action))
            }
        }()
        return HStack(spacing: 10) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(stat.channelName ?? stat.channelId.prefix(12).description)
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(label)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.14), in: Capsule())
            Text(detail)
                .font(DesignTokens.Typography.monoMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 6)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.6), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    // MARK: - DB Health Disclosure (Overview)

    private var dbHealthDisclosure: some View {
        DisclosureGroup(isExpanded: $dbHealthExpanded) {
            systemHealthSection
                .padding(.top, DesignTokens.Spacing.sm)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text("DB 상세")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(viewModel.serverStats?.serverVersion ?? "")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        // 글로우 도트
                        ZStack {
                            Circle()
                                .fill(viewModel.isMetricsServerOnline ? DesignTokens.Colors.chzzkGreen : .red)
                                .frame(width: 10, height: 10)
                            if viewModel.isMetricsServerOnline {
                                Circle()
                                    .fill(DesignTokens.Colors.chzzkGreen.opacity(0.4))
                                    .frame(width: 10, height: 10)
                                    .scaleEffect(appearAnimated ? 2.2 : 1.0)
                                    .opacity(appearAnimated ? 0 : 0.6)
                                    .animation(DesignTokens.Animation.pulse, value: appearAnimated)
                            }
                        }
                        Text("CView 서버")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }

                    Text("cv.dododo.app")
                        .font(DesignTokens.Typography.monoMedium)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }

                Spacer()

                HStack(spacing: DesignTokens.Spacing.sm) {
                    // 연결 모드 배지
                    connectionBadge

                    // 마지막 업데이트
                    if let lastUpdate = viewModel.serverLastUpdate {
                        Text(lastUpdate, format: .dateTime.hour().minute().second())
                            .font(DesignTokens.Typography.monoMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }

                    // 새로고침
                    Button {
                        Task { await viewModel.loadServerStats() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignTokens.Typography.bodyMedium)
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 28, height: 28)
                            .background(DesignTokens.Colors.chzzkGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 악센트 라인
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.5)
                .opacity(appearAnimated ? 1 : 0)
                .scaleEffect(x: appearAnimated ? 1 : 0, anchor: .leading)
                .animation(DesignTokens.Animation.smooth, value: appearAnimated)
        }
    }

    private var connectionBadge: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: viewModel.isWebSocketConnected ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 9, weight: .bold))
            Text(viewModel.isWebSocketConnected ? "실시간" : "폴링")
                .font(DesignTokens.Typography.captionSemibold)
        }
        .foregroundStyle(viewModel.isWebSocketConnected ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            (viewModel.isWebSocketConnected ? DesignTokens.Colors.chzzkGreen : Color.gray)
                .opacity(0.1),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                viewModel.isWebSocketConnected ? DesignTokens.Colors.chzzkGreen.opacity(0.3) : Color.clear,
                lineWidth: 0.5
            )
        )
    }

    // MARK: - Server Overview Bar

    private var serverOverviewBar: some View {
        HStack(spacing: 0) {
            overviewCell(
                icon: "server.rack",
                title: "상태",
                value: viewModel.isMetricsServerOnline ? "온라인" : "오프라인",
                color: viewModel.isMetricsServerOnline ? DesignTokens.Colors.chzzkGreen : .red
            )
            overviewDivider
            overviewCell(
                icon: "tag",
                title: "버전",
                value: viewModel.serverStats?.serverVersion ?? "—",
                color: DesignTokens.Colors.accentBlue
            )
            overviewDivider
            overviewCell(
                icon: "clock",
                title: "업타임",
                value: viewModel.formattedUptime,
                color: DesignTokens.Colors.accentCyan
            )
            overviewDivider
            overviewCell(
                icon: "arrow.down.circle",
                title: "총 수신",
                value: formatLargeNumber(viewModel.serverTotalReceived),
                color: DesignTokens.Colors.chzzkGreen
            )
            overviewDivider
            overviewCell(
                icon: "play.circle",
                title: "활성 채널",
                value: "\(viewModel.serverChannelStats.count)",
                color: DesignTokens.Colors.accentCyan
            )
        }
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private func overviewCell(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(value)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(DesignTokens.Glass.borderColor)
            .frame(width: 0.5, height: 32)
    }

    // MARK: - System Health

    private var systemHealthSection: some View {
        sectionContainer(title: "시스템 헬스", icon: "heart.text.square") {
            if let sys = viewModel.systemStats {
                VStack(spacing: DesignTokens.Spacing.md) {
                    // [Shape Tolerance 2026-04-28]
                    // 1. 명시적 InfluxDB/Postgres/Redis breakdown 우선.
                    // 2. 없으면 services 맵 기반 카드.
                    if sys.influxdb != nil || sys.postgres != nil || sys.redis != nil {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            healthCard(
                                name: "InfluxDB",
                                status: sys.influxdb?.status,
                                detail: sys.influxdb?.version,
                                icon: "cylinder",
                                color: DesignTokens.Colors.accentOrange
                            )
                            healthCard(
                                name: "PostgreSQL",
                                status: sys.postgres,
                                detail: nil,
                                icon: "tablecells",
                                color: DesignTokens.Colors.accentBlue
                            )
                            healthCard(
                                name: "Redis",
                                status: sys.redis?.status,
                                detail: sys.redis?.usedMemory,
                                icon: "memorychip",
                                color: DesignTokens.Colors.accentPurple
                            )
                        }
                    } else if let services = sys.services, !services.isEmpty {
                        servicesHealthGrid(services)
                    } else {
                        Text("DB 상태 정보 없음")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 레코드 수 — recordCounts (v4.5 nested) 우선, 없으면 flat 응답.
                    if let records = sys.recordCounts {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            recordPill(title: "채널", count: records.channels, icon: "play.circle", color: DesignTokens.Colors.accentCyan)
                            recordPill(title: "VLC", count: records.vlcMetrics, icon: "desktopcomputer", color: DesignTokens.Colors.chzzkGreen)
                            recordPill(title: "웹", count: records.webMetrics, icon: "globe", color: DesignTokens.Colors.accentBlue)
                            recordPill(title: "일간", count: records.dailyStats, icon: "calendar", color: DesignTokens.Colors.accentPurple)
                            recordPill(title: "시간별", count: records.hourlyStats, icon: "clock", color: DesignTokens.Colors.accentOrange)
                        }
                    } else if sys.recordsLast24h != nil || sys.recordsTotal != nil || sys.dbSizeBytes != nil {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            recordPill(title: "24시간", count: sys.recordsLast24h, icon: "clock", color: DesignTokens.Colors.accentOrange)
                            recordPill(title: "누적", count: sys.recordsTotal, icon: "tray.full", color: DesignTokens.Colors.accentBlue)
                            if let bytes = sys.dbSizeBytes {
                                HStack(spacing: DesignTokens.Spacing.xs) {
                                    Image(systemName: "internaldrive")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(DesignTokens.Colors.accentPurple)
                                    Text("DB")
                                        .font(DesignTokens.Typography.micro)
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    Text(formatBytes(bytes))
                                        .font(DesignTokens.Typography.captionSemibold)
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, DesignTokens.Spacing.sm)
                                .padding(.vertical, 6)
                                .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    // 마지막 체크 시각
                    if let checkedAt = sys.checkedAt {
                        HStack {
                            Spacer()
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                Text("마지막 체크 \(checkedAt)")
                                    .font(DesignTokens.Typography.micro)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                        }
                    }
                }
            } else {
                systemLoadingPlaceholder
            }
        }
    }

    /// services 맵을 카드 그리드로 렌더 (cv.dododo.app 처럼 flat 응답인 경우).
    private func servicesHealthGrid(_ services: [String: String]) -> some View {
        let sorted = services.sorted { $0.key < $1.key }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.sm), count: min(3, max(sorted.count, 1))), spacing: DesignTokens.Spacing.sm) {
            ForEach(sorted, id: \.key) { entry in
                healthCard(
                    name: serviceDisplayName(entry.key),
                    status: entry.value,
                    detail: entry.key,
                    icon: serviceIcon(entry.key),
                    color: serviceTint(entry.key)
                )
            }
        }
    }

    private func serviceDisplayName(_ key: String) -> String {
        switch key.lowercased() {
        case "cview-api", "cview", "api": return "CView API"
        case "influxdb", "influx": return "InfluxDB"
        case "postgres", "postgresql", "pg": return "PostgreSQL"
        case "redis": return "Redis"
        case "nginx": return "nginx"
        case "ws", "websocket": return "WebSocket"
        default: return key
        }
    }

    private func serviceIcon(_ key: String) -> String {
        switch key.lowercased() {
        case "cview-api", "cview", "api": return "server.rack"
        case "influxdb", "influx": return "cylinder"
        case "postgres", "postgresql", "pg": return "tablecells"
        case "redis": return "memorychip"
        case "nginx": return "shippingbox"
        case "ws", "websocket": return "dot.radiowaves.left.and.right"
        default: return "gearshape"
        }
    }

    private func serviceTint(_ key: String) -> Color {
        switch key.lowercased() {
        case "cview-api", "cview", "api": return DesignTokens.Colors.chzzkGreen
        case "influxdb", "influx":        return DesignTokens.Colors.accentOrange
        case "postgres", "postgresql", "pg": return DesignTokens.Colors.accentBlue
        case "redis":                     return DesignTokens.Colors.accentPurple
        case "nginx":                     return DesignTokens.Colors.accentCyan
        default:                          return DesignTokens.Colors.textSecondary
        }
    }

    /// Bytes → 사람이 읽을 수 있는 포맷.
    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB, .useTB]
        f.countStyle = .binary
        return f.string(fromByteCount: Int64(bytes))
    }

    private func healthCard(name: String, status: String?, detail: String?, icon: String, color: Color) -> some View {
        let isOk = status?.lowercased() == "connected" || status?.lowercased() == "ok" || status?.lowercased() == "healthy"
        let statusColor = isOk ? DesignTokens.Colors.chzzkGreen : .red

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(status ?? "알 수 없음")
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(statusColor)
                    .textCase(.uppercase)
                if let detail {
                    Text(detail)
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private func recordPill(title: String, count: Int?, icon: String, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
            Text(title)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(count.map { formatLargeNumber($0) } ?? "—")
                .font(DesignTokens.Typography.captionSemibold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private var systemLoadingPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("시스템 데이터 로딩 중...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .frame(height: 80)
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        sectionContainer(title: "수집 메트릭", icon: "chart.bar.doc.horizontal") {
            VStack(spacing: DesignTokens.Spacing.sm) {
                // 첫 줄: 트래픽 메트릭
                HStack(spacing: DesignTokens.Spacing.sm) {
                    metricTile(
                        title: "실시간 수신",
                        value: viewModel.wsMessageCount > 0 ? formatLargeNumber(viewModel.wsMessageCount) : "—",
                        subtitle: viewModel.wsMessageCount > 0 ? "WebSocket" : "대기 중",
                        icon: "bolt.circle.fill",
                        color: viewModel.wsMessageCount > 0 ? .yellow : .gray
                    )
                    metricTile(
                        title: "웹 레이턴시",
                        value: viewModel.avgWebLatency.map { String(format: "%.0fms", $0) } ?? "—",
                        subtitle: viewModel.avgWebLatency != nil ? "평균" : "데이터 없음",
                        icon: "globe",
                        color: viewModel.avgWebLatency != nil ? DesignTokens.Colors.accentCyan : .gray
                    )
                    metricTile(
                        title: "CView 레이턴시",
                        value: viewModel.avgAppLatency.map { String(format: "%.0fms", $0) } ?? "—",
                        subtitle: viewModel.avgAppLatency != nil ? "평균" : "데이터 없음",
                        icon: "desktopcomputer",
                        color: viewModel.avgAppLatency != nil ? DesignTokens.Colors.chzzkGreen : .gray
                    )
                }

                // 둘째 줄: 클라이언트 메트릭
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if let stats = viewModel.serverStats {
                        let platforms = stats.resolvedPlatforms
                        metricTile(
                            title: "플랫폼",
                            value: platforms.isEmpty ? "—" : platforms.map { "\($0.key): \($0.value)" }.joined(separator: ", "),
                            subtitle: nil,
                            icon: "rectangle.stack",
                            color: platforms.isEmpty ? .gray : DesignTokens.Colors.accentPurple
                        )
                    }
                    metricTile(
                        title: "CView 클라이언트",
                        value: "\(viewModel.serverStats?.cviewSummary?.connectedClients ?? 0)",
                        subtitle: viewModel.serverStats?.cviewSummary.map { cviewSyncLabel($0) },
                        icon: "monitor.and.phone",
                        color: (viewModel.serverStats?.cviewSummary?.connectedClients ?? 0) > 0 ? DesignTokens.Colors.accentPurple : .gray
                    )
                    syncQualityTile
                }
            }
        }
    }

    private func metricTile(title: String, value: String, subtitle: String?, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.micro)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Text(value)
                    .font(DesignTokens.Typography.display)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignTokens.Typography.micro)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var syncQualityTile: some View {
        if let cview = viewModel.serverStats?.cviewSummary {
            if let grade = cview.aggregate?.qualityGrade, grade != "-" {
                metricTile(
                    title: "동기화 품질",
                    value: grade,
                    subtitle: cviewAggregateSubtitle(cview),
                    icon: "gauge.with.needle",
                    color: gradeColor(grade)
                )
            } else if let agg = cview.aggregate, (agg.waitingChannels ?? 0) > 0 {
                metricTile(
                    title: "동기화 품질",
                    value: "–",
                    subtitle: "웹 데이터 대기 중 (\(agg.waitingChannels ?? 0)채널)",
                    icon: "gauge.with.needle",
                    color: .gray
                )
            } else {
                metricTile(
                    title: "동기화 품질",
                    value: "—",
                    subtitle: "대기 중",
                    icon: "gauge.with.needle",
                    color: .gray
                )
            }
        } else {
            metricTile(
                title: "동기화 품질",
                value: "—",
                subtitle: "대기 중",
                icon: "gauge.with.needle",
                color: .gray
            )
        }
    }

    // MARK: - Analytics

    private var analyticsSection: some View {
        sectionContainer(title: "분석", icon: "chart.xyaxis.line") {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                LatencyComparisonChart(history: viewModel.latencyHistory)
                    .frame(maxWidth: .infinity)
                latencyDistributionChart
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var latencyDistributionChart: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("채널별 레이턴시 분포")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                // 범례
                HStack(spacing: DesignTokens.Spacing.sm) {
                    legendDot(color: .cyan, label: "웹")
                    legendDot(color: DesignTokens.Colors.chzzkGreen, label: "앱")
                }
            }

            if viewModel.serverChannelStats.isEmpty {
                emptyChartState
            } else {
                let hasAnyData = viewModel.serverChannelStats.contains { ch in
                    ((ch.web?.samples ?? 0) > 0 && ch.web?.avg != nil) ||
                    ((ch.app?.samples ?? 0) > 0 && ch.app?.avg != nil)
                }
                if !hasAnyData {
                    emptyChartState
                } else {
                    Chart(viewModel.serverChannelStats) { stat in
                        let channelName = stat.channelName ?? stat.channelId.prefix(8).description
                        if let web = stat.web, (web.samples ?? 0) > 0, let webAvg = web.avg {
                            BarMark(
                                x: .value("채널", channelName),
                                y: .value("레이턴시", webAvg)
                            )
                            .foregroundStyle(.cyan.opacity(0.75))
                            .position(by: .value("타입", "웹"))
                            .cornerRadius(3)
                            .annotation(position: .top, spacing: 2) {
                                Text(String(format: "%.0f", webAvg))
                                    .font(DesignTokens.Typography.custom(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                        }
                        if let app = stat.app, (app.samples ?? 0) > 0, let appAvg = app.avg {
                            BarMark(
                                x: .value("채널", channelName),
                                y: .value("레이턴시", appAvg)
                            )
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.75))
                            .position(by: .value("타입", "앱"))
                            .cornerRadius(3)
                            .annotation(position: .top, spacing: 2) {
                                Text(String(format: "%.0f", appAvg))
                                    .font(DesignTokens.Typography.custom(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .font(DesignTokens.Typography.micro)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(DesignTokens.Colors.border)
                            AxisValueLabel()
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .font(DesignTokens.Typography.micro)
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 160)
                    .drawingGroup()
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }

    private var emptyChartState: some View {
        HStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                Text("데이터 수집 중...")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Spacer()
        }
        .frame(height: 160)
    }

    // MARK: - Channel Detail

    private var channelDetailSection: some View {
        sectionContainer(title: "채널 상세", icon: "antenna.radiowaves.left.and.right") {
            if viewModel.serverChannelStats.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                        Text("활성 채널이 없습니다")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                        Text("스트림을 시청하면 자동으로 메트릭이 수집됩니다")
                            .font(DesignTokens.Typography.micro)
                            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
                    }
                    Spacer()
                }
                .frame(height: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: DesignTokens.Spacing.sm)], spacing: DesignTokens.Spacing.sm) {
                    ForEach(viewModel.serverChannelStats) { stat in
                        channelDetailCard(stat)
                    }
                }
            }
        }
    }

    private func channelDetailCard(_ stat: ChannelStatsItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Text(stat.channelName ?? stat.channelId.prefix(12).description)
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let quality = stat.quality {
                    Text(quality)
                        .font(DesignTokens.Typography.microSemibold)
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .background(DesignTokens.Colors.chzzkGreen.opacity(0.1), in: Capsule())
                }
            }
            .padding(DesignTokens.Spacing.md)

            // 스트림 정보 태그
            if let resolution = stat.resolution {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    streamTag(icon: "display", text: resolution)
                    if let bitrate = stat.bitrate {
                        streamTag(icon: "speedometer", text: String(format: "%.1f Mbps", bitrate))
                    }
                    if let fps = stat.fps {
                        streamTag(icon: "film", text: String(format: "%.0f fps", fps))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
            }

            // 레이턴시 비교 바
            HStack(spacing: 0) {
                latencyCell(title: "웹", stats: stat.web, color: .cyan)
                Rectangle().fill(DesignTokens.Glass.borderColor).frame(width: 0.5)
                latencyCell(title: "CView", stats: stat.app, color: DesignTokens.Colors.chzzkGreen)
                if let delta = stat.delta {
                    Rectangle().fill(DesignTokens.Glass.borderColor).frame(width: 0.5)
                    deltaCell(delta: delta)
                }
            }
            .background(DesignTokens.Colors.surfaceBase.opacity(0.5))

            // 방송 정보
            if let broadcast = stat.broadcast, broadcast.title != nil {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    if let title = broadcast.title {
                        Text(title)
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        if let category = broadcast.category {
                            streamTag(icon: "tag", text: category)
                        }
                        if let viewers = broadcast.concurrentUsers {
                            streamTag(icon: "person.2", text: formatLargeNumber(viewers))
                        }
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }

            // CView 동기화 정보
            if let syncChannel = viewModel.serverStats?.cviewSummary?.syncChannels?.first(where: { $0.channelId == stat.channelId }),
               let rec = syncChannel.recommendation {
                Rectangle().fill(DesignTokens.Glass.borderColor).frame(height: 0.5)
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: cviewActionIcon(rec.action))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(syncActionColor(rec.action))
                    Text(cviewActionLabel(rec.action))
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(syncActionColor(rec.action))

                    Spacer()

                    HStack(spacing: DesignTokens.Spacing.sm) {
                        if let tier = rec.tier {
                            syncBadge(text: tier)
                        }
                        if let speed = rec.suggestedSpeed, speed != 1.0 {
                            syncBadge(text: String(format: "%.2fx", speed))
                        }
                        if let delta = rec.delta {
                            syncBadge(text: String(format: "%+.0fms", delta))
                        }
                        if let confidence = rec.confidence {
                            syncBadge(text: String(format: "%.0f%%", confidence * 100))
                        }
                    }
                }
                .padding(DesignTokens.Spacing.md)
            }
        }
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        )
    }

    private func streamTag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(text)
                .font(DesignTokens.Typography.micro)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, 2)
        .background(DesignTokens.Colors.surfaceBase.opacity(0.6), in: Capsule())
    }

    private func latencyCell(title: String, stats: LatencyStats?, color: Color) -> some View {
        let hasSamples = (stats?.samples ?? 0) > 0
        return VStack(spacing: DesignTokens.Spacing.xs) {
            Text(title.uppercased())
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                .foregroundStyle(color)
                .tracking(0.5)

            if let stats, hasSamples, let avg = stats.avg {
                Text(String(format: "%.0fms", avg))
                    .font(DesignTokens.Typography.custom(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                HStack(spacing: DesignTokens.Spacing.xs) {
                    if let min = stats.min {
                        Text(String(format: "↓%.0f", min))
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    if let max = stats.max {
                        Text(String(format: "↑%.0f", max))
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    if let samples = stats.samples {
                        Text("n=\(samples)")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
            } else {
                Text("—")
                    .font(DesignTokens.Typography.bodySemibold)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func deltaCell(delta: DeltaStats) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text("DELTA")
                .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .tracking(0.5)

            if let current = delta.current {
                Text(String(format: "%+.0fms", current))
                    .font(DesignTokens.Typography.custom(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(current > 0 ? DesignTokens.Colors.accentOrange : DesignTokens.Colors.chzzkGreen)
            }
            if let avg = delta.avg {
                Text(String(format: "avg %+.0f", avg))
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    private func syncBadge(text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, 2)
            .background(DesignTokens.Colors.surfaceBase.opacity(0.6), in: Capsule())
    }

    private func syncActionColor(_ action: String?) -> Color {
        switch action {
        case "hold": return DesignTokens.Colors.chzzkGreen
        case "speed_up": return DesignTokens.Colors.accentOrange
        case "slow_down": return DesignTokens.Colors.accentBlue
        case "waiting": return DesignTokens.Colors.textTertiary
        default: return DesignTokens.Colors.textTertiary
        }
    }

    // MARK: - Section Container

    private func sectionContainer<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Rectangle()
                    .fill(DesignTokens.Glass.borderColor)
                    .frame(height: 0.5)
            }
            content()
        }
    }

    // MARK: - Helpers

    private func formatLargeNumber(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000.0) }
        if n >= 1_000  { return String(format: "%.1f천", Double(n) / 1_000.0) }
        return "\(n)"
    }

    private func cviewSyncLabel(_ summary: CViewStatsSummary) -> String {
        guard let channels = summary.syncChannels, !channels.isEmpty else {
            return "대기 중"
        }
        let actions = channels.compactMap { $0.recommendation?.action }
        if actions.allSatisfy({ $0 == "hold" }) { return "동기화 양호" }
        if actions.contains("speed_up") { return "가속 중" }
        if actions.contains("slow_down") { return "감속 중" }
        return "대기 중"
    }

    private func cviewActionIcon(_ action: String?) -> String {
        switch action {
        case "hold": return "checkmark.circle"
        case "speed_up": return "hare"
        case "slow_down": return "tortoise"
        case "waiting": return "hourglass"
        default: return "questionmark.circle"
        }
    }

    private func cviewActionLabel(_ action: String?) -> String {
        switch action {
        case "hold": return "동기화 양호"
        case "speed_up": return "가속 필요"
        case "slow_down": return "감속 필요"
        case "waiting": return "대기 중"
        default: return "알 수 없음"
        }
    }

    private func cviewAggregateSubtitle(_ summary: CViewStatsSummary) -> String {
        guard let agg = summary.aggregate else { return "" }
        let rate = agg.syncRate ?? 0
        let avg = agg.avgDeltaAbs ?? 0
        return String(format: "%.0f%% · %.0fms", rate, avg)
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "S": return DesignTokens.Colors.chzzkGreen
        case "A": return DesignTokens.Colors.accentCyan
        case "B": return DesignTokens.Colors.accentOrange
        case "C": return DesignTokens.Colors.accentOrange
        case "D": return .red
        default: return .gray
        }
    }
}
