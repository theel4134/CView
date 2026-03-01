// MARK: - ChannelVODClipTab.swift
// CViewApp - 채널 상세 정보 VOD/클립 탭 전체 목록 뷰

import SwiftUI
import CViewCore
import CViewUI

// MARK: - VOD Tab

struct ChannelVODTab: View {
    let vodList: [VODInfo]
    let hasMoreVODs: Bool
    let isLoadingMore: Bool
    let onLoadMore: () async -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("전체 VOD")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(hasMoreVODs ? "\(vodList.count)+" : "\(vodList.count)개")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            if vodList.isEmpty && !isLoadingMore {
                ChannelInfoEmptyState(icon: "play.rectangle", message: "VOD가 없습니다")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: DesignTokens.Spacing.md)],
                    spacing: DesignTokens.Spacing.md
                ) {
                    ForEach(vodList) { vod in
                        VODCard(vod: vod) {
                            router.navigate(to: .vod(videoNo: vod.videoNo))
                        }
                        .onAppear {
                            if vod.id == vodList.last?.id { Task { await onLoadMore() } }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)

                if isLoadingMore {
                    ChannelInfoLoadMoreIndicator()
                }
            }

            Spacer(minLength: DesignTokens.Spacing.xl)
        }
        .padding(.top, DesignTokens.Spacing.sm)
    }
}

// MARK: - Clip Tab

struct ChannelClipTab: View {
    let clipList: [ClipInfo]
    let hasMoreClips: Bool
    let isLoadingMore: Bool
    let onLoadMore: () async -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("전체 클립")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(hasMoreClips ? "\(clipList.count)+" : "\(clipList.count)개")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)

            if clipList.isEmpty && !isLoadingMore {
                ChannelInfoEmptyState(icon: "scissors", message: "클립이 없습니다")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: DesignTokens.Spacing.md)],
                    spacing: DesignTokens.Spacing.md
                ) {
                    ForEach(clipList) { clip in
                        ClipCard(clip: clip) {
                            router.navigate(to: .clip(clipUID: clip.clipUID))
                        }
                        .onAppear {
                            if clip.id == clipList.last?.id { Task { await onLoadMore() } }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)

                if isLoadingMore {
                    ChannelInfoLoadMoreIndicator()
                }
            }

            Spacer(minLength: DesignTokens.Spacing.xl)
        }
        .padding(.top, DesignTokens.Spacing.sm)
    }
}

// MARK: - Shared Components

struct ChannelInfoEmptyState: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.display)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
            Text(message)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

struct ChannelInfoLoadMoreIndicator: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}
