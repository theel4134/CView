// MARK: - ChatPanelView.swift
// CViewApp - 프리미엄 채팅 패널
// Design: Discord/Twitch 스타일 다크 채팅 + 모던 메시지 레이아웃

import SwiftUI
import CViewCore
import CViewChat
import CViewUI

// MARK: - Chat Panel (Header + Messages + Input)

struct ChatPanelView: View {
    let chatVM: ChatViewModel?
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            chatHeader

            // Messages list
            ChatMessagesView(viewModel: chatVM)

            // Input area
            ChatInputView(viewModel: chatVM)
        }
        .background(DesignTokens.Colors.backgroundElevated)
        .sheet(isPresented: Binding(
            get: { chatVM?.showExportSheet ?? false },
            set: { chatVM?.showExportSheet = $0 }
        )) {
            ChatExportView()
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
            
            Text("채팅")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            // Connection status pill
            HStack(spacing: 5) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: connectionColor.opacity(0.5), radius: 3)

                Text(connectionText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DesignTokens.Colors.surface)
            .clipShape(Capsule())

            // Chat export
            Button {
                chatVM?.showExportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DesignTokens.Colors.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("채팅 내보내기")
            .disabled(chatVM?.messages.isEmpty ?? true)

            // Chat settings
            Button(action: onOpenSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(DesignTokens.Colors.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.backgroundDark)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.Colors.border.opacity(0.3))
                .frame(height: 0.5)
        }
    }

    // MARK: - Connection State

    private var connectionColor: Color {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected(_): DesignTokens.Colors.chzzkGreen
        case .connecting, .reconnecting(_): DesignTokens.Colors.warning
        case .disconnected, .failed(_): DesignTokens.Colors.error
        }
    }

    private var connectionText: String {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected(_): "연결됨"
        case .connecting: "연결 중"
        case .reconnecting(_): "재연결 중"
        case .disconnected: "연결 끊김"
        case .failed(_): "연결 실패"
        }
    }
}

// MARK: - Chat Messages View

struct ChatMessagesView: View {
    let viewModel: ChatViewModel?

    var body: some View {
        VStack(spacing: 0) {
            // Pinned message banner
            if let pinned = viewModel?.pinnedMessage {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Colors.accentOrange)
                        .rotationEffect(.degrees(-45))

                    Text(pinned.nickname)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.accentOrange)

                    Text(pinned.content)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        viewModel?.unpinMessage()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [
                            DesignTokens.Colors.accentOrange.opacity(0.12),
                            DesignTokens.Colors.accentOrange.opacity(0.04)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(DesignTokens.Colors.accentOrange)
                        .frame(width: 3)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(viewModel?.messages ?? []) { message in
                        ChatMessageRow(message: message, chatVM: viewModel)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .onChange(of: viewModel?.messages.count) { _, _ in
                if viewModel?.isAutoScrollEnabled == true {
                    if let lastId = viewModel?.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
        } // VStack
    }
}

// MARK: - Chat Message Row (Premium)

struct ChatMessageRow: View {
    let message: ChatMessageItem
    var chatVM: ChatViewModel?
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var showProfile = false

    var body: some View {
        Group {
            if message.isNotice {
                noticeMessageView
            } else if message.isSystem {
                systemMessageView
            } else if message.type == MessageType.donation {
                donationMessageView
            } else if message.type == MessageType.subscription {
                subscriptionMessageView
            } else {
                normalMessageView
            }
        }
    }

    private var normalMessageView: some View {
        let messageFontSize = chatVM?.fontSize ?? appState.settingsStore.chat.fontSize
        let showTS          = chatVM?.showTimestamp ?? appState.settingsStore.chat.showTimestamp
        let showBadge       = chatVM?.showBadge ?? true
        let emojiEnabled    = chatVM?.emoticonEnabled ?? appState.settingsStore.chat.emoticonEnabled
        let spacing         = chatVM?.lineSpacing ?? 2.0
        // 멘션 강조: 현재 사용자 닉네임이 메시지에 포함되면 행 배경 강조
        let myNickname      = chatVM?.currentUserNickname ?? ""
        let isMentioned     = chatVM?.highlightMentions == true
            && !myNickname.isEmpty
            && message.content.localizedCaseInsensitiveContains(myNickname)

        return HStack(alignment: .top, spacing: 6) {
            if showTS {
                Text(message.formattedTime)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .padding(.top, 1)
            }

            if showBadge, let badgeURL = message.badgeImageURL {
                CachedAsyncImage(url: badgeURL) {
                    EmptyView()
                }
                .frame(width: 14, height: 14)
                .padding(.top, 2)
            }

            let useEmoji = emojiEnabled && !message.emojis.isEmpty
            if !useEmoji {
                (Text(message.nickname + " ")
                    .font(.system(size: messageFontSize, weight: .bold))
                    .foregroundStyle(nicknameColor)
                + Text(message.content)
                    .font(.system(size: messageFontSize))
                    .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.9)))
                    .lineSpacing(spacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { showProfile = true }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(message.nickname + " ")
                        .font(.system(size: messageFontSize, weight: .bold))
                        .foregroundStyle(nicknameColor)
                        .fixedSize()
                    ChatContentRenderer(
                        content: message.content,
                        emojis: message.emojis,
                        fontSize: messageFontSize
                    )
                    .lineSpacing(spacing)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .onTapGesture { showProfile = true }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .background(
            isMentioned
                ? DesignTokens.Colors.accentOrange.opacity(0.10)
                : (isHovered ? DesignTokens.Colors.surfaceHover.opacity(0.5) : .clear)
        )
        .overlay(
            isMentioned
                ? RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(DesignTokens.Colors.accentOrange.opacity(0.45), lineWidth: 1)
                : nil
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in isHovered = hovering }
        .popover(isPresented: $showProfile) {
            ChatUserProfileSheet(message: message, chatVM: chatVM)
        }
        .contextMenu {
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.nickname, forType: .string) } label: { Label("닉네임 복사", systemImage: "person.text.rectangle") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) } label: { Label("메시지 복사", systemImage: "doc.on.doc") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.userId, forType: .string) } label: { Label("사용자 ID 복사", systemImage: "number") }
            Divider()
            Button { Task { await chatVM?.blockUser(message.userId) } } label: { Label("차단", systemImage: "person.fill.xmark") }
            Divider()
            Button { if let url = URL(string: "https://chzzk.naver.com/live/\(message.userId)") { NSWorkspace.shared.open(url) } } label: { Label("치지직에서 열기", systemImage: "safari") }
        }
    }

