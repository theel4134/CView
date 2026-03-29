// MARK: - ResponsiveFollowingLayout.swift
// CViewApp - 팔로잉 화면 반응형 레이아웃 토큰
// 컨테이너 너비 기반 SizeClass → 모든 수치를 중앙 관리

import SwiftUI
import CViewCore

// ═══════════════════════════════════════════════════════════════════
// MARK: - Size Class
// ═══════════════════════════════════════════════════════════════════

enum FollowingSizeClass: Sendable, Hashable {
    /// < 400pt — 최소 폭 (1컬럼)
    case ultraCompact
    /// 400–599pt — 좁은 사이드바, 팝오버
    case compact
    /// 600–999pt — 기본 너비
    case regular
    /// ≥ 1000pt — 넓은 화면
    case expanded

    init(width: CGFloat) {
        switch width {
        case ..<400:  self = .ultraCompact
        case ..<600:  self = .compact
        case ..<1000: self = .regular
        default:      self = .expanded
        }
    }

    var isNarrow: Bool { self == .ultraCompact || self == .compact }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Responsive Following Layout
// ═══════════════════════════════════════════════════════════════════

struct ResponsiveFollowingLayout: Equatable {

    let sizeClass: FollowingSizeClass
    let containerWidth: CGFloat

    init(width: CGFloat) {
        self.containerWidth = width
        self.sizeClass = FollowingSizeClass(width: width)
    }

    // ─── 그리드 ───

