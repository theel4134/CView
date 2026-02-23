// MARK: - CViewCore/Protocols/PlayerEngineProtocol.swift
// 플레이어 엔진 프로토콜 — VLC / AVPlayer 추상화

import Foundation
import AppKit

/// 플레이어 엔진 프로토콜 — 모든 엔진 공통 인터페이스
/// @unchecked Sendable class 또는 actor 모두 채택 가능
public protocol PlayerEngineProtocol: AnyObject, Sendable {
    /// 현재 재생 중인지 여부
    var isPlaying: Bool { get }

    /// 현재 시간
    var currentTime: TimeInterval { get }

    /// 총 시간
    var duration: TimeInterval { get }

    /// 현재 재생 속도
    var rate: Float { get }

    /// 재생 시작
    func play(url: URL) async throws

    /// 일시 정지
    func pause()

    /// 재개
    func resume()

    /// 정지
    func stop()

    /// 특정 위치로 이동
    func seek(to position: TimeInterval)

    /// 재생 속도 변경
    func setRate(_ rate: Float)

    /// 볼륨 변경
    func setVolume(_ volume: Float)

    /// 비디오 렌더링 뷰 (NSViewRepresentable 통합용)
    var videoView: NSView { get }
}

/// 플레이어 엔진 팩토리
public protocol PlayerEngineFactory: Sendable {
    func createEngine(type: PlayerEngineType) -> any PlayerEngineProtocol
}