    // MARK: - Donation Tier Helpers

    /// 후원 금액에 따른 (티어 색상, 레이블, 아이콘) 반환
    private var donationTierData: (color: Color, label: String, icon: String) {
        let amount = message.donationAmount ?? 0
        switch amount {
        case ..<1_000:
            return (DesignTokens.Colors.accentBlue, "소액 후원", "bolt.circle.fill")
        case ..<10_000:
            return (DesignTokens.Colors.chzzkGreen, "후원", "heart.fill")
        case ..<50_000:
            return (DesignTokens.Colors.accentOrange, "큰 후원", "flame.fill")
        default:
            return (DesignTokens.Colors.error, "대형 후원", "crown.fill")
        }
    }

    // MARK: - Donation Card

    private var donationMessageView: some View {
        let (tierColor, tierLabel, tierIcon) = donationTierData
        let donationType = message.donationType ?? "CHAT"
        let typeIcon  = donationType == "VIDEO"   ? "play.rectangle.fill"
                      : donationType == "MISSION" ? "flag.fill"
                      : tierIcon
        let typeLabel = donationType == "VIDEO"   ? "영상 후원"
                      : donationType == "MISSION" ? "미션 후원"
                      : tierLabel

        return HStack(spacing: 0) {
            // ── 좌측 티어 액센트 바 ──────────────────────────────
            tierColor
                .frame(width: 3)

            // ── 카드 본문 ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {

                // 헤더: 아이콘 뱃지 · 닉네임 · 금액 필
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(tierColor.opacity(0.2))
                            .frame(width: 28, height: 28)
                        Image(systemName: typeIcon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tierColor)
                    }

                    Text(message.nickname)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let amount = message.donationAmount {
                        Text("₩\(amount.formatted())")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(tierColor)
                            .clipShape(Capsule())
                    }
                }

                // 후원 타입 레이블 필
                Label(typeLabel, systemImage: typeIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tierColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tierColor.opacity(0.15))
                    .clipShape(Capsule())

