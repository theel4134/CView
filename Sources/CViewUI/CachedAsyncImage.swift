// MARK: - CViewUI/CachedAsyncImage.swift
// 디스크 + 메모리 캐싱 지원 이미지 뷰

import SwiftUI
import AppKit
import CViewNetworking

/// AsyncImage 대체 — ImageCacheService를 통한 3단 캐시(메모리+디스크+디코딩)
/// NSImage 디코딩은 백그라운드에서 수행 — 렌더 패스에 Data→NSImage 변환 없음
/// `.utility` 태스크 우선순위 — UI 렌더링을 방해하지 않음
///
/// 최적화:
/// - 캐시 히트 시 즉시 표시 (애니메이션 없음) → 리사이즈/페이지 전환 시 깜빡임 방지
/// - 네트워크 로드 시 부드러운 페이드인 전환
/// - URL 변경 시 이전 이미지 유지하여 빈 프레임 방지
public struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder

    @State private var image: NSImage?
    /// 캐시 히트 여부 — true이면 애니메이션 없이 즉시 표시
    @State private var isCacheHit: Bool = false

    public init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium) // [GPU 최적화] 기본 bicubic → bilinear — 작은 아이콘에 충분
                    .aspectRatio(contentMode: .fill)
                    .transition(isCacheHit ? .identity : .opacity)
            } else {
                placeholder()
            }
        }
        .animation(isCacheHit ? nil : .easeIn(duration: 0.15), value: image != nil)
        .task(id: url, priority: .utility) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else { return }
        // nsImage(for:) → 디코딩 결과를 캐시에서 반환하거나 백그라운드 디코딩
        let decoded = await ImageCacheService.shared.nsImage(for: url)
        if !Task.isCancelled {
            // 캐시 히트 판별: 디코딩 캐시에 이미 있었으면 즉시 반환되므로
            // 이전에 image가 nil이었고 매우 빠르게 반환 → 캐시 히트
            let wasNil = image == nil
            isCacheHit = wasNil && decoded != nil
            self.image = decoded
        }
    }
}

// MARK: - Convenience Init (String URL)

extension CachedAsyncImage where Placeholder == Color {
    public init(urlString: String?) {
        self.init(url: urlString.flatMap { URL(string: $0) }) {
            Color.gray.opacity(0.2)
        }
    }
}
