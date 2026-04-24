// MARK: - WidgetCommon.swift
// 위젯 공통 helper: deep link URL, 썸네일 비동기 로더, 시간 포맷.

import SwiftUI
import CViewCore

enum WidgetDeepLink {
    static func live(channelId: String) -> URL {
        URL(string: "cview://live?channelId=\(channelId)")!
    }
    static let following = URL(string: "cview://following")!
    static let home = URL(string: "cview://home")!
}

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                default:
                    Color.gray.opacity(0.25)
                }
            }
        } else {
            Color.gray.opacity(0.25)
        }
    }
}

extension WidgetSnapshot {
    /// 스냅샷이 얼마나 오래된지 사람이 읽기 쉬운 표현 (예: "방금", "3분 전").
    var ageDescription: String {
        let seconds = Int(-generatedAt.timeIntervalSinceNow)
        if seconds < 30 { return "방금" }
        if seconds < 60 { return "\(seconds)초 전" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)분 전" }
        let hours = minutes / 60
        return "\(hours)시간 전"
    }
}