                // 메시지 본문
                if !message.content.isEmpty {
                    ChatContentRenderer(content: message.content, emojis: message.emojis, fontSize: 13)
                        .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(LinearGradient(
                    colors: [tierColor.opacity(0.12), DesignTokens.Colors.surface.opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(tierColor.opacity(0.45), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .shadow(color: tierColor.opacity(0.14), radius: 4, x: 0, y: 2)
        .padding(.vertical, 3)
        .contextMenu {
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.nickname, forType: .string) } label: { Label("닉네임 복사", systemImage: "person.text.rectangle") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) } label: { Label("메시지 복사", systemImage: "doc.on.doc") }
            if let amount = message.donationAmount {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("₩\(amount.formatted())", forType: .string) } label: { Label("금액 복사", systemImage: "wonsign.circle") }
            }
            Divider()
            Button { Task { await chatVM?.blockUser(message.userId) } } label: { Label("차단", systemImage: "person.fill.xmark") }
        }
    }

    // MARK: - Subscription Tier Helpers

    private func subscriptionColor(months: Int) -> Color {
        switch months {
        case ..<3:  return DesignTokens.Colors.chzzkGreen
        case ..<6:  return DesignTokens.Colors.accentBlue
        case ..<12: return DesignTokens.Colors.accentPurple
        default:    return DesignTokens.Colors.donation   // 골드
        }
    }

    private func subscriptionIcon(months: Int) -> String {
        switch months {
        case ..<3:  return "star.fill"
        case ..<6:  return "star.circle.fill"
        case ..<12: return "crown"
        default:    return "crown.fill"
        }
    }

    /// 마일스톤 개월(3/6/12/24개월 등) 도달 시 특별 레이블 반환
    private func subscriptionMilestone(months: Int) -> String? {
        switch months {
        case 1:  return nil
        case 3:  return "3개월 달성 🎉"
        case 6:  return "6개월 달성 ✨"
        case 12: return "1년 달성 👑"
        case 24: return "2년 달성 💎"
        default: return months % 12 == 0 ? "\(months / 12)년 달성 👑" : nil
        }
    }

    // MARK: - Subscription Card

    private var subscriptionMessageView: some View {
        let months    = message.subscriptionMonths ?? 1
        let subColor  = subscriptionColor(months: months)
        let subIcon   = subscriptionIcon(months: months)
        let milestone = subscriptionMilestone(months: months)

        return HStack(spacing: 0) {
            // ── 좌측 구독 티어 액센트 바 ─────────────────────────
            subColor
                .frame(width: 3)

            // ── 카드 본문 ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {

                // 헤더: 아이콘 뱃지 · 닉네임 + 구독 문구 · 개월 수 필
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(subColor.opacity(0.2))
                            .frame(width: 28, height: 28)
                        Image(systemName: subIcon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(subColor)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.nickname)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)
                        Text("구독하셨습니다!")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(subColor)
                    }

                    Spacer(minLength: 4)

