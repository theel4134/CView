// MARK: - MLSplitVideoChat.swift
// 멀티라이브 비디오 + 채팅 영역을 NSSplitView로 물리적 분리
//
// [왜 NSSplitView인가?]
// VLC Metal/OpenGL 렌더링 서피스는 SwiftUI .clipped(), CALayer masksToBounds 등
// 일반적인 뷰 클리핑 메커니즘을 무시하고 부모 뷰 경계를 넘어 렌더링된다.
// NSSplitView는 macOS AppKit 네이티브 분할 컨테이너로, 각 split item이
// 완전히 독립된 NSView 클리핑 영역을 가지므로 Metal 렌더링 오버플로를 차단한다.

import SwiftUI
import AppKit

// MARK: - NSSplitView Wrapper

/// 비디오(좌)와 채팅(우)를 NSSplitView로 분리하는 NSViewRepresentable.
/// 채팅 패널 너비는 외부 Binding으로 제어하며 divider 드래그 시 동기화한다.
struct MLSplitVideoChat<VideoContent: View, ChatContent: View>: NSViewRepresentable {
    let videoContent: VideoContent
    let chatContent: ChatContent
    let chatWidth: CGFloat
    let showChat: Bool
    let onChatWidthChange: (CGFloat) -> Void

    init(
        chatWidth: CGFloat,
        showChat: Bool,
        onChatWidthChange: @escaping (CGFloat) -> Void,
        @ViewBuilder video: () -> VideoContent,
        @ViewBuilder chat: () -> ChatContent
    ) {
        self.videoContent = video()
        self.chatContent = chat()
        self.chatWidth = chatWidth
        self.showChat = showChat
        self.onChatWidthChange = onChatWidthChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChatWidthChange: onChatWidthChange)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true // 좌우 분할
        splitView.dividerStyle = .thin
        splitView.setDividerColor(.clear) // divider 숨김 — SwiftUI ChatResizeHandle 사용

        // 비디오 호스팅 뷰
        let videoHost = NSHostingView(rootView: videoContent)
        videoHost.translatesAutoresizingMaskIntoConstraints = false
        videoHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        videoHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 비디오를 감싸는 클리핑 컨테이너
        let videoContainer = ClippingSplitItem()
        videoContainer.addSubview(videoHost)
        NSLayoutConstraint.activate([
            videoHost.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            videoHost.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            videoHost.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            videoHost.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
        ])

        splitView.addArrangedSubview(videoContainer)

