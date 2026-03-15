// MARK: - ChatMessageRow.swift
// CViewApp - 채팅 메시지 행 렌더링 (일반/후원/구독/공지/시스템)

import SwiftUI
import AppKit
import CViewCore
import CViewChat
import CViewUI

// MARK: - Chat Render Config (값 타입 — EquatableChatMessageRow 재렌더링 최소화)

/// ChatViewModel의 렌더링 실정값들을 값 타입으로 스냅샷.
/// EquatableChatMessageRow는 message + config 두 값이 같으면 재렌더링을 건너뜀.
struct ChatRenderConfig: Equatable, Sendable {
    let fontSize: CGFloat
    let showTimestamp: Bool
    let showBadge: Bool
    let emoticonEnabled: Bool
    let lineSpacing: CGFloat
    let highlightMentions: Bool
    let currentUserNickname: String

    @MainActor
    init(from vm: ChatViewModel) {
        self.fontSize = vm.fontSize
        self.showTimestamp = vm.showTimestamp
        self.showBadge = vm.showBadge
        self.emoticonEnabled = vm.emoticonEnabled
        self.lineSpacing = vm.lineSpacing
        self.highlightMentions = vm.highlightMentions
        self.currentUserNickname = vm.currentUserNickname ?? ""
    }

    static let `default` = ChatRenderConfig(
        fontSize: 13, showTimestamp: true, showBadge: true,
        emoticonEnabled: true, lineSpacing: 2.0, highlightMentions: true,
        currentUserNickname: ""
    )

    init(
        fontSize: CGFloat, showTimestamp: Bool, showBadge: Bool,
        emoticonEnabled: Bool, lineSpacing: CGFloat, highlightMentions: Bool,
        currentUserNickname: String
    ) {
        self.fontSize = fontSize
        self.showTimestamp = showTimestamp
        self.showBadge = showBadge
        self.emoticonEnabled = emoticonEnabled
        self.lineSpacing = lineSpacing
        self.highlightMentions = highlightMentions
        self.currentUserNickname = currentUserNickname
    }
}

// MARK: - Chat Message Row (Premium)

struct ChatMessageRow: View {
    let message: ChatMessageItem
    let config: ChatRenderConfig
    var chatVM: ChatViewModel?
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
        let messageFontSize = config.fontSize
        let showTS          = config.showTimestamp
        let showBadge       = config.showBadge
        let emojiEnabled    = config.emoticonEnabled
        let spacing         = config.lineSpacing
        let myNickname      = config.currentUserNickname
        let isMentioned     = config.highlightMentions
            && !myNickname.isEmpty
            && message.content.localizedCaseInsensitiveContains(myNickname)

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            // 타임스탬프
            if showTS {
                Text(message.formattedTime)
                    .font(DesignTokens.Typography.custom(size: max(messageFontSize - 3, 9), weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.6))
                    .padding(.trailing, 6)
            }

            // 뱃지
            if showBadge, let badgeURL = message.badgeImageURL {
                CachedAsyncImage(url: badgeURL) {
                    EmptyView()
                }
                .frame(width: 16, height: 16)
                .padding(.trailing, 4)
            }

