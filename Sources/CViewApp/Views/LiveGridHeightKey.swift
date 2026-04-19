// MARK: - LiveGridHeightKey.swift
// FollowingView 라이브 그리드의 동적 높이 측정용 PreferenceKey (Refactor P1-6)

import SwiftUI

struct LiveGridHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
