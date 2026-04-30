// MARK: - FollowingSortOrder.swift
// FollowingView에서 사용하는 정렬 순서 enum (Refactor P1-6)

import Foundation
import CViewCore

enum FollowingSortOrder: String, CaseIterable, Identifiable {
    case liveFirst    = "라이브 우선"
    case viewers      = "시청자 많은 순"
    case nameAsc      = "채널명 가나다순"
    case original     = "기본 순서"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .liveFirst: return "dot.radiowaves.left.and.right"
        case .viewers:   return "person.2"
        case .nameAsc:   return "textformat.abc"
        case .original:  return "list.bullet"
        }
    }

    func sort(_ channels: [LiveChannelItem]) -> [LiveChannelItem] {
        switch self {
        case .liveFirst:
            return channels.sorted { lhs, rhs in
                if lhs.isLive != rhs.isLive { return lhs.isLive }
                return lhs.viewerCount > rhs.viewerCount
            }
        case .viewers:
            return channels.sorted { $0.viewerCount > $1.viewerCount }
        case .nameAsc:
            return channels.sorted { $0.channelName < $1.channelName }
        case .original:
            return channels
        }
    }
}