            // 닉네임 + 메시지 (치지직 스타일: 닉네임: 메시지)
            let useEmoji = emojiEnabled && !message.emojis.isEmpty
            if !useEmoji {
                (Text(message.nickname)
                    .font(DesignTokens.Typography.custom(size: messageFontSize, weight: .semibold))
                    .foregroundStyle(nicknameColor)
                + Text(": ")
                    .font(DesignTokens.Typography.custom(size: messageFontSize, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
                + Text(message.content)
                    .font(DesignTokens.Typography.custom(size: messageFontSize))
                    .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.88)))
                    .lineSpacing(spacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { showProfile = true }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(message.nickname)
                        .font(DesignTokens.Typography.custom(size: messageFontSize, weight: .semibold))
                        .foregroundStyle(nicknameColor)
                        .fixedSize()
                    Text(": ")
                        .font(DesignTokens.Typography.custom(size: messageFontSize, weight: .regular))
                        .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.5))
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(
                    isMentioned
                        ? DesignTokens.Colors.accentOrange.opacity(0.10)
                        : (isHovered ? Color.primary.opacity(0.04) : .clear)
                )
        )
        .overlay(
            isMentioned
                ? RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.accentOrange.opacity(0.35), lineWidth: 1)
                : nil
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .customCursor(.pointingHand)
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
            // 좌측 티어 액센트 바
            tierColor
                .frame(width: 3)

            // 카드 본문
            VStack(alignment: .leading, spacing: 8) {

                // 헤더: 아이콘 뱃지 · 닉네임 · 금액 필
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(tierColor.opacity(0.15))
                            .frame(width: 26, height: 26)
                        Image(systemName: typeIcon)
                            .font(DesignTokens.Typography.custom(size: 12, weight: .bold))
                            .foregroundStyle(tierColor)
                    }

                    Text(message.nickname)
                        .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let amount = message.donationAmount {
                        Text("₩\(amount.formatted())")
                            .font(DesignTokens.Typography.custom(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(tierColor, in: Capsule())
                    }
                }

                // 후원 타입 레이블
                Label(typeLabel, systemImage: typeIcon)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(tierColor.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(tierColor.opacity(0.1), in: Capsule())

                // 메시지 본문
                if !message.content.isEmpty {
                    ChatContentRenderer(content: message.content, emojis: message.emojis, fontSize: 13)
                        .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tierColor.opacity(0.08), tierColor.opacity(0.02)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .strokeBorder(tierColor.opacity(0.25), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
        // Metal 3: material+gradient+border+shadow 4중 합성 → GPU 단일 패스
        .compositingGroup()
        .shadow(color: tierColor.opacity(0.08), radius: 6, x: 0, y: 2)
        .padding(.vertical, 2)
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
            // 좌측 구독 티어 액센트 바
            subColor
                .frame(width: 3)

            // 카드 본문
            VStack(alignment: .leading, spacing: 8) {

                // 헤더: 아이콘 뱃지 · 닉네임 + 구독 문구 · 개월 수 필
                HStack(alignment: .center, spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(subColor.opacity(0.15))
                            .frame(width: 26, height: 26)
                        Image(systemName: subIcon)
                            .font(DesignTokens.Typography.custom(size: 12, weight: .bold))
                            .foregroundStyle(subColor)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.nickname)
                            .font(DesignTokens.Typography.custom(size: 13, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)
                        Text("구독하셨습니다!")
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(subColor)
                    }

                    Spacer(minLength: 4)

                    // 개월 수 뱃지 (2개월 이상)
                    if months > 1 {
                        Text("\(months)개월")
                            .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(subColor, in: Capsule())
                    }
                }

                // 마일스톤 뱃지 또는 연속 구독 레이블
                if let milestone {
                    Text(milestone)
                        .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                        .foregroundStyle(subColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(subColor.opacity(0.1), in: Capsule())
                } else if months > 1 {
                    Label("\(months)개월 연속 구독 중", systemImage: "repeat")
                        .font(DesignTokens.Typography.footnoteMedium)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                // 메시지 본문 (이모티콘 지원)
                if !message.content.isEmpty {
                    ChatContentRenderer(content: message.content, emojis: message.emojis, fontSize: 13)
                        .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(DesignTokens.Colors.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [subColor.opacity(0.08), subColor.opacity(0.02)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .strokeBorder(subColor.opacity(0.20), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
        // Metal 3: material+gradient+border+shadow 4중 합성 → GPU 단일 패스
        .compositingGroup()
        .shadow(color: subColor.opacity(0.08), radius: 6, x: 0, y: 2)
        .padding(.vertical, 2)
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
                .font(DesignTokens.Typography.custom(size: 10, weight: .medium))
                .foregroundStyle(systemMessageColor)
            
            Text(message.content)
                .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.7))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous)
                .fill(systemMessageColor.opacity(0.04))
        )
        .padding(.horizontal, DesignTokens.Spacing.xxs)
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
        HStack(spacing: 0) {
            // 좌측 액센트 바
            DesignTokens.Colors.accentOrange
                .frame(width: 3)

            HStack(spacing: 8) {
                Image(systemName: "megaphone.fill")
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)

                Text(message.content)
                    .font(DesignTokens.Typography.custom(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.9))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(DesignTokens.Colors.accentOrange.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .strokeBorder(DesignTokens.Colors.accentOrange.opacity(0.2), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
        .padding(.vertical, 2)
        .contextMenu {
            Button { chatVM?.pinMessage(message) } label: { Label("고정", systemImage: "pin") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string) } label: { Label("복사", systemImage: "doc.on.doc") }
        }
    }

    /// djb2 해시 — 실행마다 동일한 닉네임에 동일한 색상 보장 (hashValue는 런타임마다 달라짐)
    private var nicknameColor: Color {
        var hash: UInt64 = 5381
        for ch in message.nickname.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(ch)
        }
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
        return colors[Int(hash % UInt64(colors.count))]
    }
}

// MARK: - EquatableChatMessageRow (prevents unnecessary re-renders)

/// Wraps `ChatMessageRow` with equatable check so SwiftUI skips re-rendering when
/// neither the message nor the render config has changed.
/// chatVM은 moderation 액션 전용으로만 보유 — Observable 읽기를 이 뷰에서 수행하지 않음.
struct EquatableChatMessageRow: View, @preconcurrency Equatable {
    let message: ChatMessageItem
    let config: ChatRenderConfig
    var chatVM: ChatViewModel?

    var body: some View {
        ChatMessageRow(message: message, config: config, chatVM: chatVM)
    }

    nonisolated static func == (lhs: EquatableChatMessageRow, rhs: EquatableChatMessageRow) -> Bool {
        lhs.message == rhs.message && lhs.config == rhs.config
    }
}