        // 채팅 호스팅 뷰
        let chatHost = NSHostingView(rootView: chatContent)
        chatHost.translatesAutoresizingMaskIntoConstraints = false
        chatHost.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        chatHost.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let chatContainer = ClippingSplitItem()
        chatContainer.addSubview(chatHost)
        NSLayoutConstraint.activate([
            chatHost.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            chatHost.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            chatHost.topAnchor.constraint(equalTo: chatContainer.topAnchor),
            chatHost.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor),
        ])

        splitView.addArrangedSubview(chatContainer)

        // holding priority — 리사이즈 시 비디오가 신축, 채팅은 고정
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)    // video: 낮은 우선순위 → 신축 대상
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)   // chat: 높은 우선순위 → 크기 유지

        // delegate
        splitView.delegate = context.coordinator
        context.coordinator.splitView = splitView

        // 초기 채팅 너비 설정
        if showChat {
            chatContainer.isHidden = false
        } else {
            chatContainer.isHidden = true
        }

        // 초기 layout — splitView가 window에 추가된 후 divider 위치 설정
        DispatchQueue.main.async {
            if showChat && splitView.bounds.width > 0 {
                context.coordinator.isProgrammaticResize = true
                splitView.setPosition(splitView.bounds.width - chatWidth, ofDividerAt: 0)
                context.coordinator.isProgrammaticResize = false
            }
        }

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        guard splitView.arrangedSubviews.count == 2 else { return }

        let videoContainer = splitView.arrangedSubviews[0]
        let chatContainer = splitView.arrangedSubviews[1]

        // SwiftUI 콘텐츠 업데이트
        if let videoHost = videoContainer.subviews.first as? NSHostingView<VideoContent> {
            videoHost.rootView = videoContent
        }
        if let chatHost = chatContainer.subviews.first as? NSHostingView<ChatContent> {
            chatHost.rootView = chatContent
        }

        // 채팅 표시/숨김
        let shouldShow = showChat
        let visibilityChanged = chatContainer.isHidden == shouldShow
        if visibilityChanged {
            context.coordinator.suppressWidthReport = true
            chatContainer.isHidden = !shouldShow
            splitView.adjustSubviews()
            context.coordinator.suppressWidthReport = false
        }

        // 채팅 너비 동기화
        // ⚠️ display cycle 재진입 방지: setPosition()을 다음 런루프로 지연
        // setPosition → constraint update → NSHostingView invalidation → SwiftUI 재렌더 → updateNSView 재진입 크래시 방지
        if shouldShow && !context.coordinator.pendingSetPosition {
            let currentChatWidth = chatContainer.frame.width
            let targetChatWidth = chatWidth
            if abs(currentChatWidth - targetChatWidth) > 1 && splitView.bounds.width > 0 {
                context.coordinator.pendingSetPosition = true
                DispatchQueue.main.async { [weak splitView, weak coordinator = context.coordinator] in
                    guard let splitView, let coordinator else { return }
                    coordinator.pendingSetPosition = false
                    // 아직 유효한 상태인지 재확인
                    guard splitView.arrangedSubviews.count == 2,
                          !splitView.arrangedSubviews[1].isHidden,
                          splitView.bounds.width > 0 else { return }
                    let actualChatWidth = splitView.arrangedSubviews[1].frame.width
                    guard abs(actualChatWidth - targetChatWidth) > 1 else { return }
                    coordinator.isProgrammaticResize = true
                    splitView.setPosition(splitView.bounds.width - targetChatWidth, ofDividerAt: 0)
                    coordinator.isProgrammaticResize = false
                }
            }
        }
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, NSSplitViewDelegate {
        weak var splitView: NSSplitView?
        var isDragging = false
        /// visibility 전환 중에는 임시 리사이즈의 chatWidth 보고를 억제
        var suppressWidthReport = false
        /// setPosition() 프로그래밍 리사이즈 시 피드백 루프 차단
        var isProgrammaticResize = false
        /// 이미 예약된 setPosition이 있는지 여부 — 중복 호출 방지
        var pendingSetPosition = false
        let onChatWidthChange: (CGFloat) -> Void

        init(onChatWidthChange: @escaping (CGFloat) -> Void) {
            self.onChatWidthChange = onChatWidthChange
        }

        // 비디오 영역 최소 너비
        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return 200
        }

        // 채팅 영역 최소 너비 (divider 최대 위치 = 전체 너비 - 200)
        @MainActor
        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            return splitView.bounds.width - 200
        }

        // 리사이즈 시 비디오 영역이 신축
        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            guard splitView.arrangedSubviews.count == 2 else {
                splitView.adjustSubviews()
                return
            }
            let videoView = splitView.arrangedSubviews[0]
            let chatView = splitView.arrangedSubviews[1]

            if chatView.isHidden {
                videoView.frame = splitView.bounds
            } else {
                let bounds = splitView.bounds
                let dividerThickness = splitView.dividerThickness
                // 채팅 너비를 유지하되 bounds를 초과하지 않도록 보정
                let chatW = min(max(chatView.frame.width, 200), bounds.width - 200 - dividerThickness)
                let videoW = bounds.width - chatW - dividerThickness
                videoView.frame = NSRect(x: 0, y: 0, width: videoW, height: bounds.height)
                chatView.frame = NSRect(x: videoW + dividerThickness, y: 0, width: chatW, height: bounds.height)
            }
        }

        func splitViewWillResizeSubviews(_ notification: Notification) {
            // 프로그래밍 리사이즈(setPosition)가 아닌 경우에만 isDragging 설정
            // (divider effectiveRect가 .zero이므로 사용자가 NSSplitView divider를 직접 드래그하는 경우는 없음)
            if !isProgrammaticResize {
                isDragging = true
            }
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView, splitView.arrangedSubviews.count == 2 else { return }
            let chatView = splitView.arrangedSubviews[1]
            // 피드백 루프 차단: 프로그래밍 리사이즈 및 visibility 전환 시 보고 억제
            if !chatView.isHidden && !suppressWidthReport && !isProgrammaticResize {
                onChatWidthChange(chatView.frame.width)
            }
            // 프로그래밍 리사이즈가 아닌 경우에만 isDragging 해제
            if !isProgrammaticResize {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.isDragging = false
                }
            }
        }

        // divider hit-test 영역을 0으로 — SwiftUI ChatResizeHandle이 대신 처리
        func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
            return .zero
        }
    }
}

// MARK: - ClippingSplitItem

/// NSSplitView의 각 영역에 사용되는 강제 클리핑 NSView.
/// layer.masksToBounds + clipsToBounds 이중 보장.
private final class ClippingSplitItem: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.isOpaque = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.masksToBounds = true
    }
}

// MARK: - NSSplitView Extension

private extension NSSplitView {
    func setDividerColor(_ color: NSColor) {
        // NSSplitView에서 divider 색상 변경은 subclass가 필요하지만
        // 여기서는 divider를 투명하게 만들고 SwiftUI handle을 사용하므로
        // effectiveRect를 .zero로 반환하여 hitTest에서 제외
    }
}
