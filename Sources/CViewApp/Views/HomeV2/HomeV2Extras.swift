// MARK: - HomeV2Extras.swift
// HomeView_v2 정밀 보강 컴포넌트
//
// 추가 항목 (docs/home-screen-redesign-analysis-2026-04-24.md 미구현분 보강):
//   • HomeCategoryChips         : 상위 카테고리 필터 칩 (P1-2)
//   • LiveCardActionMenu        : 카드 공용 contextMenu (P1-3)
//   • HomeActiveMultiLiveStrip  : 활성 멀티라이브 세션 strip (P0-4 보강)

import SwiftUI
import CViewCore
import CViewUI
import CViewPersistence

// MARK: - Category Chips

/// 인기 카테고리 칩 — selection 은 binding 으로 부모(View)가 보유.
/// nil = "전체" 선택. tap 으로 toggle.
struct HomeCategoryChips: View {
    /// 후보 채널들 (allStatChannels 권장) 으로부터 상위 카테고리 산출
    let channels: [LiveChannelItem]
    @Binding var selected: String?
    /// 표시할 칩 최대 개수 (전체 제외)
    var limit: Int = 6

    private var topCategories: [(name: String, count: Int)] {
        var counter: [String: Int] = [:]
        for ch in channels {
            guard let c = ch.categoryName, !c.isEmpty else { continue }
            counter[c, default: 0] += 1
        }
        return counter
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (name: $0.key, count: $0.value) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: "전체", count: channels.count, isOn: selected == nil) {
                    selected = nil
                }
                ForEach(topCategories, id: \.name) { item in
                    chip(label: item.name, count: item.count, isOn: selected == item.name) {
                        selected = (selected == item.name) ? nil : item.name
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chip(label: String, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(DesignTokens.Typography.captionSemibold)
                Text("\(count)")
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 5)
            .foregroundStyle(isOn ? Color.white : DesignTokens.Colors.textSecondary)
            .background(
                isOn
                    ? AnyShapeStyle(LinearGradient(
                        colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0.78)],
                        startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(DesignTokens.Colors.surfaceElevated),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    isOn ? DesignTokens.Colors.chzzkGreen.opacity(0.6) : DesignTokens.Glass.borderColor,
                    lineWidth: isOn ? 0.0 : 0.5
                )
            }
        }
        .buttonStyle(.plain)
        .animation(DesignTokens.Animation.fast, value: isOn)
    }
}

// MARK: - Live Card Action Menu (공용 contextMenu)

/// 카드/행에 일관된 우클릭/길게누르기 액션을 제공.
/// 즐겨찾기 토글은 dataStore 가 있을 때만 노출.
struct LiveCardActionMenu: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    let channelId: String
    let channelName: String
    /// 라이브 중 여부 (true 이면 "재생" / false 이면 "채널 상세")
    var isLive: Bool = true

    func body(content: Content) -> some View {
        content.contextMenu {
            if isLive {
                Button {
                    router.navigate(to: .live(channelId: channelId))
                } label: {
                    Label("재생", systemImage: "play.fill")
                }
                Button {
                    addToMultiLive()
                } label: {
                    Label("멀티라이브에 추가", systemImage: "square.grid.2x2.fill")
                }
                Button {
                    router.navigate(to: .chatOnly(channelId: channelId))
                } label: {
                    Label("채팅만 열기", systemImage: "text.bubble")
                }
                Divider()
            }
            Button {
                router.navigate(to: .channelDetail(channelId: channelId))
            } label: {
                Label("채널 상세 보기", systemImage: "person.crop.rectangle")
            }
            Divider()
            Button {
                Task { await toggleFavorite() }
            } label: {
                Label("즐겨찾기 토글", systemImage: "star")
            }
        }
    }

    private func addToMultiLive() {
        Task { @MainActor in
            await appState.multiLiveManager.addSession(
                channelId: channelId,
                presentationOverride: .embedded
            )
        }
    }

    private func toggleFavorite() async {
        guard let ds = appState.dataStore else { return }
        // saveChannel 로 등록을 보장한 뒤 toggleFavorite 호출
        let info = ChannelInfo(channelId: channelId, channelName: channelName)
        try? await ds.saveChannel(info, isFavorite: false)
        _ = try? await ds.toggleFavorite(channelId: channelId)
    }
}

extension View {
    /// 라이브 카드/행 공용 액션 메뉴 (재생 / 멀티라이브 / 채널 상세 / 즐겨찾기 토글)
    func liveCardActions(channelId: String, channelName: String, isLive: Bool = true) -> some View {
        modifier(LiveCardActionMenu(channelId: channelId, channelName: channelName, isLive: isLive))
    }
}

