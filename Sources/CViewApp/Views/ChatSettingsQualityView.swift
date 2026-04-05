// MARK: - ChatSettingsView.swift
// CViewApp - 채팅 설정 & 화질 선택 뷰

import SwiftUI
import CViewCore
import CViewPersistence

// MARK: - Quality Selector View

struct QualitySelectorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    private var playerVM: PlayerViewModel? { appState.playerViewModel }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("화질 선택")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if let qualities = playerVM?.availableQualities, !qualities.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(qualities) { quality in
                            Button {
                                Task {
                                    await playerVM?.switchQuality(quality)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(quality.name)
                                            .font(DesignTokens.Typography.bodyMedium)
                                        Text("\(quality.resolution) · \(formatBandwidth(quality.bandwidth))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if playerVM?.currentQuality?.id == quality.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, DesignTokens.Spacing.md)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                        }
                    }
                }
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("사용 가능한 화질 정보가 없습니다")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("스트림이 재생 중일 때 화질을 변경할 수 있습니다")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
        }
        .frame(width: 340, height: 400)
    }
    
    private func formatBandwidth(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000.0)
        }
        return String(format: "%d Kbps", bps / 1000)
    }
}

// MARK: - Chat Settings View

struct ChatSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// 외부에서 주입된 ChatViewModel (멀티라이브 등)
    /// nil이면 appState.chatViewModel 사용 (기존 동작 유지)
    var overrideChatVM: ChatViewModel? = nil

    @State private var newKeyword = ""
    @State private var confirmClear = false

    private var chatVM: ChatViewModel? { overrideChatVM ?? appState.chatViewModel }
    private var store: SettingsStore { appState.settingsStore }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────────────────
            HStack {
                Label("채팅 설정", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typography.subhead)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider()

            // ── Content ────────────────────────────────────────────
            if let vm = chatVM {
                ScrollView {
                    VStack(spacing: 14) {
                        displaySection(vm: vm)
                        contentSection(vm: vm)
                        filterSection(vm: vm)
                        statsSection(vm: vm)
                        actionSection(vm: vm)
                    }
                    .padding(DesignTokens.Spacing.md)
                }
            } else {
                Spacer()
                Text("채팅이 연결되지 않았습니다")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
            }
        }
        .frame(width: 420, height: 600)
    }

    // MARK: - Section Builders

    @ViewBuilder
    private func displaySection(vm: ChatViewModel) -> some View {
        ChatSettingsCard(title: "표시", icon: "textformat.size", color: DesignTokens.Colors.accentPurple) {
            // 채팅 표시 모드
            ChatSettingsRow(label: "채팅 모드", icon: "rectangle.on.rectangle", iconColor: DesignTokens.Colors.chzzkGreen) {
                Picker("", selection: Binding(
                    get: { vm.displayMode },
                    set: { vm.displayMode = $0; saveToStore(vm) }
                )) {
                    ForEach(ChatDisplayMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }

            ChatSettingsDivider()

            // 오버레이 전용 설정
            if vm.displayMode == .overlay {
                ChatSettingsRow(label: "오버레이 배경", icon: "square.fill", iconColor: DesignTokens.Colors.textSecondary) {
                    HStack(spacing: 6) {
                        Slider(value: Binding(
                            get: { vm.overlayBackgroundOpacity },
                            set: { vm.overlayBackgroundOpacity = $0; saveToStore(vm) }
                        ), in: 0.0...1.0, step: 0.05)
                        .tint(DesignTokens.Colors.chzzkGreen)
                        .frame(width: 110)
                        Text("\(Int(vm.overlayBackgroundOpacity * 100))%")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                            .frame(width: 34)
                    }
                }

                ChatSettingsDivider()

                ChatSettingsRow(label: "입력창 표시", icon: "keyboard", iconColor: DesignTokens.Colors.textSecondary) {
                    Toggle("", isOn: Binding(
                        get: { vm.overlayShowInput },
                        set: { vm.overlayShowInput = $0; saveToStore(vm) }
                    ))
                    .toggleStyle(.switch).tint(DesignTokens.Colors.chzzkGreen).labelsHidden()
                }

                ChatSettingsDivider()
            }

            ChatSettingsRow(label: "글꼴 크기", icon: "textformat", iconColor: DesignTokens.Colors.accentPurple) {
                HStack(spacing: 6) {
                    Text("가").font(DesignTokens.Typography.custom(size: 10, weight: .regular)).foregroundStyle(DesignTokens.Colors.textTertiary)
                    Slider(value: Binding(
                        get: { vm.fontSize },
                        set: { vm.fontSize = $0; saveToStore(vm) }
                    ), in: 10...24, step: 1)
                    .tint(DesignTokens.Colors.accentPurple)
                    .frame(width: 110)
                    Text("가").font(DesignTokens.Typography.custom(size: 17)).foregroundStyle(DesignTokens.Colors.textTertiary)
                    Text("\(Int(vm.fontSize))pt")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.accentPurple)
                        .frame(width: 34)
                }
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "투명도", icon: "circle.lefthalf.filled", iconColor: .gray) {
                HStack(spacing: 6) {
                    Slider(value: Binding(
                        get: { vm.opacity },
                        set: { vm.opacity = $0; saveToStore(vm) }
                    ), in: 0.3...1.0, step: 0.05)
                    .tint(DesignTokens.Colors.accentPurple)
                    .frame(width: 110)
                    Text("\(Int(vm.opacity * 100))%")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.accentPurple)
                        .frame(width: 34)
                }
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "줄 간격", icon: "arrow.up.and.down.text.horizontal", iconColor: DesignTokens.Colors.textSecondary) {
                HStack(spacing: 6) {
                    Slider(value: Binding(
                        get: { vm.lineSpacing },
                        set: { vm.lineSpacing = $0; saveToStore(vm) }
                    ), in: 0...8, step: 1)
                    .tint(DesignTokens.Colors.accentPurple)
                    .frame(width: 110)
                    Text(String(format: "%.0fpt", vm.lineSpacing))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.accentPurple)
                        .frame(width: 38)
                }
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "타임스탬프", icon: "clock", iconColor: DesignTokens.Colors.textSecondary) {
                Toggle("", isOn: Binding(
                    get: { vm.showTimestamp },
                    set: { vm.showTimestamp = $0; saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.accentPurple).labelsHidden()
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "뱃지 표시", icon: "shield.fill", iconColor: DesignTokens.Colors.accentBlue) {
                Toggle("", isOn: Binding(
                    get: { vm.showBadge },
                    set: { vm.showBadge = $0; saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "멘션 강조", icon: "at", iconColor: DesignTokens.Colors.accentOrange,
                            description: "내 닉네임 언급 시 하이라이트") {
                Toggle("", isOn: Binding(
                    get: { vm.highlightMentions },
                    set: { vm.highlightMentions = $0; saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "역할 강조", icon: "person.badge.shield.checkmark.fill", iconColor: DesignTokens.Colors.chzzkGreen,
                            description: "스트리머/매니저 메시지 배경 강조") {
                Toggle("", isOn: Binding(
                    get: { vm.highlightRoles },
                    set: { vm.highlightRoles = $0; saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.chzzkGreen).labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func contentSection(vm: ChatViewModel) -> some View {
        ChatSettingsCard(title: "콘텐츠", icon: "sparkles", color: DesignTokens.Colors.accentOrange) {
            ChatSettingsRow(label: "이모티콘 표시", icon: "face.smiling", iconColor: DesignTokens.Colors.accentOrange) {
                Toggle("", isOn: Binding(
                    get: { vm.emoticonEnabled },
                    set: { vm.emoticonEnabled = $0; saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.accentOrange).labelsHidden()
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "도네이션 표시", icon: "heart.fill", iconColor: DesignTokens.Colors.live) {
                Toggle("", isOn: Binding(
                    get: { vm.showDonation },
                    set: { vm.showDonation = $0; saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.live).labelsHidden()
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "도네이션만 표시", icon: "line.3.horizontal.decrease.circle",
                            iconColor: DesignTokens.Colors.live, description: "일반 채팅 숨기고 도네이션만") {
                Toggle("", isOn: Binding(
                    get: { vm.showDonationsOnly },
                    set: { vm.showDonationsOnly = $0; saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.live).labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func filterSection(vm: ChatViewModel) -> some View {
        ChatSettingsCard(title: "필터 & 스크롤", icon: "line.3.horizontal.decrease.circle.fill",
                         color: DesignTokens.Colors.accentBlue) {
            ChatSettingsRow(label: "자동 스크롤", icon: "arrow.down.to.line", iconColor: DesignTokens.Colors.accentBlue) {
                Toggle("", isOn: Binding(
                    get: { vm.isAutoScrollEnabled },
                    set: { vm.isAutoScrollEnabled = $0; saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
            }

            ChatSettingsDivider()

            ChatSettingsRow(label: "채팅 필터", icon: "hand.raised.fill", iconColor: DesignTokens.Colors.accentBlue,
                            description: "차단 키워드가 포함된 메시지 숨김") {
                Toggle("", isOn: Binding(
                    get: { vm.isFilterEnabled },
                    set: { vm.setFilterEnabled($0); saveToStore(vm) }
                ))
                .toggleStyle(.switch).tint(DesignTokens.Colors.accentBlue).labelsHidden()
            }

            if vm.isFilterEnabled {
                ChatSettingsDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("차단 키워드")
                        .font(DesignTokens.Typography.captionSemibold)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.xs)

                    if !vm.blockedWords.isEmpty {
                        FlowTagView(tags: vm.blockedWords) { keyword in
                            vm.blockedWords.removeAll { $0 == keyword }
                            saveToStore(vm)
                            Task { await vm.addKeywordFilter(vm.blockedWords) }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                    }

                    HStack(spacing: 6) {
                        TextField("키워드 입력 후 +", text: $newKeyword)
                            .textFieldStyle(.roundedBorder)
                            .font(DesignTokens.Typography.caption)
                            .onSubmit { addKeyword(vm: vm) }
                        Button { addKeyword(vm: vm) } label: {
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
    }

    @ViewBuilder
    private func statsSection(vm: ChatViewModel) -> some View {
        ChatSettingsCard(title: "통계", icon: "chart.bar.fill", color: DesignTokens.Colors.textSecondary) {
            ChatStatRow(label: "총 메시지", value: "\(vm.messageCount)개", icon: "bubble.left.fill")
            ChatSettingsDivider()
            ChatStatRow(label: "초당 메시지", value: String(format: "%.1f/s", vm.messagesPerSecond), icon: "speedometer")
            ChatSettingsDivider()
            ChatStatRow(label: "참여 사용자", value: "\(vm.uniqueUserCount)명", icon: "person.2.fill")
            if vm.donationCount > 0 {
                ChatSettingsDivider()
                ChatStatRow(label: "도네이션", value: "\(vm.donationCount)건", icon: "heart.fill")
            }
        }
    }

    @ViewBuilder
    private func actionSection(vm: ChatViewModel) -> some View {
        Button {
            confirmClear = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("채팅 지우기")
                    .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .confirmationDialog("채팅 내용을 모두 지우겠습니까?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("지우기", role: .destructive) { vm.clearMessages() }
            Button("취소", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private func addKeyword(vm: ChatViewModel) {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !vm.blockedWords.contains(kw) else { return }
        vm.blockedWords.append(kw)
        newKeyword = ""
        saveToStore(vm)
        Task { await vm.addKeywordFilter(vm.blockedWords) }
    }

    private func saveToStore(_ vm: ChatViewModel) {
        store.chat = vm.exportSettings(base: store.chat)
        Task { await store.save() }
    }
}

// MARK: - Chat Settings Subviews

private struct ChatSettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(color)
                Text(title)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.xs)

            content()
                .padding(.bottom, DesignTokens.Spacing.xxs)
        }
        .background(DesignTokens.Colors.surfaceOverlay)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }
}

private struct ChatSettingsRow<Control: View>: View {
    let label: String
    let icon: String
    let iconColor: Color
    var description: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(iconColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(DesignTokens.Typography.captionMedium)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let desc = description {
                    Text(desc).font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
            }
            Spacer()
            control()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

private struct ChatSettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 42)
    }
}

private struct ChatStatRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 18)
            Text(label).font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignTokens.Typography.custom(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

/// 흐름(flow) 태그 레이아웃 — 차단 키워드 표시
private struct FlowTagView: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlexibleTagLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(DesignTokens.Typography.captionMedium)
                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                    Button { onRemove(tag) } label: {
                        Image(systemName: "xmark")
                            .font(DesignTokens.Typography.custom(size: 9, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(DesignTokens.Colors.accentBlue.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
}

/// 수평 우선 유연 레이아웃
private struct FlexibleTagLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowH + verticalSpacing; x = 0; rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + horizontalSpacing
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowH + verticalSpacing; x = bounds.minX; rowH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .init(size))
            rowH = max(rowH, size.height)
            x += size.width + horizontalSpacing
        }
    }
}


// MARK: - Clip Lookup View

struct ClipLookupView: View {
    let clipUID: String
    @Environment(AppState.self) private var appState
    @State private var clipInfo: ClipInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("클립 정보를 불러오는 중...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let clipInfo {
                ClipPlayerView(clipInfo: clipInfo)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(DesignTokens.Typography.custom(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("클립을 찾을 수 없습니다")
                        .font(.title3)
                        .fontWeight(.semibold)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("클립 UID: \(clipUID)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    Button("다시 시도") {
                        Task { await loadClip() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadClip() }
    }
    
    private func loadClip() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        guard let api = appState.apiClient else {
            errorMessage = "API 클라이언트가 초기화되지 않았습니다"
            return
        }
        
        do {
            let detail = try await api.clipDetail(clipUID: clipUID)
            clipInfo = ClipInfo(
                clipUID: clipUID,
                clipTitle: detail.clipTitle,
                thumbnailImageURL: detail.thumbnailImageURL,
                clipURL: detail.bestPlaybackURL ?? detail.clipURL,
                duration: detail.duration,
                readCount: detail.readCount ?? 0
            )
        } catch {
            // Fallback: create minimal ClipInfo
            clipInfo = ClipInfo(
                clipUID: clipUID,
                clipTitle: "클립 \(clipUID)"
            )
        }
    }
}
