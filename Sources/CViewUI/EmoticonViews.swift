// MARK: - EmoticonViews.swift
// CViewUI - 이모티콘 렌더링 및 피커 컴포넌트

import SwiftUI
import AppKit
import CViewCore
import CViewNetworking

// MARK: - Flow Layout

/// 텍스트·이모티콘 토큰을 좌→우 → 다음 줄 방식으로 배치하는 Layout
/// SwiftUI Layout 프로토콜 사용 (macOS 13+)
private struct FlowLayout: Layout {
    var hSpacing: CGFloat = 0
    var vSpacing: CGFloat = 2

    // MARK: Layout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = compute(subviews: subviews, maxWidth: proposal.replacingUnspecifiedDimensions().width)
        return result.totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = compute(subviews: subviews, maxWidth: bounds.width)
        for (sv, frame) in zip(subviews, result.frames) {
            sv.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    // MARK: Private

    private struct ComputeResult {
        let totalSize: CGSize
        let frames: [CGRect]
    }

    private func compute(subviews: Subviews, maxWidth: CGFloat) -> ComputeResult {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var frames = Array(repeating: CGRect.zero, count: sizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        var lineStart = 0

        func commitLine(end: Int) {
            for j in lineStart..<end {
                frames[j].origin.y = y + (lineH - sizes[j].height) / 2
            }
        }

        for (i, sz) in sizes.enumerated() {
            if x > 0 && x + sz.width > maxWidth {
                commitLine(end: i)
                y += lineH + vSpacing
                x = 0; lineH = 0; lineStart = i
            }
            frames[i] = CGRect(x: x, y: y, width: sz.width, height: sz.height)
            x += sz.width + hSpacing
            lineH = max(lineH, sz.height)
        }
        commitLine(end: sizes.count)

        return ComputeResult(
            totalSize: CGSize(width: maxWidth, height: y + lineH),
            frames: frames
        )
    }
}

// MARK: - Animated GIF Image (NSViewRepresentable)

/// GIF 이모티콘을 애니메이션으로 재생하는 macOS 네이티브 뷰
/// ImageCacheService를 통해 데이터를 캐싱하여 재다운로드 방지
struct AnimatedGIFView: NSViewRepresentable {
    let url: URL
    let size: CGFloat

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        context.coordinator.currentTask?.cancel()

        context.coordinator.currentTask = Task(priority: .utility) {
            // ImageCacheService 경유 — 2회차부터 디스크/메모리 캐시에서 즉시 반환
            guard let data = await ImageCacheService.shared.imageData(for: url),
                  !Task.isCancelled,
                  let image = NSImage(data: data) else { return }
            await MainActor.run {
                nsView.image = image
                nsView.animates = true
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var currentTask: Task<Void, Never>?
    }
}

// MARK: - Emoticon Image View

/// 단일 이모티콘 이미지 렌더링 (정적 이미지는 CachedAsyncImage, GIF는 AnimatedGIFView)
public struct EmoticonImageView: View {
    let url: URL
    let size: CGFloat

    public init(url: URL, size: CGFloat = 24) {
        self.url = url
        self.size = size
    }

    public var body: some View {
        if url.pathExtension.lowercased() == "gif" {
            AnimatedGIFView(url: url, size: size)
                .frame(width: size, height: size)
        } else {
            CachedAsyncImage(url: url) {
                // placeholder
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(Color.secondary.opacity(0.12))
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Chat Content Renderer

/// 텍스트와 이모티콘이 혼합된 채팅 메시지를 렌더링
///
/// - 이모티콘이 없으면 `Text` 단독 경로(빠른 렌더)
/// - 이모티콘이 있으면 `FlowLayout` 기반 줄바꿈 흐름 렌더
public struct ChatContentRenderer: View {
    let content: String
    let emojis: [String: String]
    let fontSize: CGFloat

    private let parser = EmoticonParser()

    public init(content: String, emojis: [String: String] = [:], fontSize: CGFloat = 13) {
        self.content = content
        self.emojis = emojis
        self.fontSize = fontSize
    }

    public var body: some View {
        let segments = parser.parse(content: content, emojis: emojis)

        if segments.count == 1, case .text(let text) = segments.first {
            // 단순 텍스트 — 최적화 경로 (이모티콘 뷰/레이아웃 비용 없음)
            Text(text)
                .font(DesignTokens.Typography.custom(size: fontSize))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // 텍스트+이모티콘 혼합 — FlowLayout 줄바꿈
            FlowContentView(segments: segments, fontSize: fontSize)
        }
    }
}

// MARK: - Flow Content View (internal)

/// FlowLayout을 사용해 텍스트·이모티콘 세그먼트를 자연스럽게 배치
/// 각 텍스트 세그먼트를 단어 단위로 분리하여 줄바꿈 품질 향상
private struct FlowContentView: View {
    let segments: [ChatContentSegment]
    let fontSize: CGFloat

    // 단어 단위 + 이모티콘 토큰 (FlowLayout 배치용)
    private struct Token: Identifiable {
        let id: String
        enum Kind { case word(String), emoticon(URL) }
        let kind: Kind
    }

    private var tokens: [Token] {
        var result: [Token] = []
        for seg in segments {
            switch seg {
            case .text(let text):
                // 공백 기준으로 단어 분리 (trailing space 포함 → 자연스런 간격)
                var buf = ""
                for ch in text {
                    buf.append(ch)
                    if ch == " " {
                        if !buf.isEmpty {
                            result.append(Token(id: "w-\(result.count)", kind: .word(buf)))
                        }
                        buf = ""
                    }
                }
                if !buf.isEmpty {
                    result.append(Token(id: "w-\(result.count)", kind: .word(buf)))
                }
            case .emoticon(let id, let url):
                result.append(Token(id: "e-\(id)", kind: .emoticon(url)))
            }
        }
        return result
    }

    var body: some View {
        FlowLayout(hSpacing: 0, vSpacing: 2) {
            ForEach(tokens) { token in
                switch token.kind {
                case .word(let text):
                    Text(text)
                        .font(DesignTokens.Typography.custom(size: fontSize))
                        .fixedSize()
                case .emoticon(let url):
                    EmoticonImageView(url: url, size: floor(fontSize * 1.8))
                        .padding(.horizontal, DesignTokens.Spacing.xxs)
                }
            }
        }
    }
}

// WrappingHStack: 기존 호출부 호환을 위해 유지 (FlowContentView로 위임)
struct WrappingHStack: View {
    let segments: [ChatContentSegment]
    let fontSize: CGFloat

    var body: some View {
        FlowContentView(segments: segments, fontSize: fontSize)
    }
}