                    // 개월 수 뱃지 (2개월 이상)
                    if months > 1 {
                        Text("\(months)개월")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(subColor)
                            .clipShape(Capsule())
                    }
                }

                // 마일스톤 뱃지 또는 연속 구독 레이블
                if let milestone {
                    Text(milestone)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(subColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(subColor.opacity(0.15))
                        .clipShape(Capsule())
                } else if months > 1 {
                    Label("\(months)개월 연속 구독 중", systemImage: "repeat")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                // 메시지 본문
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(LinearGradient(
                    colors: [subColor.opacity(0.12), DesignTokens.Colors.surface.opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(subColor.opacity(0.40), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .shadow(color: subColor.opacity(0.12), radius: 4, x: 0, y: 2)
        .padding(.vertical, 3)
        .contextMenu {
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.nickname, forType: .string) } label: { Label("닉네임 복사", systemImage: "person.text.rectangle") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) } label: { Label("메시지 복사", systemImage: "doc.on.doc") }
            Divider()
            Button { Task { await chatVM?.blockUser(message.userId) } } label: { Label("차단", systemImage: "person.fill.xmark") }
        }
    }

    private var systemMessageView: some View {
        HStack(spacing: 6) {
            Image(systemName: systemMessageIcon)
                .font(.system(size: 10))
                .foregroundStyle(systemMessageColor)
            
            Text(message.content)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .italic()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, DesignTokens.Spacing.xs)
    }

    private var systemMessageIcon: String {
        let content = message.content
        if content.contains("차단") || content.contains("block") { return "person.fill.xmark" }
        if content.contains("해제") || content.contains("unblock") || content.contains("unmute") { return "person.fill.checkmark" }
        if content.contains("뮤트") || content.contains("금지") || content.contains("mute") { return "speaker.slash.fill" }
        if content.contains("필터") || content.contains("filter") { return "line.3.horizontal.decrease.circle" }
        if content.contains("추방") || content.contains("kick") { return "door.left.hand.open" }
        if content.contains("⚠️") || content.contains("실패") || content.contains("error") { return "exclamationmark.triangle.fill" }
        if content.contains("명령어") || content.contains("help") { return "questionmark.circle" }
        return "info.circle"
    }

    private var systemMessageColor: Color {
        let content = message.content
        if content.contains("⚠️") || content.contains("실패") { return DesignTokens.Colors.error }
        if content.contains("차단") || content.contains("추방") { return DesignTokens.Colors.warning }
        if content.contains("해제") { return DesignTokens.Colors.chzzkGreen }
        return DesignTokens.Colors.textTertiary
    }

    private var noticeMessageView: some View {
        HStack(spacing: 8) {
            Image(systemName: "pin.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.accentOrange)

            Text(message.content)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Colors.accentOrange.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Colors.accentOrange.opacity(0.3), lineWidth: 0.5)
                }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button { chatVM?.pinMessage(message) } label: { Label("고정", systemImage: "pin") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) } label: { Label("복사", systemImage: "doc.on.doc") }
        }
    }

    private var nicknameColor: Color {
        let hash = abs(message.nickname.hashValue)
        let colors: [Color] = [
            DesignTokens.Colors.chzzkGreen,    // 치지직 그린
            DesignTokens.Colors.accentBlue,    // 블루
            DesignTokens.Colors.accentOrange,  // 오렌지
            DesignTokens.Colors.accentPurple,  // 퍼플
            DesignTokens.Colors.accentPink,    // 핑크
            Color(hex: 0x00E5CC),              // 시안
            Color(hex: 0xFFD60A),              // 옐로우
            Color(hex: 0x30D158),              // 라임
            Color(hex: 0xFF6B6B),              // 코랄
            Color(hex: 0x64D2FF),              // 스카이
        ]
        return colors[hash % colors.count]
    }
}

// MARK: - Chat Input View (Premium)

struct ChatInputView: View {
    let viewModel: ChatViewModel?
    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @State private var showEmoticonPicker = false

    /// 채팅 전송 가능 여부 (연결 + 로그인)
    private var canSend: Bool { viewModel?.canSendChat ?? false }

    var body: some View {
        VStack(spacing: 0) {
            // 로그인 안내 배너 (미로그인 또는 Read-only 연결 시)
            if let vm = viewModel, vm.connectionState.isConnected, !canSend {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                    Text("로그인하면 채팅에 참여할 수 있어요")
                        .font(.system(size: 12))
                }
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(DesignTokens.Colors.surface.opacity(0.6))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DesignTokens.Colors.border.opacity(0.3))
                        .frame(height: 0.5)
                }
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                // Emoticon button
                Button {
                    showEmoticonPicker.toggle()
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 14))
                        .foregroundStyle(showEmoticonPicker ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(DesignTokens.Colors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmoticonPicker) {
                    EmoticonPickerView(packs: viewModel?.emoticonPickerPacks ?? []) { emoticon in
                        inputText += emoticon.chatPattern
                        showEmoticonPicker = false
                    }
                }
                .help("이모티콘")
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.4)

                HStack(spacing: 8) {
                    Image(systemName: canSend ? "text.bubble" : "lock")
                        .font(.system(size: 12))
                        .foregroundStyle(isFocused ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textTertiary)

                    TextField(canSend ? "채팅을 입력하세요..." : "로그인 후 채팅 참여 가능", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .focused($isFocused)
                        .onSubmit { sendMessage() }
                        .disabled(!canSend)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, 8)
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(
                            isFocused ? DesignTokens.Colors.chzzkGreen.opacity(0.5) : DesignTokens.Colors.border.opacity(0.3),
                            lineWidth: isFocused ? 1 : 0.5
                        )
                }
                .animation(DesignTokens.Animation.fast, value: isFocused)
                .onTapGesture { if canSend { isFocused = true } }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(canSend && !inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .black : DesignTokens.Colors.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(canSend && !inputText.trimmingCharacters(in: .whitespaces).isEmpty ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend || inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                .animation(DesignTokens.Animation.fast, value: inputText.isEmpty)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.backgroundDark)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DesignTokens.Colors.border.opacity(0.3))
                    .frame(height: 0.5)
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, canSend else { return }
        viewModel?.inputText = text
        inputText = ""
        Task { await viewModel?.sendMessage() }
        inputText = ""
    }
}
