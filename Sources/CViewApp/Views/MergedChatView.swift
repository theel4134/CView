// MARK: - MergedChatView.swift
// CViewApp - 멀티채팅 통합 뷰
// 여러 채널의 메시지를 시간순으로 통합 표시
//
// [성능 개선] Timer 500ms 폴링 → 이벤트 기반 증분 업데이트
// · 변경 감지: 전체 세션 메시지 수 합산 → onChange 트리거
// · 증분 merge: 세션별 lastMergedCount로 delta만 처리 → O(k log k)
// · 링 버퍼: ChatMessageBuffer(300) 자동 eviction
// · 리플레이 모드: 스크롤 위치 기반 자동 고정 + 미읽음 배지

import SwiftUI
import CViewCore
import CViewUI

/// 채널별 라벨이 붙은 통합 메시지 아이템
struct MergedMessageItem: Identifiable, Equatable {
    let id: String
    let channelName: String
    let channelColor: Color
    let message: ChatMessageItem

    static func == (lhs: MergedMessageItem, rhs: MergedMessageItem) -> Bool {
        lhs.id == rhs.id && lhs.message == rhs.message
    }
}

/// 멀티채팅 통합 타임라인 뷰
/// 모든 세션의 메시지를 시간순으로 합산하여 단일 스트림으로 표시
struct MergedChatView: View {
    let sessionManager: MultiChatSessionManager

    // MARK: - Merged Message State

    /// 통합 메시지 목록 (시간순)
    @State private var mergedMessages: [MergedMessageItem] = []
    /// 세션별 마지막 병합 메시지 수 (증분 업데이트용)
    @State private var lastMergedCounts: [String: Int] = [:]
    /// 이전 세션 수 — 세션 추가/제거 감지용
    @State private var lastSessionCount: Int = 0

    // MARK: - Scroll & Replay State

    @State private var isReplayMode = false
    @State private var unreadCount = 0
    @State private var isAutoScrollEnabled = true
    @State private var isScrollViewVisible = true
    @State private var scrollSuppressionCount = 0
    @State private var containerHeight: CGFloat = 400

    private var isScrollSuppressed: Bool { scrollSuppressionCount > 0 }

    /// 채널별 색상 (인덱스 기반 고정)
    private static let channelColors: [Color] = [
        DesignTokens.Colors.chzzkGreen,
        DesignTokens.Colors.accentBlue,
        DesignTokens.Colors.accentOrange,
        DesignTokens.Colors.accentPurple,
        DesignTokens.Colors.accentPink,
        Color(hex: 0x00E5CC),
        Color(hex: 0xFFD60A),
        Color(hex: 0x64D2FF),
    ]

    // MARK: - Computed Triggers

