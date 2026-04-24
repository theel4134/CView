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
    let sessionIndex: Int
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
    @Environment(AppState.self) private var appState

    /// 하단 고정 sentinel ID (scrollTo 안정화용)
    private static let bottomAnchorID = "__merged_bottom_anchor__"

    // MARK: - Merged Message State

    /// 통합 메시지 목록 (시간순)
    @State private var mergedMessages: [MergedMessageItem] = []
    /// 세션별 마지막 병합 메시지 수 (증분 업데이트용)
    @State private var lastMergedCounts: [String: Int] = [:]
    /// 세션별 마지막으로 병합한 메시지 ID (ring buffer eviction 감지용)
    @State private var lastMergedMessageIds: [String: String] = [:]
    /// 이전 세션 수 — 세션 추가/제거 감지용
    @State private var lastSessionCount: Int = 0

    // MARK: - Scroll & Replay State

    @State private var isReplayMode = false
    @State private var unreadCount = 0
    @State private var isAutoScrollEnabled = true
    @State private var isScrollViewVisible = true
    /// 프로그래닝 스크롤 진행 중 geometry 변화 오탐 방지 — 시간 윈도 기반 (누적 차단 방지)
    @State private var scrollSuppressUntil: Date = .distantPast
    /// replay mode 진입 debounce — 배치 flush에 의한 일시적 geometry 변경을 걸러냄
    @State private var replayDebounceTask: Task<Void, Never>?

    // MARK: - P0-2: 통합 모드 채팅 입력
    /// 메시지를 보낼 대상 채널 ID (nil → 선택된 세션 / 첫 번째 세션)
    @State private var targetChannelId: String? = nil

    private var isScrollSuppressed: Bool { scrollSuppressUntil > Date() }

    /// 채널별 색상 팔레트
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

    /// channelId 해시 기반 안정적 색상 반환 (세션 순서/삭제에 영향받지 않음)
    private static func channelColor(for channelId: String) -> Color {
        var hash: UInt64 = 5381
        for byte in channelId.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return channelColors[Int(hash % UInt64(channelColors.count))]
    }

    /// 연결 상태를 푸터에 짧게 표시 — 재연결 시 attempt 횟수까지 노출 (P1-4)
    private func connectionShortLabel(_ state: ChatConnectionState) -> String {
        switch state {
        case .connected: return "연결됨"
        case .connecting: return "연결 중"
        case .reconnecting(let attempt) where attempt > 0: return "재연결 \(attempt)회"
        case .reconnecting: return "재연결 중"
        case .disconnected: return "끊김"
        case .failed: return "실패"
        }
    }

    // MARK: - Computed Triggers

    /// 메시지 변경 감지 — 각 세션의 (메시지 수, 마지막 ID) 페어 배열.
    /// count도 포함하여 ring buffer가 capacity 도달 후 evict+append로 last ID가 일시적으로
    /// 같은 값일 때도 누락 없이 감지 가능.
    private var messageChangeSignal: [String] {
        sessionManager.sessions.map { session in
            let msgs = session.chatViewModel.messages
            return "\(msgs.count)_\(msgs.last?.id ?? "")"
        }
    }

    /// 사용자 설정 기반 렌더 config (SettingsStore에서 가져옴)
    private var mergedRenderConfig: ChatRenderConfig {
        guard let session = sessionManager.sessions.first else { return .default }
        return ChatRenderConfig(from: session.chatViewModel)
    }

    /// 각 세션의 고정 메시지 수집 (최신 1개만 표시)
    private var pinnedMessages: [(channelName: String, message: ChatMessageItem)] {
        sessionManager.sessions.compactMap { session in
            guard let pinned = session.chatViewModel.pinnedMessage else { return nil }
            return (channelName: session.channelName, message: pinned)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
        GeometryReader { geo in
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
                        // 하단 고정 sentinel — scrollTo 타겟 안정화
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                }
                // ChatPanelView와 동일: minHeight로 콘텐츠가 적을 때도 하단 정렬 유지 → 앵커 흔들림 제거
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .bottom)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            // 새 메시지 삽입/레이아웃 변화에 대한 암시적 애니메이션 차단 → 스크롤 jitter 원천 제거
            .transaction { $0.animation = nil }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.bottom)
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
                    // 하단 도달 시 즉시 해제 + 보류 중인 debounce 취소
                    replayDebounceTask?.cancel()
                    replayDebounceTask = nil
                    if isReplayMode {
                        exitReplayMode()
                    }
                } else {
                    // 하단 이탈 시 debounce 후 진입 — 배치 flush(100ms)에 의한 일시적 geometry 변경 걸러냄
                    guard !isReplayMode, mergedMessages.count > 3 else { return }
                    guard replayDebounceTask == nil else { return }
                    replayDebounceTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled, !self.isReplayMode else { return }
                        self.enterReplayMode()
                        self.replayDebounceTask = nil
                    }
                }
            }
            .onAppear {
                isScrollViewVisible = true
                sessionManager.setAllSessionsForeground(true)
                fullRebuild()
            }
            .onDisappear {
                isScrollViewVisible = false
                sessionManager.setAllSessionsForeground(false)
            }
            // MARK: 이벤트 기반 트리거 — 메시지 변경 시 증분 merge
            .onChange(of: messageChangeSignal) { _, _ in
                mergeNewMessages()
                // [Auto-scroll Recovery 2026-04-18] geometry oscillation 으로 replay mode 가
                // 잘못 진입되어 읽힌 메시지 수(unreadCount)이 0 인 경우 다시 자동 스크롤 재개.
                if isReplayMode, unreadCount == 0 {
                    exitReplayMode()
                }
                if isAutoScrollEnabled, !isReplayMode {
                    stickyScroll(proxy: proxy)
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
            // MARK: 고정 메시지(공지) 배너
            .overlay(alignment: .top) {
                if let first = pinnedMessages.first {
                    mergedPinnedBanner(channelName: first.channelName, message: first.message)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // MARK: Esc 키 — 리플레이 모드 해제
            .onKeyPress(.escape) {
                guard isReplayMode else { return .ignored }
                exitReplayMode()
                scrollToLatest(proxy: proxy)
                return .handled
            }
        } // ScrollViewReader
        } // GeometryReader
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // P0-2: 통합 모드 채팅 입력 푸터 — 채널 타겟 피커 + 컴팩트 입력
        if !sessionManager.sessions.isEmpty, let target = effectiveTargetSession {
            mergedInputFooter(target: target)
        }
        } // VStack
    }

    // MARK: - Merged Input Footer (P0-2)

    /// 현재 메시지 전송 대상 세션 해결
    /// 우선순위: targetChannelId → selectedSession → 첫 번째 세션
    private var effectiveTargetSession: MultiChatSessionManager.ChatSession? {
        if let id = targetChannelId,
           let s = sessionManager.sessions.first(where: { $0.id == id }) {
            return s
        }
        if let sel = sessionManager.selectedSession { return sel }
        return sessionManager.sessions.first
    }

    private func mergedInputFooter(target: MultiChatSessionManager.ChatSession) -> some View {
        VStack(spacing: 0) {
            // 송신 채널 선택 바
            HStack(spacing: 6) {
                Image(systemName: "paperplane")
                    .font(DesignTokens.Typography.custom(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)

                Menu {
                    ForEach(sessionManager.sessions) { session in
                        Button {
                            targetChannelId = session.id
                        } label: {
                            HStack {
                                Text(session.channelName)
                                if session.id == target.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Self.channelColor(for: target.id))
                            .frame(width: 6, height: 6)
                        Text(target.channelName)
                            .font(DesignTokens.Typography.custom(size: 10.5, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(DesignTokens.Typography.custom(size: 8, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("메시지를 보낼 채널")

                Spacer()

                // 연결 상태 표시 — 재연결 attempt까지 함께 노출
                ChatConnectionStatusBadge(state: target.chatViewModel.connectionState, compact: false)
                Text(connectionShortLabel(target.chatViewModel.connectionState))
                    .font(DesignTokens.Typography.custom(size: 9.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 4)
            .background(DesignTokens.Colors.surfaceBase.opacity(0.7))

            // 컴팩트 입력 bar
            ChatInputView(
                viewModel: target.chatViewModel,
                compact: true,
                compactChannelHint: target.channelName
            )
            .id(target.id) // 채널 전환 시 입력 상태 리셋
        }
        .background(DesignTokens.Colors.surfaceBase)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.Glass.dividerColor)
                .frame(height: 0.5)
        }
    }

    // MARK: - Merged Message Row

    private func mergedMessageRow(_ item: MergedMessageItem) -> some View {
        MergedChatRowContainer(channelColor: item.channelColor) {
            VStack(alignment: .leading, spacing: 1) {
                // 채널 라벨 — 작은 텍스트 단독, 색상으로만 식별.
                // 기존 capsule+stroke 조합은 메시지 영역을 잠식하고 행당 수직 공간을
                // 과도하게 차지하여 가독성이 떨어졌음. 좌측 accent 바(3pt)가 채널
                // 경계를 시각적으로 잡아주고, 라벨은 메타정보로 축소.
                Text(item.channelName)
                    .font(DesignTokens.Typography.custom(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(item.channelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, MSTokens.chatRowHPad)

                // 메시지 — EquatableChatMessageRow 재사용 (사용자 설정 + chatVM 전달)
                EquatableChatMessageRow(
                    message: item.message,
                    config: mergedRenderConfig,
                    chatVM: sessionManager.sessions[safe: item.sessionIndex]?.chatViewModel
                )
                .equatable()
            }
            .padding(.vertical, MSTokens.chatRowVPad - 1)
        }
    }

    // MARK: - Incremental Merge Logic

    /// 증분 업데이트 — 각 세션에서 새로 추가된 메시지만 수집하여 병합
    /// Ring buffer eviction-safe: 마지막으로 본 메시지 ID를 기준으로 delta 계산
    private func mergeNewMessages() {
        var newItems: [MergedMessageItem] = []

        for (index, session) in sessionManager.sessions.enumerated() {
            let color = Self.channelColor(for: session.id)
            let channelName = session.channelName
            let messages = session.chatViewModel.messages
            let currentCount = messages.count
            guard currentCount > 0 else { continue }

            let lastCount = lastMergedCounts[session.id] ?? 0

            // Ring buffer eviction 감지:
            // buffer가 capacity에 도달하면 count가 정체되면서 앞 메시지가 evict됨.
            // lastCount > currentCount인 경우는 buffer가 reset된 것 → 전체 스캔.
            // lastCount == currentCount이면 마지막 메시지 ID로 실제 변경 여부 확인.
            let scanStart: Int
            if lastCount > currentCount {
                // Buffer reset 또는 축소 — 전체 스캔
                scanStart = 0
            } else if lastCount == currentCount, currentCount > 0 {
                // Count 동일 — ring buffer eviction 발생 가능.
                // 마지막 메시지 ID가 같으면 변경 없음.
                let lastMsg = messages[currentCount - 1]
                let knownLastId = lastMergedMessageIds[session.id]
                if knownLastId == lastMsg.id {
                    continue // 변경 없음
                }
                // ID가 다르면 새 메시지가 들어오면서 eviction 발생한 것.
                // 기존 merged에서 이 세션의 메시지를 제거 후 전체 재수집.
                mergedMessages.removeAll { $0.sessionIndex == index }
                scanStart = 0
            } else {
                // 정상 증분: lastCount < currentCount
                scanStart = lastCount
            }

            for i in scanStart..<currentCount {
                let msg = messages[i]
                newItems.append(MergedMessageItem(
                    id: "\(index)_\(msg.id)",
                    sessionIndex: index,
                    channelName: channelName,
                    channelColor: color,
                    message: msg
                ))
            }
            lastMergedCounts[session.id] = currentCount
            if currentCount > 0 {
                lastMergedMessageIds[session.id] = messages[currentCount - 1].id
            }
        }

        guard !newItems.isEmpty else { return }

        // 새 메시지끼리 먼저 정렬 — O(k log k), k = 새 메시지 수 (보통 < 20)
        newItems.sort {
            if $0.message.timestamp != $1.message.timestamp {
                return $0.message.timestamp < $1.message.timestamp
            }
            return $0.id < $1.id  // 타임스탬프 충돌 시 ID로 안정 정렬
        }

        // 시간순 유지 머지 삽입:
        // · 일반 케이스(새 메시지가 기존 last보다 미래): 단순 append → O(k)
        // · 역순 도착(네트워크 지연/세션 evict 재수집): 전체 merge-sort → O(n+k)
        // 덕분에 세션 간 타임스탬프 역전·eviction 재삽입 모두 순서 붕괴 없음.
        let lastExistingTs = mergedMessages.last?.message.timestamp
        let firstNewTs = newItems.first?.message.timestamp
        if let lastTs = lastExistingTs, let firstTs = firstNewTs, firstTs < lastTs {
            // 역전 발생 → 머지
            var merged: [MergedMessageItem] = []
            merged.reserveCapacity(mergedMessages.count + newItems.count)
            var i = 0
            var j = 0
            while i < mergedMessages.count && j < newItems.count {
                let a = mergedMessages[i].message.timestamp
                let b = newItems[j].message.timestamp
                if a <= b {
                    merged.append(mergedMessages[i]); i += 1
                } else {
                    merged.append(newItems[j]); j += 1
                }
            }
            if i < mergedMessages.count { merged.append(contentsOf: mergedMessages[i...]) }
            if j < newItems.count { merged.append(contentsOf: newItems[j...]) }
            mergedMessages = merged
        } else {
            mergedMessages.append(contentsOf: newItems)
        }

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
        lastMergedMessageIds.removeAll(keepingCapacity: true)  // 증분 merge 정합성을 위해 반드시 동기화

        for (index, session) in sessionManager.sessions.enumerated() {
            let color = Self.channelColor(for: session.id)
            let channelName = session.channelName
            let messages = session.chatViewModel.messages

            for msg in messages {
                allMessages.append(MergedMessageItem(
                    id: "\(index)_\(msg.id)",
                    sessionIndex: index,
                    channelName: channelName,
                    channelColor: color,
                    message: msg
                ))
            }
            lastMergedCounts[session.id] = messages.count
            if let lastId = messages.last?.id {
                lastMergedMessageIds[session.id] = lastId
            }
        }

        allMessages.sort {
            if $0.message.timestamp != $1.message.timestamp {
                return $0.message.timestamp < $1.message.timestamp
            }
            return $0.id < $1.id
        }

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
        replayDebounceTask?.cancel()
        replayDebounceTask = nil
        isReplayMode = false
        unreadCount = 0
        isAutoScrollEnabled = true
    }

    // MARK: - Scroll Helpers

    /// 새 메시지 자동 스크롤 — macOS SwiftUI `defaultScrollAnchor(.bottom)` 는
    /// contentSize/containerSize 변동 후 앵커 손실이 종종 발생하므로
    /// 명시적 `proxy.scrollTo(bottomAnchorID)` 로 하단 고정을 보장한다.
    /// `scrollSuppressUntil` 은 geometry oscillation 으로 인한 replay mode 오진입 차단용.
    private func stickyScroll(proxy: ScrollViewProxy) {
        guard !mergedMessages.isEmpty else { return }
        replayDebounceTask?.cancel()
        replayDebounceTask = nil
        scrollSuppressUntil = max(scrollSuppressUntil, Date().addingTimeInterval(0.08))
        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
    }

    /// 사용자 요청 시 최하단 스크롤 — 부드러운 애니메이션으로 이동
    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard !mergedMessages.isEmpty else { return }
        replayDebounceTask?.cancel()
        replayDebounceTask = nil
        scrollSuppressUntil = max(scrollSuppressUntil, Date().addingTimeInterval(0.2))
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
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

    // MARK: - Pinned Message Banner

    private func mergedPinnedBanner(channelName: String, message: ChatMessageItem) -> some View {
        HStack(spacing: 0) {
            DesignTokens.Colors.accentOrange
                .frame(width: 3)

            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
                    .rotationEffect(.degrees(-45))

                Text(channelName)
                    .font(DesignTokens.Typography.custom(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.accentOrange.opacity(0.7))

                Text(message.nickname)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.accentOrange)

                Text(message.content)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.85))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs + 2)
        }
        .background(DesignTokens.Colors.accentOrange.opacity(0.06))
    }
}

// MARK: - MergedChatRowContainer
/// 치지직 웹 채팅 UX 반영:
/// · 좌측 3pt accent 바로 채널 식별 (색상 팔레트 8종)
/// · hover 시 배경 살짝 강조 + accent 바 밝아짐
/// 스크롤 jitter 방지를 위해 opacity/위치 관련 등장 애니메이션은 의도적으로 제외.
/// (LazyVStack + .defaultScrollAnchor(.bottom) 조합과 충돌하여 새 메시지 삽입 시 흔들림 유발)
private struct MergedChatRowContainer<Content: View>: View {
    let channelColor: Color
    @ViewBuilder let content: () -> Content
    @State private var isHovering = false

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovering
                    ? DesignTokens.Colors.chzzkGreen.opacity(0.05)
                    : Color.clear
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(channelColor.opacity(isHovering ? 1.0 : 0.75))
                    .frame(width: 3)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