    var liveColumnMinWidth: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 280
        case .compact:  return 200
        case .regular:  return 260
        case .expanded: return 300
        }
    }

    var liveColumnMaxWidth: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 500
        case .compact:  return 340
        case .regular:  return 400
        case .expanded: return 440
        }
    }

    var liveColumns: Int {
        if sizeClass == .ultraCompact { return 1 }
        return max(2, Int(floor(containerWidth / liveColumnMinWidth)))
    }

    var liveRowsPerPage: Int {
        switch sizeClass {
        case .ultraCompact: return 4
        case .compact:  return 3
        case .regular:  return 4
        case .expanded: return 4
        }
    }

    var offlineRowsPerPage: Int {
        switch sizeClass {
        case .ultraCompact: return 6
        case .compact:  return 8
        case .regular:  return 10
        case .expanded: return 12
        }
    }

    var liveItemsPerPage: Int { liveColumns * liveRowsPerPage }

    // ─── 헤더 ───

    var headerIconSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 32
        case .compact:  return 40
        case .regular:  return 52
        case .expanded: return 56
        }
    }

    var headerIconFontSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 14
        case .compact:  return 20
        case .regular:  return 24
        case .expanded: return 26
        }
    }

    var headerTitleFont: Font {
        switch sizeClass {
        case .ultraCompact: return .system(size: 14, weight: .semibold)
        case .compact:  return DesignTokens.Typography.headline
        case .regular:  return DesignTokens.Typography.title
        case .expanded: return DesignTokens.Typography.title
        }
    }

    var headerSubtitleSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 9
        case .compact:  return 10
        case .regular:  return 12
        case .expanded: return 13
        }
    }

    // ─── 카드 ───

    var cardInfoHeight: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 36
        case .compact:  return 38
        case .regular:  return 44
        case .expanded: return 46
        }
    }

    var liveProfileSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 22
        case .compact:  return 24
        case .regular:  return 28
        case .expanded: return 30
        }
    }

    var liveNameFontSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 10
        case .compact:  return 10.5
        case .regular:  return 11.5
        case .expanded: return 12
        }
    }

    var liveTitleFontSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 10
        case .compact:  return 10
        case .regular:  return 11
        case .expanded: return 12
        }
    }

    // ─── 오프라인 행 ───

    var offlineProfileSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 24
        case .compact:  return 28
        case .regular:  return 34
        case .expanded: return 36
        }
    }

    var offlineNameFontSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 10.5
        case .compact:  return 11
        case .regular:  return 12
        case .expanded: return 13
        }
    }

    var offlineRowHeight: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 34
        case .compact:  return 38
        case .regular:  return 44
        case .expanded: return 46
        }
    }

    // ─── 뱃지 (썸네일 오버레이) ───

    var badgeViewerEyeSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 6
        case .compact:  return 6
        case .regular:  return 7
        case .expanded: return 8
        }
    }

    var badgeViewerFontSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 8
        case .compact:  return 8
        case .regular:  return 9
        case .expanded: return 10
        }
    }

    var badgeCategoryFontSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 8
        case .compact:  return 8
        case .regular:  return 9
        case .expanded: return 10
        }
    }

    // ─── 섹션 & 칩 ───

    var sectionIconSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 9
        case .compact:  return 10
        case .regular:  return 11
        case .expanded: return 12
        }
    }

    var sectionCountSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 8
        case .compact:  return 9
        case .regular:  return 10
        case .expanded: return 11
        }
    }

    var chipLabelSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 9
        case .compact:  return 10
        case .regular:  return 11
        case .expanded: return 12
        }
    }

    var chipCountSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 7
        case .compact:  return 8
        case .regular:  return 9
        case .expanded: return 10
        }
    }

    // ─── 페이지 네비게이터 ───

    var pageChevronSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 8
        case .compact:  return 9
        case .regular:  return 10
        case .expanded: return 11
        }
    }

    var pageButtonSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 20
        case .compact:  return 22
        case .regular:  return 26
        case .expanded: return 28
        }
    }

    var pageTextSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 9
        case .compact:  return 10
        case .regular:  return 11
        case .expanded: return 12
        }
    }

    var pageIndicatorWidth: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 10
        case .compact:  return 12
        case .regular:  return 16
        case .expanded: return 18
        }
    }

    // ─── 스켈레톤 ───

    var skeletonProfileSize: CGFloat { liveProfileSize }

    var skeletonHeaderIconSize: CGFloat { headerIconSize }

    var skeletonHeaderTitleWidth: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 60
        case .compact:  return 80
        case .regular:  return 100
        case .expanded: return 120
        }
    }

    // ─── 빈 상태 / 게이트 ───

    var emptyOuterRingSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 48
        case .compact:  return 60
        case .regular:  return 72
        case .expanded: return 80
        }
    }

    var emptyInnerRingSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 32
        case .compact:  return 40
        case .regular:  return 48
        case .expanded: return 56
        }
    }

    var emptyIconSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 14
        case .compact:  return 16
        case .regular:  return 20
        case .expanded: return 22
        }
    }

    var gateOuterRingSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 52
        case .compact:  return 64
        case .regular:  return 80
        case .expanded: return 88
        }
    }

    var gateInnerRingSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 36
        case .compact:  return 44
        case .regular:  return 56
        case .expanded: return 64
        }
    }

    var gateIconSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 16
        case .compact:  return 20
        case .regular:  return 26
        case .expanded: return 28
        }
    }

    // ─── 정렬 메뉴 ───

    var sortIconSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 7
        case .compact:  return 8
        case .regular:  return 9
        case .expanded: return 10
        }
    }

    var sortChevronSize: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 5
        case .compact:  return 6
        case .regular:  return 7
        case .expanded: return 8
        }
    }

    // ─── 섹션 간격 ───

    var sectionSpacing: CGFloat {
        switch sizeClass {
        case .ultraCompact: return DesignTokens.Spacing.md
        case .compact:  return DesignTokens.Spacing.lg
        case .regular:  return DesignTokens.Spacing.xl
        case .expanded: return DesignTokens.Spacing.xxl
        }
    }

    var contentPadding: CGFloat {
        switch sizeClass {
        case .ultraCompact: return DesignTokens.Spacing.sm
        case .compact:  return DesignTokens.Spacing.md
        case .regular:  return DesignTokens.Spacing.xl
        case .expanded: return DesignTokens.Spacing.xxl
        }
    }

    var cardPadding: CGFloat {
        switch sizeClass {
        case .ultraCompact: return DesignTokens.Spacing.md
        case .compact:  return DesignTokens.Spacing.lg
        case .regular:  return DesignTokens.Spacing.xl
        case .expanded: return DesignTokens.Spacing.xl
        }
    }

    var gridSpacing: CGFloat {
        switch sizeClass {
        case .ultraCompact: return DesignTokens.Spacing.xs
        case .compact:  return DesignTokens.Spacing.sm
        case .regular:  return DesignTokens.Spacing.md
        case .expanded: return DesignTokens.Spacing.lg
        }
    }

    // ─── 멀티 라이브 패널 ───

    var chatSidebarWidth: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 120
        case .compact:  return 140
        case .regular:  return 180
        case .expanded: return 200
        }
    }

    var chatAddSheetWidth: CGFloat {
        switch sizeClass {
        case .ultraCompact: return 240
        case .compact:  return 280
        case .regular:  return 360
        case .expanded: return 400
        }
    }
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