    /// 전체 세션의 메시지 수 합산 — @Observable 추적으로 변경 시 자동 view invalidation
    private var totalMessageCount: Int {
        sessionManager.sessions.reduce(0) { $0 + $1.chatViewModel.messages.count }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if mergedMessages.isEmpty {
                        mergedEmptyState
                    } else {
                        ForEach(mergedMessages) { item in
                            mergedMessageRow(item)
                                .id(item.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: containerHeight, alignment: .bottom)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                if newHeight > 0 { containerHeight = newHeight }
            }
            // MARK: 스크롤 위치 감지 — 리플레이 모드 진입/해제
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let maxScrollY = geometry.contentSize.height - geometry.containerSize.height
                guard maxScrollY > 0 else { return true }
                let distanceFromBottom = maxScrollY - geometry.contentOffset.y
                let threshold = max(40.0, min(geometry.containerSize.height * 0.1, 120.0))
                return distanceFromBottom <= threshold
            } action: { oldValue, isNearBottom in
                guard oldValue != isNearBottom else { return }
                guard isScrollViewVisible, !isScrollSuppressed else { return }
                if isNearBottom {
                    exitReplayMode()
                } else if !isReplayMode, mergedMessages.count > 3 {
                    enterReplayMode()
                }
            }
            .onAppear {
                isScrollViewVisible = true
                fullRebuild()
            }
            .onDisappear {
                isScrollViewVisible = false
            }
            // MARK: 이벤트 기반 트리거 — 메시지 수 변경 시 증분 merge
            .onChange(of: totalMessageCount) { _, _ in
                mergeNewMessages()
                if isAutoScrollEnabled, !isReplayMode {
                    scrollToLatest(proxy: proxy)
                }
            }
            // 세션 추가/제거 시 전체 rebuild
            .onChange(of: sessionManager.sessions.count) { _, newCount in
                if newCount != lastSessionCount {
                    lastSessionCount = newCount
                    fullRebuild()
                    scrollToLatest(proxy: proxy)
                }
            }
            // MARK: 리플레이 모드 버튼 오버레이
            .overlay(alignment: .bottom) {
                Group {
                    if isReplayMode {
                        replayModeButton(proxy: proxy)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(DesignTokens.Animation.snappy, value: isReplayMode)
            }
        }
    }

    // MARK: - Merged Message Row

    private func mergedMessageRow(_ item: MergedMessageItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // 채널 라벨
            Text(item.channelName)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(item.channelColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(item.channelColor.opacity(0.12), in: Capsule())
                .padding(.trailing, 6)

            // 메시지 — EquatableChatMessageRow 재사용
            EquatableChatMessageRow(message: item.message, config: .default)
                .equatable()
        }
        .padding(.leading, 4)
    }

    // MARK: - Incremental Merge Logic

    /// 증분 업데이트 — 각 세션에서 새로 추가된 메시지만 수집하여 병합
    private func mergeNewMessages() {
        var newItems: [MergedMessageItem] = []

        for (index, session) in sessionManager.sessions.enumerated() {
            let color = Self.channelColors[index % Self.channelColors.count]
            let channelName = session.channelName
            let messages = session.chatViewModel.messages
            let currentCount = messages.count
            let lastCount = lastMergedCounts[session.id] ?? 0

            guard currentCount > lastCount else { continue }

            // 새 메시지만 수집 (ring buffer의 뒤쪽 delta)
            let startIdx = lastCount
            for i in startIdx..<currentCount {
                let msg = messages[i]
                newItems.append(MergedMessageItem(
                    id: "\(index)_\(msg.id)",
                    channelName: channelName,
                    channelColor: color,
                    message: msg
                ))
            }
            lastMergedCounts[session.id] = currentCount
        }

        guard !newItems.isEmpty else { return }

        // 새 메시지끼리만 정렬 — O(k log k), k = 새 메시지 수 (보통 < 20)
        newItems.sort { $0.message.timestamp < $1.message.timestamp }

        // 기존 목록에 append (새 메시지는 항상 최신이므로 전체 재정렬 불필요)
        mergedMessages.append(contentsOf: newItems)

        // 300개 초과 시 앞에서 제거
        if mergedMessages.count > 300 {
            mergedMessages.removeFirst(mergedMessages.count - 300)
        }

        // 리플레이 모드에서는 미읽음 카운트 증분
        if isReplayMode {
            unreadCount += newItems.count
        }
    }

    /// 전체 재구성 — 세션 추가/제거 시 또는 최초 표시 시
    private func fullRebuild() {
        var allMessages: [MergedMessageItem] = []
        lastMergedCounts.removeAll(keepingCapacity: true)

        for (index, session) in sessionManager.sessions.enumerated() {
            let color = Self.channelColors[index % Self.channelColors.count]
            let channelName = session.channelName
            let messages = session.chatViewModel.messages

            for msg in messages {
                allMessages.append(MergedMessageItem(
                    id: "\(index)_\(msg.id)",
                    channelName: channelName,
                    channelColor: color,
                    message: msg
                ))
            }
            lastMergedCounts[session.id] = messages.count
        }

        allMessages.sort { $0.message.timestamp < $1.message.timestamp }

        if allMessages.count > 300 {
            allMessages = Array(allMessages.suffix(300))
        }

        mergedMessages = allMessages
        lastSessionCount = sessionManager.sessions.count
    }

    // MARK: - Replay Mode

    private func enterReplayMode() {
        guard !isReplayMode else { return }
        isReplayMode = true
        unreadCount = 0
        isAutoScrollEnabled = false
    }

    private func exitReplayMode() {
        isReplayMode = false
        unreadCount = 0
        isAutoScrollEnabled = true
    }

    // MARK: - Scroll Helpers

    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let lastId = mergedMessages.last?.id else { return }
        scrollSuppressionCount += 1
        withAnimation(DesignTokens.Animation.chatScroll) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.scrollSuppressionCount = max(0, self.scrollSuppressionCount - 1)
        }
    }

    // MARK: - Replay Mode Button

    private func replayModeButton(proxy: ScrollViewProxy) -> some View {
        Button {
            exitReplayMode()
            scrollToLatest(proxy: proxy)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.down")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .bold))
                if unreadCount > 0 {
                    Text("새 메시지 \(unreadCount)개")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                } else {
                    Text("맨 아래로")
                        .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(unreadCount > 0 ? DesignTokens.Colors.onPrimary : DesignTokens.Colors.textPrimary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 6)
            .background {
                if unreadCount > 0 {
                    Capsule()
                        .fill(DesignTokens.Colors.chzzkGreen)
                } else {
                    Capsule()
                        .fill(DesignTokens.Colors.surfaceElevated)
                }
            }
            // [GPU 최적화] 조건분기 내 중복 shadow → 외부 단일 shadow로 통합
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .overlay {
                if unreadCount == 0 {
                    Capsule()
                        .strokeBorder(DesignTokens.Glass.borderColorLight, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, DesignTokens.Spacing.sm)
    }

    // MARK: - Empty State

    private var mergedEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.4))
            Text("통합 채팅")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text("여러 채널의 메시지가\n시간순으로 표시됩니다")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
