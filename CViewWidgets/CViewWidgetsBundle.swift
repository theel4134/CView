// MARK: - CViewWidgetsBundle.swift
// macOS WidgetKit Extension entry point.
// 4개 위젯 (FollowingLiveList, SingleChannel, NowWatching, LiveCount) 등록.

import WidgetKit
import SwiftUI

@main
struct CViewWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FollowingLiveListWidget()
        SingleChannelWidget()
        NowWatchingWidget()
        LiveCountWidget()
    }
}
