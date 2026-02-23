// MARK: - CViewUI/CachedAsyncImage.swift
// 디스크 + 메모리 캐싱 지원 이미지 뷰

import SwiftUI
import AppKit
import CViewNetworking

/// AsyncImage 대체 — ImageCacheService를 통한 3단 캐시(메모리+디스크+디코딩)
/// NSImage 디코딩은 백그라운드에서 수행 — 렌더 패스에 Data→NSImage 변환 없음
/// `.utility` 태스크 우선순위 — UI 렌더링을 방해하지 않음
public struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder

    @State private var image: NSImage?

    public init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url, priority: .utility) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else { return }
        // nsImage(for:) → 디코딩 결과를 캐시에서 반환하거나 백그라운드 디코딩
        let decoded = await ImageCacheService.shared.nsImage(for: url)
        if !Task.isCancelled {
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
