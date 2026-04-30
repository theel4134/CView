// MARK: - ResponsiveFollowingLayout.swift
// CViewApp - 팔로잉 화면 반고정형 레이아웃 토큰
// 카드 고정폭 320pt 기준 — 열 수만 컨테이너 너비에 따라 자동 계산

import SwiftUI
import CViewCore

// ═══════════════════════════════════════════════════════════════════
// MARK: - Semi-Fixed Following Layout
// ═══════════════════════════════════════════════════════════════════

struct ResponsiveFollowingLayout: Equatable {

    let containerWidth: CGFloat

    init(width: CGFloat) {
        self.containerWidth = width
    }

    // ─── 그리드 (반고정) ───

    /// 카드 고정 기준폭 — 열 수 계산에 사용
    static let liveCardWidth: CGFloat = 320

    /// 컨테이너 너비 ÷ 320pt → 열 수 자동 계산
    var liveColumns: Int {
        max(1, Int(floor(containerWidth / Self.liveCardWidth)))
    }

    let liveRowsPerPage: Int = 4
    var liveItemsPerPage: Int { liveColumns * liveRowsPerPage }
    let offlineRowsPerPage: Int = 10

    // ─── 간격 ───

    let gridSpacing: CGFloat = DesignTokens.Spacing.md       // 12pt
    let sectionSpacing: CGFloat = DesignTokens.Spacing.xl    // 24pt
    let contentPadding: CGFloat = DesignTokens.Spacing.xl    // 24pt
    let cardPadding: CGFloat = DesignTokens.Spacing.xl       // 24pt

    // ─── 헤더 ───

    let headerIconSize: CGFloat = 52
    let headerIconFontSize: CGFloat = 24
    let headerTitleFont: Font = DesignTokens.Typography.title
    let headerSubtitleSize: CGFloat = 12

    // ─── 라이브 카드 ───

    let cardInfoHeight: CGFloat = 44
    let liveProfileSize: CGFloat = 28
    let liveNameFontSize: CGFloat = 11.5
    let liveTitleFontSize: CGFloat = 11

    // ─── 오프라인 행 ───

    let offlineProfileSize: CGFloat = 34
    let offlineNameFontSize: CGFloat = 12
    let offlineRowHeight: CGFloat = 44

    // ─── 뱃지 (썸네일 오버레이) ───

    let badgeViewerEyeSize: CGFloat = 7
    let badgeViewerFontSize: CGFloat = 9
    let badgeCategoryFontSize: CGFloat = 9

    // ─── 섹션 & 칩 ───

    let sectionIconSize: CGFloat = 11
    let sectionCountSize: CGFloat = 10
    let chipLabelSize: CGFloat = 11
    let chipCountSize: CGFloat = 9

    // ─── 페이지 네비게이터 ───

    let pageChevronSize: CGFloat = 10
    let pageButtonSize: CGFloat = 26
    let pageTextSize: CGFloat = 11
    let pageIndicatorWidth: CGFloat = 16

    // ─── 스켈레톤 ───

    var skeletonProfileSize: CGFloat { liveProfileSize }
    var skeletonHeaderIconSize: CGFloat { headerIconSize }
    let skeletonHeaderTitleWidth: CGFloat = 100

    // ─── 빈 상태 / 게이트 ───

    let emptyOuterRingSize: CGFloat = 72
    let emptyInnerRingSize: CGFloat = 48
    let emptyIconSize: CGFloat = 20
    let gateOuterRingSize: CGFloat = 80
    let gateInnerRingSize: CGFloat = 56
    let gateIconSize: CGFloat = 26

    // ─── 정렬 메뉴 ───

    let sortIconSize: CGFloat = 9
    let sortChevronSize: CGFloat = 7

    // ─── 라이브 아바타 스트립 ───

    let liveAvatarSize: CGFloat = 60
    let liveAvatarRingWidth: CGFloat = 2.5
    let liveAvatarNameFontSize: CGFloat = 10.5
    let liveAvatarSpacing: CGFloat = 16
    let liveAvatarViewerFontSize: CGFloat = 9

    var liveAvatarItemWidth: CGFloat {
        liveAvatarSize + liveAvatarRingWidth * 2 + 8
    }

    // ─── 멀티 라이브 패널 ───

    let chatSidebarWidth: CGFloat = 180
    let chatAddSheetWidth: CGFloat = 360
}

// MARK: - Aliases used by FollowingCardViews

extension ResponsiveFollowingLayout {
    var viewerIconSize: CGFloat { badgeViewerEyeSize }
    var viewerFontSize: CGFloat { badgeViewerFontSize }
    var categoryFontSize: CGFloat { badgeCategoryFontSize }
    var cardProfileSize: CGFloat { liveProfileSize }
    var cardNameFontSize: CGFloat { liveNameFontSize }
    var offlineInfoFontSize: CGFloat { offlineNameFontSize }
}
