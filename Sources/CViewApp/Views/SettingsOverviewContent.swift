// MARK: - SettingsOverviewContent.swift
// CView 설정 메뉴 — 개요(Overview) 그룹 콘텐츠 (Redesign 2026-04-29)
//
// 구성:
//   1. Status Strip — 테마/엔진/네트워크 프리셋/메트릭 상태 한눈에
//   2. Quick Controls — 자주 쓰는 8개 토글/픽커
//   3. Scenario Presets — 시나리오 카드(일반/저지연/멀티/채팅/디버깅)
//   4. Recent Changes — 최근 변경 내역
//   5. Maintenance — 캐시·초기화·App Secret 진입
//
// 시나리오 적용은 SettingsScenario.apply(to:) 가 SettingsStore를 직접 변경하고,
// 워크스페이스가 적용 전 스냅샷을 보관해 1단계 rollback을 제공한다.

import SwiftUI
import CViewCore
import CViewPersistence

struct SettingsOverviewContent: View {
    @Bindable var settings: SettingsStore
    let recentChanges: SettingsRecentChangesTracker
    let changedOnly: Bool
    let onSelectGroup: (AppRouter.SettingsGroup) -> Void
    let onApplyScenario: (SettingsScenario) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                SettingsPageHeader(
                    "개요",
                    subtitle: "현재 상태와 자주 쓰는 설정을 한곳에서 빠르게 조정하세요"
                )

                // 1. Status Strip
                SettingsStatusStrip(settings: settings, onJump: onSelectGroup)

                // 2. Quick Controls
                SettingsQuickControls(settings: settings)

                // 3. Scenario Presets
                SettingsScenarioGallery(
                    settings: settings,
                    onApply: onApplyScenario
                )

                // 4. Recent Changes
                SettingsRecentChangesPanel(tracker: recentChanges, onJump: onSelectGroup)

                // 5. 변경됨만 보기 활성화 시 — diff 요약
                if changedOnly {
                    SettingsChangedOverview(settings: settings, onJump: onSelectGroup)
                }

                // 6. Maintenance shortcut
                SettingsMaintenanceShortcut(onJump: onSelectGroup)
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }
}

// MARK: - Status Strip

