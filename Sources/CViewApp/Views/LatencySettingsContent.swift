// MARK: - LatencySettingsContent.swift
// 레이턴시 설정 재사용 뷰 — 설정 탭, 싱글 라이브 패널, 멀티라이브 패널에서 공유

import SwiftUI
import CViewCore
import CViewPersistence

// MARK: - Compact (사이드 패널용)

/// 싱글 라이브 & 멀티라이브 설정 패널용 컴팩트 레이턴시 설정
struct LatencySettingsCompact: View {
    @Bindable var settings: SettingsStore
    var onApply: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // ── 프리셋 선택 ──
            presetGrid

            // ── 현재 프리셋 설명 ──
            presetDescription

            // ── 상세 파라미터 (커스텀 모드) ──
            if settings.player.currentPreset == .custom {
                detailParameters
            }

            // ── 기본 설정 복원 ──
            resetButton
        }
    }

    // MARK: - 프리셋 그리드

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("레이턴시 프리셋")
                .font(DesignTokens.Typography.custom(size: 13, weight: .bold))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: DesignTokens.Spacing.xs) {
                ForEach(PlayerSettings.LatencyPreset.allCases, id: \.self) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    private func presetButton(_ preset: PlayerSettings.LatencyPreset) -> some View {
        let isSelected = settings.player.currentPreset == preset
        return Button {
            settings.player.applyLatencyPreset(preset)
            onApply?()
            Task { await settings.save() }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: preset.icon)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                Text(preset.displayName)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isSelected
                          ? DesignTokens.Colors.chzzkGreen.opacity(0.15)
                          : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(isSelected
                                  ? DesignTokens.Colors.chzzkGreen
                                  : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 프리셋 설명

    private var presetDescription: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "info.circle")
                .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
            Text(settings.player.currentPreset.description)
                .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
        }
        .foregroundStyle(DesignTokens.Colors.textTertiary)
    }

    // MARK: - 상세 파라미터

    private var detailParameters: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Divider()

            Text("상세 파라미터")
                .font(DesignTokens.Typography.custom(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            latencySlider(label: "목표 지연", value: $settings.player.latencyTarget,
                          range: 0.5...15.0, step: 0.5, unit: "초", format: "%.1f")
            latencySlider(label: "최대 지연", value: $settings.player.latencyMax,
                          range: 3.0...30.0, step: 1.0, unit: "초", format: "%.0f")
            latencySlider(label: "최소 지연", value: $settings.player.latencyMin,
                          range: 0.0...5.0, step: 0.5, unit: "초", format: "%.1f")

            Divider()

            latencySlider(label: "최대 속도", value: $settings.player.latencyMaxRate,
                          range: 1.01...1.50, step: 0.01, unit: "x", format: "%.2f")
            latencySlider(label: "최소 속도", value: $settings.player.latencyMinRate,
                          range: 0.70...0.99, step: 0.01, unit: "x", format: "%.2f")
            latencySlider(label: "캐치업 임계", value: $settings.player.latencyCatchUpThreshold,
                          range: 0.1...3.0, step: 0.1, unit: "초", format: "%.1f")
            latencySlider(label: "슬로우다운 임계", value: $settings.player.latencySlowDownThreshold,
                          range: 0.1...2.0, step: 0.1, unit: "초", format: "%.1f")

            Divider()

            Text("PID 제어기")
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            latencySlider(label: "Kp (비례)", value: $settings.player.latencyPidKp,
                          range: 0.1...3.0, step: 0.1, unit: "", format: "%.1f")
            latencySlider(label: "Ki (적분)", value: $settings.player.latencyPidKi,
                          range: 0.0...1.0, step: 0.01, unit: "", format: "%.2f")
            latencySlider(label: "Kd (미분)", value: $settings.player.latencyPidKd,
                          range: 0.0...0.5, step: 0.01, unit: "", format: "%.2f")
        }
    }

    private func latencySlider(label: String, value: Binding<Double>,
                                range: ClosedRange<Double>, step: Double,
                                unit: String, format: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(DesignTokens.Colors.accentBlue)
                .onChange(of: value.wrappedValue) { _, _ in
                    settings.player.latencyPreset = PlayerSettings.LatencyPreset.custom.rawValue
                    onApply?()
                    Task { await settings.save() }
                }
            Text(String(format: "\(format)\(unit)", value.wrappedValue))
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - 기본 설정 복원

    private var resetButton: some View {
        Button {
            settings.player.applyLatencyPreset(.webSync)
            onApply?()
            Task { await settings.save() }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "arrow.counterclockwise")
                    .font(DesignTokens.Typography.caption)
                Text("기본 설정 복원")
                    .font(DesignTokens.Typography.captionMedium)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.gray.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full (설정 탭용)

/// 메인 설정 창의 PlayerSettingsTab용 레이턴시 섹션
struct LatencySettingsFull: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingsSection(title: "레이턴시 동기화", icon: "bolt.circle.fill", color: DesignTokens.Colors.accentBlue) {
            // ── 프리셋 선택 ──
            SettingsRow("동기화 프리셋",
                        description: "재생 지연 시간 프리셋을 선택합니다",
                        icon: "gauge.with.dots.needle.50percent",
                        iconColor: DesignTokens.Colors.accentBlue) {
                Picker("", selection: Binding(
                    get: { settings.player.currentPreset },
                    set: { settings.player.applyLatencyPreset($0); Task { await settings.save() } }
                )) {
                    ForEach(PlayerSettings.LatencyPreset.allCases, id: \.self) { preset in
                        Label(preset.displayName, systemImage: preset.icon).tag(preset)
                    }
                }
                .frame(width: 170)
                .labelsHidden()
            }
            RowDivider()

            // ── 프리셋 설명 ──
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: settings.player.currentPreset.icon)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                Text(settings.player.currentPreset.description)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.vertical, DesignTokens.Spacing.xs)

            // ── 핵심 슬라이더 (항상 표시) ──
            RowDivider()
            settingsSlider(label: "목표 지연", description: "이 시간만큼 방송보다 뒤에 재생됩니다",
                           icon: "target", value: $settings.player.latencyTarget,
                           range: 0.5...15.0, step: 0.5, format: "%.1f초")
            RowDivider()
            settingsSlider(label: "버퍼 한계", description: "지연이 이 값을 초과하면 캐치업을 시작합니다",
                           icon: "clock.fill", value: $settings.player.latencyMax,
                           range: 3.0...30.0, step: 1.0, format: "%.0f초")
            RowDivider()
            settingsSlider(label: "캐치업 속도", description: "지연 보정 시 최대 재생 속도",
                           icon: "forward.fill", value: $settings.player.latencyMaxRate,
                           range: 1.01...1.50, step: 0.01, format: "×%.2f")

            // ── 고급 파라미터 (커스텀 모드일 때) ──
            if settings.player.currentPreset == .custom {
                RowDivider()
                advancedSection
            }
        }
    }

    // MARK: - 고급 섹션

    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                Text("고급 파라미터")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
            }
            .foregroundStyle(DesignTokens.Colors.textTertiary)
            .padding(.top, DesignTokens.Spacing.xs)
        }
        RowDivider()
        settingsSlider(label: "최소 지연", description: "이 값 이하로는 재생 속도를 줄여 유지합니다",
                       icon: "minus.circle", value: $settings.player.latencyMin,
                       range: 0.0...5.0, step: 0.5, format: "%.1f초")
        RowDivider()
        settingsSlider(label: "최소 속도", description: "목표보다 빠른 재생 시 감속 하한",
                       icon: "tortoise.fill", value: $settings.player.latencyMinRate,
                       range: 0.70...0.99, step: 0.01, format: "×%.2f")
        RowDivider()
        settingsSlider(label: "캐치업 임계", description: "목표 대비 초과량이 이 값 이상이면 가속 시작",
                       icon: "arrow.up.right", value: $settings.player.latencyCatchUpThreshold,
                       range: 0.1...3.0, step: 0.1, format: "%.1f초")
        RowDivider()
        settingsSlider(label: "슬로우다운 임계", description: "목표 대비 부족량이 이 값 이상이면 감속 시작",
                       icon: "arrow.down.right", value: $settings.player.latencySlowDownThreshold,
                       range: 0.1...2.0, step: 0.1, format: "%.1f초")
        RowDivider()

        // PID
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "function")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                Text("PID 제어기 튜닝")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
            }
            .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        RowDivider()
        settingsSlider(label: "Kp (비례)", description: "오차에 대한 즉각 반응 강도",
                       icon: "chart.line.uptrend.xyaxis", value: $settings.player.latencyPidKp,
                       range: 0.1...3.0, step: 0.1, format: "%.1f")
        RowDivider()
        settingsSlider(label: "Ki (적분)", description: "누적 오차 보정 강도 (과하면 진동)",
                       icon: "sum", value: $settings.player.latencyPidKi,
                       range: 0.0...1.0, step: 0.01, format: "%.2f")
        RowDivider()
        settingsSlider(label: "Kd (미분)", description: "오차 변화율에 대한 제동 강도",
                       icon: "waveform.path.ecg", value: $settings.player.latencyPidKd,
                       range: 0.0...0.5, step: 0.01, format: "%.2f")
    }

    // MARK: - Helper

    private func settingsSlider(label: String, description: String, icon: String,
                                 value: Binding<Double>, range: ClosedRange<Double>,
                                 step: Double, format: String) -> some View {
        SettingsRow(label, description: description,
                    icon: icon, iconColor: DesignTokens.Colors.textSecondary) {
            HStack(spacing: 6) {
                Slider(value: value, in: range, step: step)
                    .frame(width: 110)
                    .tint(DesignTokens.Colors.accentBlue)
                    .onChange(of: value.wrappedValue) { _, _ in
                        settings.player.latencyPreset = PlayerSettings.LatencyPreset.custom.rawValue
                        Task { await settings.save() }
                    }
                Text(String(format: format, value.wrappedValue))
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
}
