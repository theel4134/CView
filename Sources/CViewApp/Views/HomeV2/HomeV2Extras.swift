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

/// 멀티라이브 세션이 1개 이상이면 홈 상단에 노출되는 가로 strip.
/// 각 칩은 채널 아바타 + 이름, 우측에 "전체 보기" / "닫기" 액션.
struct HomeActiveMultiLiveStrip: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    /// liveLookup 으로 채널 이름/이미지 빠르게 조회
    let liveLookup: [String: LiveChannelItem]

    var body: some View {
        let sessions = Array(appState.multiLiveManager.sessions)
        if !sessions.isEmpty {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                Text("멀티라이브 \(sessions.count)개 진행 중")
                    .font(DesignTokens.Typography.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Spacer(minLength: DesignTokens.Spacing.sm)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sessions, id: \.id) { session in
                            sessionChip(channelId: session.channelId)
                        }
                    }
                }
                .frame(maxWidth: 380)

                Button {
                    router.selectSidebar(.following)
                } label: {
                    HStack(spacing: 3) {
                        Text("전체 보기")
                            .font(DesignTokens.Typography.captionSemibold)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [
                        DesignTokens.Colors.chzzkGreen.opacity(0.12),
                        DesignTokens.Colors.chzzkGreen.opacity(0.05)
                    ],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(DesignTokens.Colors.chzzkGreen.opacity(0.35), lineWidth: 0.6)
            }
        }
    }

    @ViewBuilder
    private func sessionChip(channelId: String) -> some View {
        let live = liveLookup[channelId]
        let name = live?.channelName ?? channelId
        let imageURL = URL(string: live?.channelImageUrl ?? "")
        Button {
            router.navigate(to: .live(channelId: channelId))
        } label: {
            HStack(spacing: 4) {
                CachedAsyncImage(url: imageURL) {
                    Circle().fill(DesignTokens.Colors.surfaceBase)
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())
                Text(name)
                    .font(DesignTokens.Typography.custom(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            .padding(.leading, 3)
            .padding(.trailing, DesignTokens.Spacing.sm)
            .padding(.vertical, 2)
            .background(DesignTokens.Colors.surfaceElevated, in: Capsule())
            .overlay {
                Capsule().strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help("\(name) 으로 이동")
    }
}
