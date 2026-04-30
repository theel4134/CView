// MARK: - Statistics/Tabs/ChatStatsView.swift
// 채팅 탭 — 메시지 통계 + 분당 메시지 차트 + Top 발화자 + 후원/구독 + CSV 내보내기.

import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers
import CViewCore
import CViewChat
import CViewUI

struct ChatStatsView: View {
    @Environment(AppState.self) private var appState

    /// 1초 간격 messageCount 샘플 — 직전 30초(=30 포인트). 차트는 분당 비율 환산.
    @State private var messageRateSamples: [(timestamp: Date, count: Int)] = []
    @State private var sampleTask: Task<Void, Never>? = nil

    private var chatVM: ChatViewModel? { appState.chatViewModel }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {

                // ── 핵심 통계
                StatSection("채팅 통계", icon: "bubble.left.fill", color: DesignTokens.Colors.accentPurple) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "총 메시지",
                            value: "\(chatVM?.messageCount ?? 0)",
                            icon: "bubble.left.fill",
                            color: DesignTokens.Colors.accentBlue
                        )
                        StatCard(
                            title: "초당 메시지",
                            value: String(format: "%.1f", chatVM?.messagesPerSecond ?? 0),
                            icon: "bolt.fill",
                            color: .yellow
                        )
                        StatCard(
                            title: "연결 상태",
                            value: connectionStatusText,
                            icon: connectionIcon,
                            color: connectionColor
                        )
                    }
                }

                // ── 분당 메시지 차트 (신규)
                StatSection("메시지 비율 (직전 30초)", icon: "chart.line.uptrend.xyaxis", color: DesignTokens.Colors.accentCyan) {
                    if messageRateSamples.count >= 2 {
                        messageRateChart
                            .padding(DesignTokens.Spacing.sm)
                            .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                            }
                    } else {
                        EmptyStatePlaceholder(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "샘플 수집 중",
                            subtitle: "약 5초 후 차트가 표시됩니다"
                        )
                    }
                }

                // ── 참여 통계
                StatSection("참여 통계", icon: "person.3.fill", color: DesignTokens.Colors.chzzkGreen) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "참여 유저",
                            value: "\(chatVM?.uniqueUserCount ?? 0)",
                            icon: "person.2.fill",
                            color: DesignTokens.Colors.accentCyan
                        )
                        StatCard(
                            title: "도네이션",
                            value: "\(chatVM?.donationCount ?? 0)건",
                            icon: "gift.fill",
                            color: DesignTokens.Colors.accentOrange
                        )
                        StatCard(
                            title: "도네 총액",
                            value: "🪙\(chatVM?.totalDonationAmount ?? 0)",
                            icon: "gift.circle.fill",
                            color: .red
                        )
                    }
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: DesignTokens.Spacing.md) {
                        StatCard(
                            title: "구독",
                            value: "\(chatVM?.subscriptionCount ?? 0)건",
                            icon: "star.fill",
                            color: .yellow
                        )
                    }
                }

                // ── Top 발화자 (신규)
                StatSection(
                    "Top 발화자",
                    icon: "person.crop.circle.badge.checkmark",
                    color: DesignTokens.Colors.accentPurple,
                    trailing: AnyView(
                        Button {
                            exportChatHistoryAsCSV()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text("CSV 내보내기")
                            }
                            .font(DesignTokens.Typography.captionMedium)
                            .foregroundStyle(DesignTokens.Colors.accentBlue)
                        }
                        .buttonStyle(.plain)
                        .disabled(!(chatVM?.hasChatHistory ?? false))
                    )
                ) {
                    let top = topSpeakers(limit: 5)
                    if top.isEmpty {
                        EmptyStatePlaceholder(
                            icon: "person.crop.circle",
                            title: "발화 기록 없음",
                            subtitle: nil
                        )
                    } else {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            let maxCount = top.first?.count ?? 1
                            ForEach(Array(top.enumerated()), id: \.offset) { idx, entry in
                                speakerRow(rank: idx + 1, name: entry.nickname, count: entry.count, maxCount: maxCount)
                            }
                        }
                    }
                }

                // ── 최근 메시지
                StatSection("최근 메시지", icon: "text.bubble", color: DesignTokens.Colors.accentBlue) {
                    let recentMessages: [ChatMessageItem] = {
                        guard let buf = chatVM?.messages, !buf.isEmpty else { return [] }
                        return Array(buf.suffix(10).reversed())
                    }()
                    if recentMessages.isEmpty {
                        EmptyStatePlaceholder(
                            icon: "bubble.left.and.bubble.right",
                            title: "메시지 없음",
                            subtitle: nil
                        )
                    } else {
                        VStack(spacing: 2) {
                            ForEach(recentMessages) { msg in
                                HStack(spacing: 8) {
                                    Text(msg.nickname)
                                        .font(DesignTokens.Typography.captionSemibold)
                                        .foregroundStyle(DesignTokens.Colors.accentBlue)
                                        .frame(width: 90, alignment: .leading)
                                        .lineLimit(1)
                                    Text(msg.content)
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.85))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                            }
                        }
                        .padding(DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .contentBackground()
        .onAppear { startSampling() }
        .onDisappear { sampleTask?.cancel(); sampleTask = nil }
    }

    // MARK: - Sampling (in-view rate accumulator)

    private func startSampling() {
        sampleTask?.cancel()
        sampleTask = Task { @MainActor in
            while !Task.isCancelled {
                let now = Date()
                let count = chatVM?.messageCount ?? 0
                messageRateSamples.append((now, count))
                if messageRateSamples.count > 30 {
                    messageRateSamples.removeFirst(messageRateSamples.count - 30)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var messageRateChart: some View {
        // 1초 간격 messageCount 차분 → 분당 환산 (×60). 음수/리셋 보호.
        let deltas: [(Date, Double)] = zip(messageRateSamples, messageRateSamples.dropFirst()).compactMap { prev, cur in
            let d = cur.count - prev.count
            return d >= 0 ? (cur.timestamp, Double(d) * 60.0) : nil
        }
        Chart(deltas, id: \.0) { item in
            AreaMark(x: .value("시간", item.0), y: .value("분당", item.1))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(
                    colors: [DesignTokens.Colors.accentCyan.opacity(0.3),
                             DesignTokens.Colors.accentCyan.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("시간", item.0), y: .value("분당", item.1))
                .interpolationMethod(.monotone)
                .foregroundStyle(DesignTokens.Colors.accentCyan)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYAxisLabel("분당 메시지")
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(DesignTokens.Colors.border.opacity(0.2))
                AxisValueLabel(format: .dateTime.minute().second())
                    .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(DesignTokens.Colors.border.opacity(0.3))
                AxisValueLabel()
                    .font(DesignTokens.Typography.custom(size: 10, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .frame(height: 140)
    }

    // MARK: - Top Speakers

    private func topSpeakers(limit: Int) -> [(nickname: String, count: Int)] {
        guard let history = chatVM?.chatHistory, !history.isEmpty else { return [] }
        var bucket: [String: Int] = [:]
        for m in history {
            // 시스템/공지 제외
            if m.isSystem || m.isNotice { continue }
            bucket[m.nickname, default: 0] += 1
        }
        return bucket.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (nickname: $0.key, count: $0.value) }
    }

    @ViewBuilder
    private func speakerRow(rank: Int, name: String, count: Int, maxCount: Int) -> some View {
        let ratio = max(0.05, Double(count) / Double(maxCount))
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text("\(rank)")
                .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: 18, alignment: .trailing)
            Text(name)
                .font(DesignTokens.Typography.custom(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(DesignTokens.Colors.surfaceBase)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                        .fill(LinearGradient(
                            colors: [DesignTokens.Colors.accentPurple.opacity(0.7),
                                     DesignTokens.Colors.accentPink.opacity(0.9)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
            Text("\(count)")
                .font(DesignTokens.Typography.custom(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.accentPurple)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
        }
    }

    // MARK: - CSV Export

    private func exportChatHistoryAsCSV() {
        guard let history = chatVM?.chatHistory, !history.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "chzzk-chat-\(fmt.string(from: Date())).csv"
        panel.title = "채팅 기록 CSV로 저장"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "timestamp,nickname,userId,type,donationAmount,subscriptionMonths,content\n"
        let isoFmt = ISO8601DateFormatter()
        for m in history {
            let ts = isoFmt.string(from: m.timestamp)
            let nick = csvEscape(m.nickname)
            let uid = csvEscape(m.userId)
            let type = "\(m.type)"
            let donation = m.donationAmount.map { "\($0)" } ?? ""
            let sub = m.subscriptionMonths.map { "\($0)" } ?? ""
            let content = csvEscape(m.content)
            csv.append("\(ts),\(nick),\(uid),\(type),\(donation),\(sub),\(content)\n")
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

    // MARK: - Connection helpers

    private var connectionStatusText: String {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected: "연결됨"
        case .connecting: "연결 중"
        case .reconnecting: "재연결"
        case .disconnected: "끊김"
        case .failed: "실패"
        }
    }

    private var connectionIcon: String {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected: "wifi"
        case .connecting, .reconnecting: "wifi.exclamationmark"
        case .disconnected, .failed: "wifi.slash"
        }
    }

    private var connectionColor: Color {
        switch chatVM?.connectionState ?? .disconnected {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected, .failed: .red
        }
    }
}