private struct SettingsStatusStrip: View {
    @Bindable var settings: SettingsStore
    let onJump: (AppRouter.SettingsGroup) -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            statusPill(
                icon: themeIcon,
                title: "테마",
                value: settings.appearance.theme.displayName,
                color: DesignTokens.Colors.accentPurple,
                action: { onJump(.overview) }
            )
            statusPill(
                icon: "cpu",
                title: "엔진",
                value: settings.player.preferredEngine.displayName,
                color: DesignTokens.Colors.chzzkGreen,
                action: { onJump(.viewing) }
            )
            statusPill(
                icon: "network",
                title: "네트워크",
                value: settings.network.matchingPreset().displayName,
                color: DesignTokens.Colors.accentBlue,
                action: { onJump(.integration) }
            )
            statusPill(
                icon: "antenna.radiowaves.left.and.right",
                title: "메트릭",
                value: settings.metrics.metricsEnabled ? "전송 ON" : "OFF",
                color: settings.metrics.metricsEnabled ? DesignTokens.Colors.live : DesignTokens.Colors.textTertiary,
                action: { onJump(.integration) }
            )
            statusPill(
                icon: "rectangle.split.2x2.fill",
                title: "멀티",
                value: "최대 \(settings.multiLive.maxConcurrentSessions)개",
                color: DesignTokens.Colors.accentBlue,
                action: { onJump(.multi) }
            )
        }
    }

    private var themeIcon: String {
        switch settings.appearance.theme {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    @ViewBuilder
    private func statusPill(icon: String, title: String, value: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DesignTokens.Typography.custom(size: 10))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text(value)
                        .font(DesignTokens.Typography.custom(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(DesignTokens.Glass.thin, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Controls

private struct SettingsQuickControls: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingsSection(title: "자주 쓰는 설정", icon: "bolt.fill", color: DesignTokens.Colors.chzzkGreen) {
            SettingsRow("테마",
                        icon: "paintpalette.fill",
                        iconColor: DesignTokens.Colors.accentPurple) {
                Picker("", selection: $settings.appearance.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .frame(width: 130)
                .labelsHidden()
            }
            RowDivider()
            SettingsRow("재생 엔진",
                        icon: "cpu",
                        iconColor: DesignTokens.Colors.chzzkGreen) {
                Picker("", selection: $settings.player.preferredEngine) {
                    ForEach(PlayerEngineType.allCases, id: \.self) { e in
                        Text(e.displayName).tag(e)
                    }
                }
                .frame(width: 130)
                .labelsHidden()
            }
            RowDivider()
            SettingsRow("기본 화질",
                        icon: "4k.tv.fill",
                        iconColor: DesignTokens.Colors.chzzkGreen) {
                Picker("", selection: $settings.player.quality) {
                    ForEach(StreamQuality.allCases, id: \.self) { q in
                        Text(q.displayName).tag(q)
                    }
                }
                .frame(width: 130)
                .labelsHidden()
            }
            RowDivider()
            SettingsRow("자동 재생",
                        icon: "play.fill",
                        iconColor: DesignTokens.Colors.chzzkGreen) {
                Toggle("", isOn: $settings.player.autoPlay)
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.chzzkGreen)
                    .labelsHidden()
            }
            RowDivider()
            SettingsRow("백그라운드 재생",
                        icon: "play.slash.fill",
                        iconColor: DesignTokens.Colors.accentPurple) {
                Toggle("", isOn: $settings.player.continuePlaybackInBackground)
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.accentPurple)
                    .labelsHidden()
            }
            RowDivider()
            SettingsRow("알림",
                        icon: "bell.badge.fill",
                        iconColor: DesignTokens.Colors.accentOrange) {
                Toggle("", isOn: $settings.general.notificationsEnabled)
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.accentOrange)
                    .labelsHidden()
            }
            RowDivider()
            SettingsRow("멀티 동시 세션",
                        icon: "number.square.fill",
                        iconColor: DesignTokens.Colors.accentBlue) {
                Stepper(value: $settings.multiLive.maxConcurrentSessions, in: 2...6) {
                    Text("\(settings.multiLive.maxConcurrentSessions)개")
                        .font(DesignTokens.Typography.custom(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            RowDivider()
            SettingsRow("메트릭 전송",
                        description: settings.metrics.metricsEnabled
                            ? "서버로 사용 통계 전송 중"
                            : "전송 꺼짐 — 로컬에서만 수집",
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: settings.metrics.metricsEnabled ? DesignTokens.Colors.live : DesignTokens.Colors.textTertiary) {
                Toggle("", isOn: $settings.metrics.metricsEnabled)
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.live)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Scenario Gallery

private struct SettingsScenarioGallery: View {
    @Bindable var settings: SettingsStore
    let onApply: (SettingsScenario) -> Void

    @State private var previewScenario: SettingsScenario?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accentPurple)
                Text("시나리오 프리셋")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("적용 전 변경 항목을 확인할 수 있어요")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 220, maximum: 320), spacing: DesignTokens.Spacing.md)
            ], alignment: .leading, spacing: DesignTokens.Spacing.md) {
                ForEach(SettingsScenario.all) { scenario in
                    scenarioCard(scenario)
                }
            }
        }
        .sheet(item: $previewScenario) { scenario in
            SettingsScenarioPreviewSheet(
                scenario: scenario,
                settings: settings,
                onApply: {
                    previewScenario = nil
                    onApply(scenario)
                },
                onCancel: { previewScenario = nil }
            )
        }
    }

    @ViewBuilder
    private func scenarioCard(_ scenario: SettingsScenario) -> some View {
        Button { previewScenario = scenario } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: scenario.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(scenario.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(scenario.title)
                        .font(DesignTokens.Typography.bodySemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                }
                Text(scenario.summary)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    ForEach(scenario.touchedGroups, id: \.self) { g in
                        Text(g.rawValue)
                            .font(DesignTokens.Typography.custom(size: 9, weight: .semibold))
                            .foregroundStyle(g.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(g.color.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    Text("미리보기 →")
                        .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                        .foregroundStyle(scenario.color)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Glass.thin, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scenario Preview Sheet (diff)

private struct SettingsScenarioPreviewSheet: View {
    let scenario: SettingsScenario
    @Bindable var settings: SettingsStore
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: scenario.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(scenario.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.title)
                        .font(DesignTokens.Typography.bodySemibold)
                    Text(scenario.summary)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(DesignTokens.Spacing.lg)

            Divider()

            // Diff list
            let diff = scenario.diff(against: settings)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if diff.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            Text("이 시나리오의 모든 항목이 이미 적용되어 있습니다")
                                .font(DesignTokens.Typography.body)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                    } else {
                        Text("바뀔 항목 \(diff.count)개")
                            .font(DesignTokens.Typography.captionSemibold)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                            .padding(.bottom, 4)
                        ForEach(diff, id: \.label) { change in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(scenario.color)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(change.label)
                                        .font(DesignTokens.Typography.captionSemibold)
                                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(change.from)
                                            .font(DesignTokens.Typography.custom(size: 11, design: .monospaced))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                            .strikethrough()
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                        Text(change.to)
                                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(scenario.color)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(scenario.color.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                }
                .padding(DesignTokens.Spacing.lg)
            }
            .frame(minHeight: 220, maxHeight: 360)

            Divider()

            // Footer
            HStack {
                Text("적용 후에도 상단 '되돌리기'로 한 번 되돌릴 수 있습니다")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(action: onApply) {
                    Text(diff.isEmpty ? "확인" : "적용")
                        .frame(minWidth: 60)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(false)
                .buttonStyle(.borderedProminent)
                .tint(scenario.color)
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .frame(width: 540)
    }
}

// MARK: - Recent Changes Panel

private struct SettingsRecentChangesPanel: View {
    let tracker: SettingsRecentChangesTracker
    let onJump: (AppRouter.SettingsGroup) -> Void

    var body: some View {
        if !tracker.entries.isEmpty {
            SettingsSection(title: "최근 변경", icon: "clock.arrow.circlepath", color: DesignTokens.Colors.accentBlue) {
                ForEach(Array(tracker.entries.prefix(6).enumerated()), id: \.element.id) { idx, entry in
                    if idx > 0 { RowDivider() }
                    Button {
                        if let g = AppRouter.SettingsGroup(rawValue: entry.groupId) {
                            onJump(g)
                        }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: entry.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.accentBlue)
                                .frame(width: 26, height: 26)
                                .background(DesignTokens.Colors.accentBlue.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.label)
                                    .font(DesignTokens.Typography.body)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Text(entry.summary)
                                    .font(DesignTokens.Typography.footnote)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Spacer()
                            Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                                .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Changed Overview (변경됨만 보기 활성화 시)

private struct SettingsChangedOverview: View {
    @Bindable var settings: SettingsStore
    let onJump: (AppRouter.SettingsGroup) -> Void

    var body: some View {
        SettingsSection(title: "기본값과 다른 설정", icon: "circle.lefthalf.filled", color: DesignTokens.Colors.accentOrange) {
            let changed = SettingsDefaultDiff.compute(settings: settings)
            if changed.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                    Text("모든 설정이 기본값입니다")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.md)
            } else {
                ForEach(Array(changed.enumerated()), id: \.element.id) { idx, group in
                    if idx > 0 { RowDivider() }
                    Button { onJump(group.group) } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: group.group.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(group.group.color)
                                .frame(width: 26, height: 26)
                                .background(group.group.color.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.group.rawValue)
                                    .font(DesignTokens.Typography.body)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Text(group.summary)
                                    .font(DesignTokens.Typography.footnote)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Spacer()
                            Text("\(group.count)개")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(group.group.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(group.group.color.opacity(0.12), in: Capsule())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Maintenance Shortcut

private struct SettingsMaintenanceShortcut: View {
    let onJump: (AppRouter.SettingsGroup) -> Void

    var body: some View {
        SettingsSection(title: "유지보수", icon: "wrench.and.screwdriver.fill", color: DesignTokens.Colors.live) {
            Button { onJump(.advanced) } label: {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.live)
                        .frame(width: 26, height: 26)
                        .background(DesignTokens.Colors.live.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("캐시 정리 / 전체 초기화")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Text("고급 그룹의 캐시 & 초기화 섹션으로 이동")
                            .font(DesignTokens.Typography.footnote)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RowDivider()
            Button { onJump(.integration) } label: {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.accentPurple)
                        .frame(width: 26, height: 26)
                        .background(DesignTokens.Colors.accentPurple.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Secret / 메트릭 인증")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Text("연동 그룹 → 메트릭 → App Secret")
                            .font(DesignTokens.Typography.footnote)
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 기본값 비교 (간이 — 도메인별 dirty 카운트)

@MainActor
enum SettingsDefaultDiff {
    struct Result: Identifiable {
        let id: String
        let group: AppRouter.SettingsGroup
        let count: Int
        let summary: String
    }

    static func compute(settings: SettingsStore) -> [Result] {
        var out: [Result] = []

        // overview: general + appearance(theme/notification 부분)
        let generalDiff = settings.general != .default ? 1 : 0
        let appearanceMinor = settings.appearance != .default ? 1 : 0
        if generalDiff + appearanceMinor > 0 {
            out.append(.init(id: "overview",
                             group: .overview,
                             count: generalDiff + appearanceMinor,
                             summary: "일반/테마 설정 변경됨"))
        }

        if settings.player != .default {
            out.append(.init(id: "viewing", group: .viewing, count: 1, summary: "플레이어/레이턴시 설정 변경됨"))
        }
        if settings.chat != .default || settings.multiChat != .default {
            out.append(.init(id: "chat", group: .chat, count: 1, summary: "채팅 설정 변경됨"))
        }
        if settings.multiLive != .default {
            out.append(.init(id: "multi", group: .multi, count: 1, summary: "멀티라이브 설정 변경됨"))
        }
        if settings.network != .default || settings.metrics != .default {
            out.append(.init(id: "integration", group: .integration, count: 1, summary: "네트워크/메트릭 변경됨"))
        }
        if settings.keyboard != .default {
            out.append(.init(id: "advanced", group: .advanced, count: 1, summary: "단축키 설정 변경됨"))
        }
        return out
    }
}

// MARK: - Settings Scenario (시나리오 정의)

struct SettingsScenario: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let icon: String
    let color: Color
    let touchedGroups: [AppRouter.SettingsGroup]

    /// 적용 시 SettingsStore 변경 (closure 보관 위해 함수 포인터 대신 enum dispatch 사용)
    private let kind: Kind

    enum Kind: String {
        case generalViewing, lowLatency, multiStable, chatFocus, debugMetrics
    }

    static func == (lhs: SettingsScenario, rhs: SettingsScenario) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    @MainActor
    func apply(to settings: SettingsStore) {
        Self.changes(for: kind).forEach { $0.applyClosure(settings) }
    }

    @MainActor
    func diff(against settings: SettingsStore) -> [DiffEntry] {
        Self.changes(for: kind).compactMap { $0.diff(settings) }
    }

    struct DiffEntry {
        let label: String
        let from: String
        let to: String
    }

    private struct Change {
        let label: String
        let describeFrom: @MainActor (SettingsStore) -> String
        let describeTo: () -> String
        let isApplied: @MainActor (SettingsStore) -> Bool
        let applyClosure: @MainActor (SettingsStore) -> Void

        @MainActor
        func diff(_ settings: SettingsStore) -> DiffEntry? {
            guard !isApplied(settings) else { return nil }
            return DiffEntry(label: label, from: describeFrom(settings), to: describeTo())
        }
    }

    nonisolated(unsafe) static let all: [SettingsScenario] = [
        .init(id: "general",
              title: "일반 시청",
              summary: "안정적이고 균형 잡힌 기본 설정. 처음 사용자에게 권장합니다.",
              icon: "play.circle.fill",
              color: DesignTokens.Colors.chzzkGreen,
              touchedGroups: [.viewing, .integration],
              kind: .generalViewing),
        .init(id: "lowLatency",
              title: "저지연 동기화",
              summary: "웹 브라우저와 비슷한 위치 유지. 캐치업·짧은 버퍼·빠른 재시도.",
              icon: "bolt.fill",
              color: DesignTokens.Colors.accentBlue,
              touchedGroups: [.viewing, .integration],
              kind: .lowLatency),
        .init(id: "multiStable",
              title: "멀티라이브 안정",
              summary: "여러 채널 동시 재생을 안정적으로. 프로세스 분리·대역폭 조정 활성화.",
              icon: "rectangle.split.3x1.fill",
              color: DesignTokens.Colors.accentPurple,
              touchedGroups: [.multi, .viewing],
              kind: .multiStable),
        .init(id: "chatFocus",
              title: "채팅 집중",
              summary: "채팅 가독성·필터·TTS를 최적화. 멀티채팅 너비 확대.",
              icon: "bubble.left.and.bubble.right.fill",
              color: DesignTokens.Colors.accentOrange,
              touchedGroups: [.chat],
              kind: .chatFocus),
        .init(id: "debug",
              title: "디버깅 / 메트릭",
              summary: "디버그 모드·메트릭 수집·상세 로그를 켭니다. 개발/문제진단용.",
              icon: "ant.fill",
              color: DesignTokens.Colors.live,
              touchedGroups: [.advanced, .integration],
              kind: .debugMetrics),
    ]

    private static func changes(for kind: Kind) -> [Change] {
        switch kind {
        case .generalViewing:
            return [
                Change(
                    label: "기본 화질",
                    describeFrom: { $0.player.quality.displayName },
                    describeTo: { StreamQuality.auto.displayName },
                    isApplied: { $0.player.quality == .auto },
                    applyClosure: { $0.player.quality = .auto }
                ),
                Change(
                    label: "항상 최고 화질 유지",
                    describeFrom: { $0.player.forceHighestQuality ? "켜짐" : "꺼짐" },
                    describeTo: { "꺼짐" },
                    isApplied: { !$0.player.forceHighestQuality },
                    applyClosure: { $0.player.forceHighestQuality = false }
                ),
                Change(
                    label: "레이턴시 프리셋",
                    describeFrom: { $0.player.latencyPreset },
                    describeTo: { "default" },
                    isApplied: { $0.player.latencyPreset == "default" },
                    applyClosure: { $0.player.latencyPreset = "default" }
                ),
                Change(
                    label: "네트워크 프리셋",
                    describeFrom: { $0.network.matchingPreset().displayName },
                    describeTo: { NetworkPreset.balanced.displayName },
                    isApplied: { $0.network.matchingPreset() == .balanced },
                    applyClosure: { $0.network = NetworkPreset.balanced.settings }
                ),
            ]
        case .lowLatency:
            return [
                Change(
                    label: "레이턴시 프리셋",
                    describeFrom: { $0.player.latencyPreset },
                    describeTo: { "webSync" },
                    isApplied: { $0.player.latencyPreset == "webSync" },
                    applyClosure: { s in
                        s.player.latencyPreset = "webSync"
                        s.player.latencyTarget = 6.0
                        s.player.latencyMax = 12.0
                        s.player.latencyMin = 3.0
                    }
                ),
                Change(
                    label: "스트림 보정 모드",
                    describeFrom: { $0.player.streamProxyMode.displayName },
                    describeTo: { StreamProxyMode.localProxy.displayName },
                    isApplied: { $0.player.streamProxyMode == .localProxy },
                    applyClosure: { $0.player.streamProxyMode = .localProxy }
                ),
                Change(
                    label: "버퍼 시간",
                    describeFrom: { String(format: "%.1fs", $0.player.bufferDuration) },
                    describeTo: { "1.5s" },
                    isApplied: { abs($0.player.bufferDuration - 1.5) < 0.01 },
                    applyClosure: { $0.player.bufferDuration = 1.5 }
                ),
                Change(
                    label: "네트워크 프리셋",
                    describeFrom: { $0.network.matchingPreset().displayName },
                    describeTo: { NetworkPreset.lowLatency.displayName },
                    isApplied: { $0.network.matchingPreset() == .lowLatency },
                    applyClosure: { $0.network = NetworkPreset.lowLatency.settings }
                ),
            ]
        case .multiStable:
            return [
                Change(
                    label: "최대 동시 세션",
                    describeFrom: { "\($0.multiLive.maxConcurrentSessions)개" },
                    describeTo: { "4개" },
                    isApplied: { $0.multiLive.maxConcurrentSessions == 4 },
                    applyClosure: { $0.multiLive.maxConcurrentSessions = 4 }
                ),
                Change(
                    label: "프로세스 분리 모드",
                    describeFrom: { $0.multiLive.useSeparateProcesses ? "켜짐" : "꺼짐" },
                    describeTo: { "켜짐" },
                    isApplied: { $0.multiLive.useSeparateProcesses },
                    applyClosure: { $0.multiLive.useSeparateProcesses = true }
                ),
                Change(
                    label: "대역폭 조정",
                    describeFrom: { $0.multiLive.bandwidthCoordinationEnabled ? "켜짐" : "꺼짐" },
                    describeTo: { "켜짐" },
                    isApplied: { $0.multiLive.bandwidthCoordinationEnabled },
                    applyClosure: { $0.multiLive.bandwidthCoordinationEnabled = true }
                ),
                Change(
                    label: "백그라운드 화질 자동 하향",
                    describeFrom: { $0.multiLive.backgroundQualityReduction ? "켜짐" : "꺼짐" },
                    describeTo: { "켜짐" },
                    isApplied: { $0.multiLive.backgroundQualityReduction },
                    applyClosure: { $0.multiLive.backgroundQualityReduction = true }
                ),
                Change(
                    label: "항상 최고 화질 유지",
                    describeFrom: { $0.player.forceHighestQuality ? "켜짐" : "꺼짐" },
                    describeTo: { "꺼짐" },
                    isApplied: { !$0.player.forceHighestQuality },
                    applyClosure: { $0.player.forceHighestQuality = false }
                ),
            ]
        case .chatFocus:
            return [
                Change(
                    label: "멀티채팅 패널 너비 비율",
                    describeFrom: { String(format: "%d%%", Int($0.multiChat.panelWidthRatio * 100)) },
                    describeTo: { "32%" },
                    isApplied: { abs($0.multiChat.panelWidthRatio - 0.32) < 0.005 },
                    applyClosure: { $0.multiChat.panelWidthRatio = 0.32 }
                ),
                Change(
                    label: "채팅 자동 스크롤",
                    describeFrom: { $0.chat.autoScroll ? "켜짐" : "꺼짐" },
                    describeTo: { "켜짐" },
                    isApplied: { $0.chat.autoScroll },
                    applyClosure: { $0.chat.autoScroll = true }
                ),
            ]
        case .debugMetrics:
            return [
                Change(
                    label: "디버그 모드",
                    describeFrom: { $0.appearance.debugMode ? "켜짐" : "꺼짐" },
                    describeTo: { "켜짐" },
                    isApplied: { $0.appearance.debugMode },
                    applyClosure: { $0.appearance.debugMode = true }
                ),
                Change(
                    label: "메트릭 전송",
                    describeFrom: { $0.metrics.metricsEnabled ? "켜짐" : "꺼짐" },
                    describeTo: { "켜짐" },
                    isApplied: { $0.metrics.metricsEnabled },
                    applyClosure: { $0.metrics.metricsEnabled = true }
                ),
            ]
        }
    }
}

// MARK: - Snapshot for Rollback

@MainActor
struct SettingsScenarioSnapshot {
    let player: PlayerSettings
    let chat: ChatSettings
    let general: GeneralSettings
    let appearance: AppearanceSettings
    let network: NetworkSettings
    let metrics: MetricsSettings
    let multiLive: MultiLiveSettings
    let multiChat: MultiChatSettings

    init(from settings: SettingsStore) {
        self.player = settings.player
        self.chat = settings.chat
        self.general = settings.general
        self.appearance = settings.appearance
        self.network = settings.network
        self.metrics = settings.metrics
        self.multiLive = settings.multiLive
        self.multiChat = settings.multiChat
    }

    func restore(to settings: SettingsStore) {
        settings.player = player
        settings.chat = chat
        settings.general = general
        settings.appearance = appearance
        settings.network = network
        settings.metrics = metrics
        settings.multiLive = multiLive
        settings.multiChat = multiChat
    }
}