// MARK: - Active Multi-Live Strip

/// 멀티라이브 세션이 1개 이상이면 홈 상단에 노출되는 "Live Now Bar".
///
/// [2026-04-24 v2] 디자인 전면 리뉴얼 (외부 트렌드 리서치 기반):
///   • Discord 활성 통화 바 + Apple Now Playing 위젯 + Twitch 라이브 인디케이터 영감.
///   • Capsule 글래스(.ultraThinMaterial) 배경 + 미세한 chzzk green 글로우 보더.
///   • 좌측: pulsing LIVE dot(붉은 링이 바깥으로 퍼지는 ripple) + "LIVE" 모노스페이스 배지 +
///     세션 카운트 캡슐.
///   • 중앙: 겹치는 아바타 스택(최대 5개, 음수 spacing -8pt) + 채널명 marquee
///     (slack/discord 계정 스택 패턴).
///   • 우측: 그라디언트 pill "전체 보기" CTA — chzzk green → 약간 어두운 그린.
///   • 호버 시 capsule 약간 lift(scale 1.005), marquee 일시정지.
///   • ReduceMotion 시 모든 애니메이션 정지(아이콘만 표시).
struct HomeActiveMultiLiveStrip: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// liveLookup 으로 채널 이름/이미지 빠르게 조회
    let liveLookup: [String: LiveChannelItem]

    @State private var hovering: Bool = false

    private var sessions: [MultiLiveSession] {
        Array(appState.multiLiveManager.sessions)
    }

    var body: some View {
        if !sessions.isEmpty {
            HStack(spacing: 10) {
                liveBadge
                avatarStack
                marqueeNames
                Spacer(minLength: 4)
                viewAllButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(barBackground)
            .overlay(barBorder)
            .scaleEffect(hovering ? 1.005 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("멀티라이브 \(sessions.count)개 진행 중. 전체 보기")
        }
    }

    // MARK: Sub-components

    /// 좌측: pulsing LIVE dot + "LIVE" 배지 + 세션 카운트
    private var liveBadge: some View {
        HStack(spacing: 6) {
            LiveRippleDot(color: DesignTokens.Colors.live, paused: reduceMotion)
            Text("LIVE")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(DesignTokens.Colors.live)
            Text("\(sessions.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignTokens.Colors.live.opacity(0.18))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(DesignTokens.Colors.live.opacity(0.35), lineWidth: 0.6)
                )
                .contentTransition(.numericText())
                .animation(.snappy, value: sessions.count)
        }
        .fixedSize()
    }

    /// 겹치는 원형 아바타 스택 (최대 5개, 추가는 +N 캡슐로)
    private var avatarStack: some View {
        let visible = Array(sessions.prefix(5))
        let overflow = max(0, sessions.count - visible.count)
        return HStack(spacing: -8) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, session in
                avatarCircle(channelId: session.channelId)
                    .zIndex(Double(visible.count - idx))   // 앞쪽이 위로
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(DesignTokens.Colors.surfaceElevated)
                    )
                    .overlay(
                        Circle().strokeBorder(DesignTokens.Colors.surfaceBase, lineWidth: 1.5)
                    )
                    .zIndex(0)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func avatarCircle(channelId: String) -> some View {
        let live = liveLookup[channelId]
        let imageURL = URL(string: live?.channelImageUrl ?? "")
        let name = live?.channelName ?? channelId
        Button {
            router.navigate(to: .live(channelId: channelId))
        } label: {
            CachedAsyncImage(url: imageURL) {
                Circle().fill(DesignTokens.Colors.surfaceBase)
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .overlay(
                // 외곽 링 — 배경과 분리되어 stack 깊이 표현
                Circle().strokeBorder(DesignTokens.Colors.surfaceBase, lineWidth: 1.5)
            )
            .overlay(
                // 활성 indicator (chzzk green hairline)
                Circle().strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.85), lineWidth: 1)
                    .padding(-1)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(name) 으로 이동")
    }

    /// 채널명 marquee (단순 텍스트 chip · spacing 작음)
    private var marqueeNames: some View {
        MarqueeRow(
            items: sessions.map(\.channelId),
            speed: 24,
            spacing: 14,
            paused: reduceMotion || hovering
        ) { channelId in
            nameChip(channelId: channelId)
        }
        .frame(maxWidth: 360, maxHeight: 22)
        .mask(
            // 양 가장자리 fade — 끊김 없는 streaming 느낌
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }

    @ViewBuilder
    private func nameChip(channelId: String) -> some View {
        let live = liveLookup[channelId]
        let name = live?.channelName ?? channelId
        Button {
            router.navigate(to: .live(channelId: channelId))
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(DesignTokens.Colors.chzzkGreen)
                    .frame(width: 4, height: 4)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(name) 으로 이동")
    }

    /// 우측: 그라디언트 pill "전체 보기" CTA
    private var viewAllButton: some View {
        Button {
            router.selectSidebar(.following)
        } label: {
            HStack(spacing: 4) {
                Text("전체 보기")
                    .font(.system(size: 11, weight: .bold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [
                        DesignTokens.Colors.chzzkGreen,
                        DesignTokens.Colors.chzzkGreen.opacity(0.78)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.35), radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("팔로잉 전체 보기")
    }

    // MARK: Background / border

    private var barBackground: some View {
        ZStack {
            // 글래스 베이스
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
            // 좌→우 미세 그린 글로우
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DesignTokens.Colors.chzzkGreen.opacity(0.16),
                            DesignTokens.Colors.chzzkGreen.opacity(0.04),
                            .clear
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
        }
    }

    private var barBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        DesignTokens.Colors.chzzkGreen.opacity(0.55),
                        DesignTokens.Colors.chzzkGreen.opacity(0.18),
                        DesignTokens.Glass.borderColor
                    ],
                    startPoint: .leading, endPoint: .trailing
                ),
                lineWidth: 0.7
            )
    }
}

// MARK: - Live Ripple Dot

/// 붉은 점 + 바깥으로 퍼지는 링 1개 (Apple Music "재생 중" 인디케이터 톤).
/// shadow radius 애니메이션 회피 — 스케일/오파시티만 사용 (GPU 친화적).
private struct LiveRippleDot: View {
    var color: Color = DesignTokens.Colors.live
    var paused: Bool = false

    @State private var phase: CGFloat = 0  // 0 → 1 cycle

    var body: some View {
        ZStack {
            // 바깥 ripple 링
            Circle()
                .strokeBorder(color.opacity(0.55 * (1 - phase)), lineWidth: 1.2)
                .frame(width: 8 + 12 * phase, height: 8 + 12 * phase)
            // 코어 점
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                )
        }
        .frame(width: 20, height: 20)
        .drawingGroup()
        .onAppear {
            guard !paused else { return }
            phase = 0
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - Marquee Row (광고형 가로 흐름)

/// 컨텐츠를 두 번 이어붙여 무한 루프 효과 — 한 사이클(컨텐츠 폭 + spacing) 만큼
/// translation 후 0 으로 wrap. CALayer 가 GPU 에서 합성하므로 CPU 부담 ≈ 0.
///
/// 사용처: HomeActiveMultiLiveStrip (멀티라이브 세션 칩들).
private struct MarqueeRow<Item: Hashable, Cell: View>: View {
    let items: [Item]
    /// pt/s — 28 정도가 광고 전광판 느낌으로 자연스러움
    var speed: CGFloat = 30
    var spacing: CGFloat = 8
    /// ReduceMotion 등으로 강제 일시정지
    var paused: Bool = false
    @ViewBuilder let cell: (Item) -> Cell

    @State private var contentWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var hovering: Bool = false

    var body: some View {
        GeometryReader { geo in
            let active = !paused && !hovering && contentWidth > 0 && contentWidth > geo.size.width
            HStack(spacing: spacing) {
                row
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: MarqueeWidthKey.self, value: proxy.size.width)
                        }
                    )
                if active {
                    row   // 무한 루프용 복제본
                }
            }
            .offset(x: offset)
            .onPreferenceChange(MarqueeWidthKey.self) { newWidth in
                let rounded = newWidth.rounded()
                guard rounded > 0, abs(rounded - contentWidth) > 1 else { return }
                contentWidth = rounded
                offset = 0
                if !paused && !hovering && rounded > geo.size.width {
                    startAnimation()
                }
            }
            .onChange(of: active) { _, isActive in
                if isActive {
                    startAnimation()
                } else {
                    // 현재 위치에서 정지: 같은 값을 trivial 애니 없이 다시 대입해 implicit 애니 종료
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { offset = 0 }
                }
            }
            .onHover { hovering = $0 }
            .drawingGroup()  // GPU 합성 — translation 시 매 프레임 layout 비용 0
        }
    }

    private var row: some View {
        HStack(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                cell(item)
            }
        }
    }

    private func startAnimation() {
        guard contentWidth > 0 else { return }
        let cycle = contentWidth + spacing
        // offset 이 -cycle 에 도달하면 0 으로 점프 (두 번째 복제본이 첫 자리에 와 있으므로 시각적 끊김 없음)
        offset = 0
        let duration = TimeInterval(cycle / speed)
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -cycle
        }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 가장 큰 값 채택 (background GeometryReader 의 row 폭)
        let next = nextValue()
        if next > value { value = next }
    }
}
