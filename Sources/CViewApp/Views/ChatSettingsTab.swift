// MARK: - ChatSettingsTab.swift
// 채팅 설정 탭 (SettingsView에서 추출)

import SwiftUI
import CViewCore
import CViewPersistence

struct ChatSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var showBlockedUsers = false
    @State private var newKeyword = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {

                // ── 표시 설정 ──────────────────────────────────────
                SettingsSection(title: "표시 설정", icon: "textformat.size", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("글꼴 크기", icon: "textformat", iconColor: DesignTokens.Colors.accentPurple) {
                        HStack(spacing: 6) {
                            Text("가").font(DesignTokens.Typography.custom(size: 10, weight: .regular)).foregroundStyle(DesignTokens.Colors.textTertiary)
                            Slider(value: $settings.chat.fontSize, in: 10...24, step: 1)
                                .frame(width: 100)
                                .tint(DesignTokens.Colors.accentPurple)
                            Text("가").font(DesignTokens.Typography.custom(size: 16)).foregroundStyle(DesignTokens.Colors.textTertiary)
                            Text("\(Int(settings.chat.fontSize))pt")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentPurple)
                                .frame(width: 34)
                        }
                    }
                    RowDivider()
                    SettingsRow("투명도", icon: "circle.lefthalf.filled", iconColor: .gray) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.chat.chatOpacity, in: 0.3...1.0, step: 0.05)
                                .frame(width: 100)
                                .tint(DesignTokens.Colors.accentPurple)
                            Text("\(Int(settings.chat.chatOpacity * 100))%")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentPurple)
                                .frame(width: 34)
                        }
                    }
                    RowDivider()
                    SettingsRow("줄 간격", icon: "arrow.up.and.down.text.horizontal",
                                iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            Slider(value: $settings.chat.lineSpacing, in: 0...8, step: 1)
                                .frame(width: 100)
                                .tint(DesignTokens.Colors.accentPurple)
                            Text(String(format: "%.0fpt", settings.chat.lineSpacing))
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentPurple)
                                .frame(width: 38)
                        }
                    }
                    RowDivider()
                    SettingsRow("타임스탬프 표시",
                                icon: "clock", iconColor: DesignTokens.Colors.textSecondary) {
                        Toggle("", isOn: $settings.chat.showTimestamp)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentPurple).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("뱃지 표시",
                                icon: "shield.fill", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.chat.showBadge)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("멘션 강조",
                                description: "내 닉네임 언급 시 하이라이트",
                                icon: "at", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.chat.highlightMentions)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
                    }
                }

                // ── 콘텐츠 설정 ────────────────────────────────────
                SettingsSection(title: "콘텐츠", icon: "sparkles", color: DesignTokens.Colors.accentOrange) {
                    SettingsRow("이모티콘 표시",
                                icon: "face.smiling", iconColor: DesignTokens.Colors.accentOrange) {
                        Toggle("", isOn: $settings.chat.emoticonEnabled)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("도네이션 표시",
                                icon: "heart.fill", iconColor: DesignTokens.Colors.live) {
                        Toggle("", isOn: $settings.chat.showDonation)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.live).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("도네이션만 표시",
                                description: "일반 채팅 숨기고 도네이션만 표시",
                                icon: "line.3.horizontal.decrease.circle", iconColor: DesignTokens.Colors.live) {
                        Toggle("", isOn: $settings.chat.showDonationsOnly)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.live).labelsHidden()
                    }
                }

                // ── TTS (음성 읽기) ────────────────────────────────
                SettingsSection(title: "TTS (음성 읽기)", icon: "speaker.wave.2.fill", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("후원/구독 TTS",
                                description: "후원 및 구독 메시지를 음성으로 읽어줍니다",
                                icon: "speaker.wave.2.fill", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.chat.ttsEnabled)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
                    }
                    if settings.chat.ttsEnabled {
                        RowDivider()
                        SettingsRow("음량", icon: "speaker.fill", iconColor: DesignTokens.Colors.accentBlue) {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.fill")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                Slider(value: $settings.chat.ttsVolume, in: 0.0...1.0, step: 0.05)
                                    .frame(width: 100)
                                    .tint(DesignTokens.Colors.accentBlue)
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                                Text("\(Int(settings.chat.ttsVolume * 100))%")
                                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                                    .frame(width: 34)
                            }
                        }
                        RowDivider()
                        SettingsRow("읽기 속도", icon: "gauge.with.dots.needle.33percent",
                                    iconColor: DesignTokens.Colors.accentBlue) {
                            HStack(spacing: 6) {
                                Text("느림").font(DesignTokens.Typography.custom(size: 10, weight: .regular)).foregroundStyle(DesignTokens.Colors.textTertiary)
                                Slider(value: $settings.chat.ttsRate, in: 100...400, step: 10)
                                    .frame(width: 100)
                                    .tint(DesignTokens.Colors.accentBlue)
                                Text("빠름").font(DesignTokens.Typography.custom(size: 10, weight: .regular)).foregroundStyle(DesignTokens.Colors.textTertiary)
                                Text("\(Int(settings.chat.ttsRate))")
                                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.accentBlue)
                                    .frame(width: 30)
                            }
                        }
                    }
                }

                // ── 필터 설정 ──────────────────────────────────────
                SettingsSection(title: "필터 & 스크롤", icon: "line.3.horizontal.decrease.circle.fill",
                                color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("자동 스크롤",
                                icon: "arrow.down.to.line", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.chat.autoScroll)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("채팅 필터 활성화",
                                description: "차단 키워드가 포함된 메시지를 숨깁니다",
                                icon: "line.3.horizontal.decrease.circle", iconColor: DesignTokens.Colors.accentBlue) {
                        Toggle("", isOn: $settings.chat.chatFilterEnabled)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
                    }
                    RowDivider()
                    SettingsRow("최대 메시지 수",
                                description: "초과 시 오래된 메시지부터 제거",
                                icon: "list.bullet", iconColor: DesignTokens.Colors.textSecondary) {
                        HStack(spacing: 6) {
                            TextField("", value: $settings.chat.maxVisibleMessages, format: .number)
                                .frame(width: 64)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                            Text("개")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }

                    // 차단 키워드 입력
                    if settings.chat.chatFilterEnabled {
                        RowDivider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("차단 키워드")
                                .font(DesignTokens.Typography.captionSemibold)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .padding(.horizontal, DesignTokens.Spacing.md)
                                .padding(.top, DesignTokens.Spacing.xs)

                            if !settings.chat.blockedWords.isEmpty {
                                SettingsFlowTagView(tags: settings.chat.blockedWords) { kw in
                                    settings.chat.blockedWords.removeAll { $0 == kw }
                                    Task { await settings.save() }
                                }
                                .padding(.horizontal, DesignTokens.Spacing.md)
                            }

                            HStack(spacing: 6) {
                                TextField("키워드 입력 후 +", text: $newKeyword)
                                    .textFieldStyle(.roundedBorder)
                                    .font(DesignTokens.Typography.caption)
                                    .onSubmit { addKeyword() }
                                Button { addKeyword() } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                                        .font(DesignTokens.Typography.subhead)
                                }
                                .buttonStyle(.plain)
                                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.bottom, DesignTokens.Spacing.xs)
                        }
                    }
                }

                // ── 사용자 관리 ────────────────────────────────────
                SettingsSection(title: "사용자 관리", icon: "person.2.fill", color: DesignTokens.Colors.live) {
                    Button {
                        showBlockedUsers = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.raised.fill")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.live)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("차단된 사용자 관리")
                                    .font(DesignTokens.Typography.captionMedium)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Text("\(settings.chat.blockedUsers.count)명 차단됨")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.md)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: settings.chat) { _, _ in Task { await settings.save() } }
        .sheet(isPresented: $showBlockedUsers) {
            BlockedUsersView(chatVM: nil)
        }
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !settings.chat.blockedWords.contains(kw) else { return }
        settings.chat.blockedWords.append(kw)
        newKeyword = ""
        Task { await settings.save() }
    }
}
