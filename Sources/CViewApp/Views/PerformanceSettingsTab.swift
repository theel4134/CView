// MARK: - PerformanceSettingsTab.swift
// 성능 설정 탭 (SettingsView에서 추출)

import SwiftUI
import CViewCore
import CViewPersistence

struct PerformanceSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var showResetAlert = false
    @State private var showCacheAlert = false
    @State private var cacheSize: String = "계산 중..."

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                SettingsPageHeader("성능")

                SettingsSection(title: "하드웨어 & 메모리", icon: "cpu.fill", color: DesignTokens.Colors.accentOrange) {
                    SettingsRow("하드웨어 디코딩",
                                description: "GPU 가속을 사용해 CPU 부하를 줄입니다",
                                icon: "memorychip", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.appearance.hardwareDecoding)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("메모리 제한",
                                description: "초과 시 이미지 캐시를 자동으로 정리합니다",
                                icon: "memorychip.fill", iconColor: DesignTokens.Colors.textSecondary) {
                        Picker("", selection: $settings.appearance.maxMemoryMB) {
                            Text("256 MB").tag(256)
                            Text("512 MB").tag(512)
                            Text("1 GB").tag(1024)
                            Text("2 GB").tag(2048)
                        }
                        .frame(width: 130)
                        .labelsHidden()
                    }
                }

                SettingsSection(title: "외관", icon: "paintbrush.fill", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("콤팩트 모드",
                                description: "UI 요소 간격을 줄여 더 많은 정보를 표시합니다",
                                icon: "rectangle.compress.vertical", iconColor: DesignTokens.Colors.accentPurple) {
                        Toggle("", isOn: $settings.appearance.compactMode)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentPurple).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("사이드바 너비", icon: "sidebar.left", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.appearance.sidebarWidth, in: 180...400, step: 10)
                                .frame(width: 110)
                                .tint(DesignTokens.Colors.accentPurple)
                            Text("\(Int(settings.appearance.sidebarWidth))px")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 46)
                        }
                    }
                }

                SettingsSection(title: "개발자", icon: "hammer.fill", color: DesignTokens.Colors.textSecondary) {
                    SettingsRow("디버그 모드",
                                description: "상세 로그 및 디버그 정보를 활성화합니다",
                                icon: "ant.fill", iconColor: DesignTokens.Colors.textSecondary) {
                        Toggle("", isOn: $settings.appearance.debugMode)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
                    }
                    if settings.appearance.debugMode {
                        SettingsSectionFooter(text: "활성화 시 성능 오버레이, 네트워크 로그 등 개발 정보가 표시됩니다.")
                    }
                }

                SettingsSection(title: "캐시 & 초기화", icon: "trash.fill", color: DesignTokens.Colors.live) {
                    // 캐시 크기 표시
                    SettingsRow("현재 캐시 크기",
                                icon: "internaldrive", iconColor: DesignTokens.Colors.textSecondary) {
                        Text(cacheSize)
                            .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    RowDivider()
                    Button {
                        URLCache.shared.removeAllCachedResponses()
                        if let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                            try? FileManager.default.removeItem(at: dir.appendingPathComponent("image_cache"))
                        }
                        showCacheAlert = true
                        cacheSize = "0 MB"
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.accentOrange)
                                .frame(width: 26, height: 26)
                                .background(DesignTokens.Colors.accentOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text("캐시 전체 삭제")
                                .font(DesignTokens.Typography.body)
                                .foregroundStyle(DesignTokens.Colors.accentOrange)
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                    Button(role: .destructive) {
                        Task {
                            await settings.resetAll()
                            showResetAlert = true
                        }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.live)
                                .frame(width: 26, height: 26)
                                .background(DesignTokens.Colors.live.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("모든 설정 초기화")
                                    .font(DesignTokens.Typography.body)
                                    .foregroundStyle(DesignTokens.Colors.live)
                                Text("되돌릴 수 없습니다")
                                    .font(DesignTokens.Typography.footnote)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .onAppear { cacheSize = measureCacheSize() }
        .onChange(of: settings.appearance) { _, _ in Task { await settings.save() } }
        .alert("설정 초기화 완료", isPresented: $showResetAlert) {
            Button("확인", role: .cancel) {}
        } message: { Text("모든 설정이 기본값으로 초기화되었습니다.") }
        .alert("캐시 삭제 완료", isPresented: $showCacheAlert) {
            Button("확인", role: .cancel) {}
        } message: { Text("URL 캐시 및 이미지 캐시가 삭제되었습니다.") }
    }

    private func measureCacheSize() -> String {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let dir = base else { return "알 수 없음" }
        let total = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)
            .compactMap { try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent($0).path)[.size] as? Int }
            .reduce(0, +)) ?? 0
        let mb = Double(total) / 1_048_576
        return mb < 1 ? String(format: "%.0f KB", mb * 1024) : String(format: "%.1f MB", mb)
    }
}
