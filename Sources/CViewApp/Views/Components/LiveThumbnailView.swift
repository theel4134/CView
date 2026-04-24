// MARK: - CViewApp/Views/Components/LiveThumbnailView.swift
// 라이브 채널 썸네일 뷰 — 45초 자동 갱신 + 메트릭 서버 통합

import SwiftUI
import CViewCore
import CViewNetworking

/// 라이브 채널 썸네일 전용 SwiftUI 뷰
///
/// - `refreshPolicy: .liveLoop` (기본): `LiveThumbnailService` 를 통해 45초마다 자동 갱신
/// - `refreshPolicy: .once`: 1회 fetch 후 자동 갱신 없음 (홈 추천/인기 그리드처럼 카드가 많은 곳)
/// - 이미지 갱신 시 부드러운 fade-in 트랜지션 적용
/// - 앱이 백그라운드(숨김/최소화)일 때 갱신 루프 자동 정지 → 복귀 시 즉시 재갱신
public struct LiveThumbnailView: View {

    /// 썸네일 갱신 정책.
    /// - `.liveLoop`: 45s TTL 마다 반복 갱신. 메인/Hero 카드 등 한 번에 1-2 개만 보일 때.
    /// - `.once`:     1회 fetch 후 정지. 홈의 그리드 카드처럼 동시에 10개 이상 떠 있을 때 권장.
    public enum RefreshPolicy: Sendable {
        case liveLoop
        case once
    }

    let channelId: String
    let thumbnailUrl: URL?
    var isLive: Bool
    var refreshPolicy: RefreshPolicy

    @State private var image: NSImage?
    @Environment(\.scenePhase) private var scenePhase

    public init(
        channelId: String,
        thumbnailUrl: URL?,
        isLive: Bool = true,
        refreshPolicy: RefreshPolicy = .liveLoop
    ) {
        self.channelId = channelId
        self.thumbnailUrl = thumbnailUrl
        self.isLive = isLive
        self.refreshPolicy = refreshPolicy
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high) // [HiDPI] Retina 다운스케일 선명도 (Lanczos 계열)
                    .antialiased(true)    // [HiDPI] 비정수 backing 비율(1.5x/2.5x)에서 가장자리 부드럽게
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
        .animation(DesignTokens.Animation.fadeIn, value: image != nil)
        // scenePhase를 ID에 포함 → 백그라운드(숨김/최소화) 시 task 취소, 복귀 시 즉시 재갱신
        .task(id: "\(channelId)_\(thumbnailUrl?.absoluteString ?? "")_\(isLive)_\(refreshPolicy)_\(scenePhase == .background)") {
            guard scenePhase != .background else { return }
            await loadLoop()
        }
    }

    // MARK: - Private

    private func loadLoop() async {
        await fetchAndApply()

        // 라이브가 아니거나 once 정책이면 1회 fetch 후 종료.
        // [Perf 2026-04-24] 홈 그리드처럼 카드가 많은 화면에서 매 45s 마다 N개의
        // task wakeup + image fade-in 동시 발생하던 부하 제거.
        guard isLive, refreshPolicy == .liveLoop else { return }

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
