// MARK: - LiveResponsiveBreakpoints.swift
// CViewApp - Live/MultiLive 화면의 폭 기반 반응형 룰 (L-1 / 2026-04-30)
//
// 디자인 문서(`live-menu-final-design-source-2026-04-28.md`)의 860/1080/1320pt 분기점을
// 코드로 형식화. 채팅 패널 폭·표시 모드 자동 선택, 사이드 패널 강제 hide, 스테이지 우선
// strategy 등에서 단일 source-of-truth 로 참조한다.
//
// 사용 예:
//   let bp = LiveBreakpoint(width: containerSize.width)
//   chatPanelMaxRatio = bp.chatMaxRatio
//   defaultChatWidth   = bp.defaultChatWidth

import CoreGraphics
import Foundation

/// 라이브 화면(단일/멀티)의 컨테이너 폭 분기점.
///
/// - `compact`  : ~860pt 미만 — 노트북/사이드패널 좁힘 상태. 스테이지 우선,
///                채팅은 overlay 권장, side 모드 시 최대 30%.
/// - `regular`  : 860 ~ 1080pt — 13"/14" 노트북 표준. 사이드 채팅 280pt 권장.
/// - `wide`     : 1080 ~ 1320pt — 외장 모니터 일반. 사이드 채팅 320pt.
/// - `xwide`    : 1320pt 이상 — 27"+ / 멀티모니터. 사이드 채팅 360pt.
public enum LiveBreakpoint: Sendable, Equatable {
    case compact
    case regular
    case wide
    case xwide

    /// 디자인 문서 분기점.
    public static let compactMax: CGFloat = 860
    public static let regularMax: CGFloat = 1080
    public static let wideMax: CGFloat = 1320

    public init(width: CGFloat) {
        if width < Self.compactMax { self = .compact }
        else if width < Self.regularMax { self = .regular }
        else if width < Self.wideMax { self = .wide }
        else { self = .xwide }
    }

    /// 사이드 채팅 권장 기본 폭 (saved 값 없을 때).
    public var defaultChatWidth: CGFloat {
        switch self {
        case .compact: return 260
        case .regular: return 280
        case .wide:    return 320
        case .xwide:   return 360
        }
    }

    /// 사이드 채팅이 컨테이너 폭에서 차지할 수 있는 최대 비율.
    /// compact 에서는 스테이지 우선이라 더 좁게 제한.
    public var chatMaxRatio: CGFloat {
        switch self {
        case .compact: return 0.30
        case .regular: return 0.40
        case .wide:    return 0.45
        case .xwide:   return 0.50
        }
    }

    /// 사이드 채팅이 컨테이너 폭에서 차지할 수 있는 최소 폭.
    public var chatMinWidth: CGFloat { 120 }

    /// compact 진입 시 side 채팅을 자동으로 overlay 로 폴백할지 여부.
    /// (기본: true — 스테이지 우선 strategy)
    public var prefersStageOverChat: Bool { self == .compact }

    /// 사람-읽기 라벨 (디버그/UI 표기용).
    public var label: String {
        switch self {
        case .compact: return "compact"
        case .regular: return "regular"
        case .wide:    return "wide"
        case .xwide:   return "xwide"
        }
    }

    /// 주어진 컨테이너 폭에서 채팅 폭을 [chatMinWidth, chatMaxRatio*width] 로 클램프.
    public func clampChatWidth(_ requested: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let upper = max(chatMinWidth, containerWidth * chatMaxRatio)
        return min(max(requested, chatMinWidth), upper)
    }
}
