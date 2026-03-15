// MARK: - ChannelInfoTabContent.swift
// CViewApp - 채널 상세 정보 탭 (정보 탭) 콘텐츠
// 라이브 카드, 통계 그리드, 채널 소개, 메모 카드, URL 공유, 최근 VOD/클립 미리보기

import SwiftUI
import CViewCore
import CViewUI

// MARK: - Info Tab Content

struct ChannelInfoTabContent: View {
    let channelInfo: ChannelInfo
    let liveInfo: LiveInfo?
    let liveUptime: TimeInterval
    let channelId: String
    let vodList: [VODInfo]
    let clipList: [ClipInfo]
    let hasMoreVODs: Bool
    let hasMoreClips: Bool

    @Binding var channelMemo: String
    @Binding var showMemoSheet: Bool
    @Binding var isDescExpanded: Bool
    @Binding var urlCopied: Bool
    @Binding var selectedTab: ChannelTab

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            // 라이브 방송 카드 (라이브 중일 때)
            if let live = liveInfo {
                liveCard(live)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 채널 통계 그리드
            statsGrid(channelInfo)
                .padding(.horizontal, DesignTokens.Spacing.lg)

            // 채널 소개
            if let desc = channelInfo.channelDescription, !desc.isEmpty {
                channelDescSection(desc)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 채널 메모 인라인 카드
            if !channelMemo.isEmpty {
                channelMemoCard
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 최근 VOD 미리보기
            if !vodList.isEmpty {
                recentVodPreview
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 최근 클립 미리보기
            if !clipList.isEmpty {
                recentClipPreview
                    .padding(.horizontal, DesignTokens.Spacing.lg)
            }

            // 채널 URL 공유 카드
            channelShareSection(channelId: channelInfo.channelId)
                .padding(.horizontal, DesignTokens.Spacing.lg)

            Spacer(minLength: DesignTokens.Spacing.xl)
        }
        .padding(.top, DesignTokens.Spacing.sm)
    }

    // MARK: - 라이브 방송 카드

    private func liveCard(_ live: LiveInfo) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // 섹션 헤더
            HStack(spacing: 6) {
                Circle().fill(DesignTokens.Colors.live).frame(width: 8, height: 8)
                Text("현재 방송 중")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                // 방송 시간
                if liveUptime > 0 {
                    Text(formatChannelUptime(liveUptime))
                        .font(DesignTokens.Typography.custom(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            Button {
                router.navigate(to: .live(channelId: channelId))
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    // 썸네일
                    ZStack(alignment: .bottomLeading) {
                        if let thumb = live.liveImageURL ?? live.defaultThumbnailImageURL {
                            CachedAsyncImage(url: thumb) {
                                Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                                    .overlay {
                                        Image(systemName: "play.tv")
                                            .font(DesignTokens.Typography.display)
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    }
                            }
                        } else {
                            Rectangle().fill(DesignTokens.Colors.surfaceElevated)
                                .overlay {
                                    Image(systemName: "play.tv")
                                        .font(DesignTokens.Typography.display)
                                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                                }
                        }
                        // 시청자 + LIVE 오버레이
                        HStack(spacing: 6) {
                            Text("LIVE")
                                .font(DesignTokens.Typography.custom(size: 9, weight: .black))
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                                .background(DesignTokens.Colors.live)
                                .clipShape(Capsule())

                            HStack(spacing: 3) {
                                Image(systemName: "person.fill")
                                    .font(DesignTokens.Typography.micro)
                                Text("\(formatChannelNumber(live.concurrentUserCount))명")
                                    .font(DesignTokens.Typography.custom(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                        }
                        .padding(DesignTokens.Spacing.xs)

                        // 재생 버튼 오버레이
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.4))
                                .frame(width: 52, height: 52)
                            Image(systemName: "play.fill")
                                .font(DesignTokens.Typography.headline)
                                .foregroundStyle(DesignTokens.Colors.textOnOverlay)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    .clipped()

                    // 방송 메타
                    VStack(alignment: .leading, spacing: 6) {
                        Text(live.liveTitle)
                            .font(DesignTokens.Typography.bodySemibold)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if let cat = live.liveCategoryValue ?? live.liveCategory {
                                Text(cat)
                                    .font(DesignTokens.Typography.captionMedium)
                                    .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                    .padding(.horizontal, DesignTokens.Spacing.xs)
                                    .padding(.vertical, DesignTokens.Spacing.xxs)
                                    .background(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            if live.adult {
                                Text("19+")
                                    .font(DesignTokens.Typography.micro)
                                    .foregroundStyle(DesignTokens.Colors.live)
                                    .padding(.horizontal, DesignTokens.Spacing.xs)
                                    .padding(.vertical, DesignTokens.Spacing.xxs)
                                    .background(DesignTokens.Colors.live.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }

                        // 태그
                        if !live.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(live.tags.prefix(8), id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(DesignTokens.Typography.footnoteMedium)
                                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                                            .padding(.horizontal, DesignTokens.Spacing.sm)
                                            .padding(.vertical, DesignTokens.Spacing.xxs)
                                            .background(DesignTokens.Colors.surfaceElevated)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.sm)
                    .background(DesignTokens.Colors.surfaceBase)
                }
                .background(DesignTokens.Colors.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                        .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 통계 그리드

    private func statsGrid(_ info: ChannelInfo) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("채널 통계")
                .font(DesignTokens.Typography.bodyBold)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: DesignTokens.Spacing.sm
            ) {
                channelStatCard(
                    icon: "person.2.fill",
                    label: "팔로워",
                    value: formatChannelNumber(info.followerCount),
                    color: DesignTokens.Colors.accentPurple
                )

                channelStatCard(
                    icon: liveInfo != nil ? "dot.radiowaves.left.and.right" : "moon.fill",
                    label: "방송 상태",
                    value: liveInfo != nil ? "라이브" : "오프라인",
                    color: liveInfo != nil ? DesignTokens.Colors.live : DesignTokens.Colors.textTertiary
                )

                channelStatCard(
                    icon: "person.fill",
                    label: "현재 시청",
                    value: liveInfo != nil ? "\(formatChannelNumber(liveInfo!.concurrentUserCount))명" : "-",
                    color: DesignTokens.Colors.chzzkGreen
                )

                channelStatCard(
                    icon: "play.rectangle.fill",
                    label: "VOD",
                    value: hasMoreVODs ? "\(vodList.count)+" : "\(vodList.count)개",
                    color: DesignTokens.Colors.accentBlue
                )

                channelStatCard(
                    icon: "scissors",
                    label: "클립",
                    value: hasMoreClips ? "\(clipList.count)+" : "\(clipList.count)개",
                    color: DesignTokens.Colors.accentOrange
                )

                if let live = liveInfo, let openDate = live.openDate {
                    let formatter = RelativeDateTimeFormatter()
                    let _ = formatter.unitsStyle = .abbreviated
                    channelStatCard(
                        icon: "clock.fill",
                        label: "방송 시작",
                        value: formatter.localizedString(for: openDate, relativeTo: Date()),
                        color: DesignTokens.Colors.warning
                    )
                } else if channelInfo.verifiedMark {
                    channelStatCard(
                        icon: "checkmark.seal.fill",
                        label: "인증",
                        value: "파트너",
                        color: DesignTokens.Colors.accentBlue
                    )
                } else {
                    channelStatCard(
                        icon: "checkmark.seal",
                        label: "인증",
                        value: "일반",
                        color: DesignTokens.Colors.textTertiary
                    )
                }
            }
        }
    }

    private func channelStatCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(DesignTokens.Typography.custom(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            Text(value)
                .font(DesignTokens.Typography.custom(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
        }
    }

    // MARK: - 채널 소개

    private func channelDescSection(_ desc: String) -> some View {
        let isLong = desc.count > 120
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("채널 소개")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                if isLong {
                    Button {
                        withAnimation(DesignTokens.Animation.fast) { isDescExpanded.toggle() }
                    } label: {
                        Text(isDescExpanded ? "접기" : "더 보기")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(desc)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(isLong && !isDescExpanded ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    // MARK: - 채널 메모 인라인 카드

    private var channelMemoCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
                Text("내 메모")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Button {
                    showMemoSheet = true
                } label: {
                    Text("편집")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            Text(channelMemo)
                .font(DesignTokens.Typography.captionMedium)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Colors.border, lineWidth: 0.5)
                }
        }
    }

    // MARK: - 채널 URL 공유 카드

    private func channelShareSection(channelId: String) -> some View {
        let url = "https://chzzk.naver.com/\(channelId)"
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                Text("채널 주소")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(url)
                    .font(DesignTokens.Typography.custom(size: 12, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    withAnimation(DesignTokens.Animation.fast) { urlCopied = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(DesignTokens.Animation.fast) { urlCopied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: urlCopied ? "checkmark" : "doc.on.doc")
                            .font(DesignTokens.Typography.caption)
                        Text(urlCopied ? "복사됨" : "복사")
                            .font(DesignTokens.Typography.captionMedium)
                    }
                    .foregroundStyle(urlCopied ? DesignTokens.Colors.chzzkGreen : DesignTokens.Colors.textSecondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background {
                        if urlCopied {
                            Capsule().fill(DesignTokens.Colors.chzzkGreen.opacity(0.12))
                        } else {
                            Capsule().fill(DesignTokens.Colors.surfaceElevated)
                        }
                    }
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }

    // MARK: - 최근 클립 미리보기

    private var recentClipPreview: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "scissors")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.accentOrange)
                Text("최근 클립")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Button {
                    withAnimation(DesignTokens.Animation.snappy) { selectedTab = .clip }
                } label: {
                    Text("전체 보기")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(clipList.prefix(5)) { clip in
                        EquatableCompactClipCard(clip: clip) {
                            router.navigate(to: .clip(clipUID: clip.clipUID))
                        }
                        .equatable()
                        .frame(width: 200)
                    }
                }
            }
        }
    }

    // MARK: - 최근 VOD 미리보기

    private var recentVodPreview: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.accentPurple)
                Text("최근 VOD")
                    .font(DesignTokens.Typography.bodyBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Button {
                    withAnimation(DesignTokens.Animation.snappy) { selectedTab = .vod }
                } label: {
                    Text("전체 보기")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(vodList.prefix(5)) { vod in
                        EquatableCompactVODCard(vod: vod) {
                            router.navigate(to: .vod(videoNo: vod.videoNo))
                        }
                        .equatable()
                        .frame(width: 200)
                    }
                }
            }
        }
    }
}
