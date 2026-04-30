// MARK: - ChatSettingsTab.swift
// 채팅 설정 탭 (SettingsView에서 추출)

import SwiftUI
import CViewCore
import CViewPersistence
import AVFoundation

struct ChatSettingsTab: View {
    @Bindable var settings: SettingsStore
    @State private var showBlockedUsers = false
    @State private var newKeyword = ""
    @AppStorage("chatPanelWidth") private var singleChatWidth: Double = 300
    @State private var singleChatWidthText: String = ""
    @State private var multiChatWidthText: String = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                SettingsPageHeader("채팅")

                // ── 패널 크기 ──────────────────────────────────────
                SettingsSection(title: "패널 크기", icon: "rectangle.split.2x1", color: DesignTokens.Colors.accentBlue) {
                    SettingsRow("멀티채팅 너비",
                                description: "앱 창 너비 대비 비율 (15~50%)",
                                icon: "square.split.2x1.fill", iconColor: DesignTokens.Colors.accentBlue) {
                        HStack(spacing: 6) {
                            Slider(value: Binding(
                                get: { Double(settings.multiChat.panelWidthRatio) },
                                set: { newVal in
                                    let clamped = min(max(newVal, 0.15), 0.50)
                                    settings.multiChat.panelWidthRatio = CGFloat(clamped)
                                    multiChatWidthText = "\(Int(clamped * 100))"
                                    Task { await settings.save() }
                                }
                            ), in: 0.15...0.50, step: 0.01)
                            .frame(width: 100)
                            .tint(DesignTokens.Colors.accentBlue)
                            TextField("", text: $multiChatWidthText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    if let pct = Int(multiChatWidthText.trimmingCharacters(in: .whitespaces)) {
                                        let clamped = min(max(Double(pct) / 100.0, 0.15), 0.50)
                                        settings.multiChat.panelWidthRatio = CGFloat(clamped)
                                        multiChatWidthText = "\(Int(clamped * 100))"
                                        Task { await settings.save() }
                                    } else {
                                        multiChatWidthText = "\(Int(settings.multiChat.panelWidthRatio * 100))"
                                    }
                                }
                            Text("%")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentBlue)
                        }
                    }
                    RowDivider()
                    SettingsRow("채팅 패널 너비",
                                description: "라이브 화면 사이드 채팅 너비 (pt)",
                                icon: "sidebar.right", iconColor: DesignTokens.Colors.accentBlue) {
                        HStack(spacing: 6) {
                            Slider(value: Binding(
                                get: { singleChatWidth },
                                set: { newVal in
                                    let clamped = min(max(newVal, 120), 800)
                                    singleChatWidth = clamped
                                    singleChatWidthText = "\(Int(clamped))"
                                }
                            ), in: 120...800, step: 10)
                            .frame(width: 100)
                            .tint(DesignTokens.Colors.accentBlue)
                            TextField("", text: $singleChatWidthText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 46)
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .onSubmit {
                                    if let val = Double(singleChatWidthText.trimmingCharacters(in: .whitespaces)) {
                                        let clamped = min(max(val, 120), 800)
                                        singleChatWidth = clamped
                                        singleChatWidthText = "\(Int(clamped))"
                                    } else {
                                        singleChatWidthText = "\(Int(singleChatWidth))"
                                    }
                                }
                            Text("pt")
                                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignTokens.Colors.accentBlue)
                        }
                    }
                }
                .onAppear {
                    singleChatWidthText = "\(Int(singleChatWidth))"
                    multiChatWidthText = "\(Int(settings.multiChat.panelWidthRatio * 100))"
                }

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
                    SettingsRow("투명도", icon: "circle.lefthalf.filled", iconColor: DesignTokens.Colors.textSecondary) {
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
                    RowDivider()
                    SettingsRow("역할 강조",
                                description: "방장, 매니저 등 역할을 색상으로 강조합니다",
                                icon: "person.badge.shield.checkmark.fill", iconColor: DesignTokens.Colors.chzzkGreen) {
                        Toggle("", isOn: $settings.chat.highlightRoles)
                            .toggleStyle(.switch).tint(DesignTokens.Colors.chzzkGreen).labelsHidden()
                    }
                }

                // ── 표시 모드 ──────────────────────────────────────
                SettingsSection(title: "표시 모드", icon: "rectangle.3.group", color: DesignTokens.Colors.accentPurple) {
                    SettingsRow("채팅 위치", icon: "sidebar.right", iconColor: DesignTokens.Colors.accentPurple) {
                        Picker("", selection: $settings.chat.displayMode) {
                            ForEach(ChatDisplayMode.allCases, id: \.self) { mode in
                                Label(mode.label, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .frame(width: 130)
                        .labelsHidden()
                    }
                    if settings.chat.displayMode == .overlay {
                        RowDivider()
                        SettingsRow("오버레이 너비", icon: "arrow.left.and.right", iconColor: DesignTokens.Colors.accentPurple) {
                            HStack(spacing: 6) {
                                Slider(value: $settings.chat.overlayWidth, in: 200...600, step: 10)
                                    .frame(width: 100)
                                    .tint(DesignTokens.Colors.accentPurple)
                                Text("\(Int(settings.chat.overlayWidth))px")
                                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.accentPurple)
                                    .frame(width: 44)
                            }
                        }
                        RowDivider()
                        SettingsRow("오버레이 높이", icon: "arrow.up.and.down", iconColor: DesignTokens.Colors.accentPurple) {
                            HStack(spacing: 6) {
                                Slider(value: $settings.chat.overlayHeight, in: 200...800, step: 20)
                                    .frame(width: 100)
                                    .tint(DesignTokens.Colors.accentPurple)
                                Text("\(Int(settings.chat.overlayHeight))px")
                                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.accentPurple)
                                    .frame(width: 44)
                            }
                        }
                        RowDivider()
                        SettingsRow("배경 투명도", icon: "circle.lefthalf.filled", iconColor: DesignTokens.Colors.textSecondary) {
                            HStack(spacing: 6) {
                                Slider(value: $settings.chat.overlayBackgroundOpacity, in: 0...1, step: 0.05)
                                    .frame(width: 100)
                                    .tint(DesignTokens.Colors.accentPurple)
                                Text("\(Int(settings.chat.overlayBackgroundOpacity * 100))%")
                                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.Colors.accentPurple)
                                    .frame(width: 34)
                            }
                        }
                        RowDivider()
                        SettingsRow("입력창 표시",
                                    description: "오버레이 모드에서 채팅 입력창을 표시합니다",
                                    icon: "character.cursor.ibeam", iconColor: DesignTokens.Colors.accentBlue) {
                            Toggle("", isOn: $settings.chat.overlayShowInput)
                                .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
                        }
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
                        RowDivider()
                        SettingsRow("음성 선택",
                                    description: "TTS에 사용할 음성을 선택합니다",
                                    icon: "person.wave.2.fill", iconColor: DesignTokens.Colors.accentPurple) {
                            Picker("", selection: Binding(
                                get: { settings.chat.ttsVoiceIdentifier ?? "" },
                                set: { settings.chat.ttsVoiceIdentifier = $0.isEmpty ? nil : $0 }
                            )) {
                                Text("시스템 기본").tag("")
                                ForEach(AVSpeechSynthesisVoice.speechVoices()
                                    .filter { $0.language.hasPrefix("ko") }
                                    .sorted(by: { $0.name < $1.name }), id: \.identifier) { voice in
                                    Text(voice.name).tag(voice.identifier)
                                }
                            }
                            .frame(width: 170)
                            .labelsHidden()
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

                            if !settings.chat.blockedWords.isEmpty {
                                SettingsFlowTagView(tags: settings.chat.blockedWords) { kw in
                                    settings.chat.blockedWords.removeAll { $0 == kw }
                                    Task { await settings.save() }
                                }
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
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.md)
                    }
                }

                // ── 사용자 관리 ────────────────────────────────────
                SettingsSection(title: "사용자 관리", icon: "person.2.fill", color: DesignTokens.Colors.live) {
                    Button {
                        showBlockedUsers = true
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.live)
                                .frame(width: 26, height: 26)
                                .background(DesignTokens.Colors.live.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("차단된 사용자 관리")
                                    .font(DesignTokens.Typography.body)
                                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                                Text("\(settings.chat.blockedUsers.count)명 차단됨")
                                    .font(DesignTokens.Typography.footnote)
                                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignTokens.Spacing.xl)
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
