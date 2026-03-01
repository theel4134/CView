// MARK: - CViewApp/Views/Components/LiveThumbnailView.swift
// 라이브 채널 썸네일 뷰 — 45초 자동 갱신 + 메트릭 서버 통합

import SwiftUI
import CViewCore
import CViewNetworking

/// 라이브 채널 썸네일 전용 SwiftUI 뷰
///
/// - `isLive: true` 이면 `LiveThumbnailService`를 통해 45초마다 자동 갱신
/// - `isLive: false` 이면 일반 `ImageCacheService` 정적 캐시 사용
/// - 이미지 갱신 시 부드러운 fade-in 트랜지션 적용
/// - 앱이 백그라운드(숨김/최소화)일 때 갱신 루프 자동 정지 → 복귀 시 즉시 재갱신
public struct LiveThumbnailView: View {
    let channelId: String
    let thumbnailUrl: URL?
    var isLive: Bool

    @State private var image: NSImage?
    @Environment(\.scenePhase) private var scenePhase

    public init(channelId: String, thumbnailUrl: URL?, isLive: Bool = true) {
        self.channelId = channelId
        self.thumbnailUrl = thumbnailUrl
        self.isLive = isLive
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(DesignTokens.Colors.surfaceElevated)
                    .overlay {
                        Image(systemName: "play.tv")
                            .font(DesignTokens.Typography.custom(size: 16))
                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                    }
            }
        }
        .animation(.easeIn(duration: 0.25), value: image != nil)
        // scenePhase를 ID에 포함 → 백그라운드(숨김/최소화) 시 task 취소, 복귀 시 즉시 재갱신
        .task(id: "\(channelId)_\(thumbnailUrl?.absoluteString ?? "")_\(isLive)_\(scenePhase == .background)") {
            guard scenePhase != .background else { return }
            await loadLoop()
        }
    }

    // MARK: - Private

    private func loadLoop() async {
        await fetchAndApply()

        guard isLive else { return }

        // 라이브 중: 45초마다 갱신
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(LiveThumbnailService.liveThumbnailTTL))
            guard !Task.isCancelled else { break }
            await fetchAndApply()
        }
    }

    private func fetchAndApply() async {
        // thumbnailImage → 디코딩 마친 NSImage 반환 (백그라운드 디코딩)
        let decoded = await LiveThumbnailService.shared.thumbnailImage(
            channelId: channelId,
            fallbackUrl: thumbnailUrl
        )
        guard !Task.isCancelled else { return }
        if let decoded {
            image = decoded
        }
    }
}
