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

    // MARK: - Recording

    /// 현재 스트림 녹화 시작
    /// - Parameter url: 녹화 파일 저장 경로
    func startRecording(to url: URL) async throws

    /// 녹화 중지
    func stopRecording() async

    /// 녹화 중 여부
    var isRecording: Bool { get }

    // MARK: - Health Check

    /// 엔진이 에러 상태인지 여부 (헬스체크 등에 사용)
    var isInErrorState: Bool { get }

    /// 재시도 카운터를 초기화합니다.
    func resetRetries()

    // MARK: - Track Events (VLCKit 4.0)

    /// 트랙 변경 콜백 — 트랙 추가/제거/업데이트/선택 변경 시 호출
    /// (trackId, trackType, event)
    var onTrackEvent: (@Sendable (TrackEvent) -> Void)? { get set }
}

// MARK: - Track Event Model

/// 플레이어 트랙 타입 (VLCKit 추상화)
public enum PlayerTrackType: String, Sendable {
    case audio
    case video
    case text
    case unknown
}

/// 트랙 이벤트 종류
public enum TrackEventKind: Sendable {
    case added
    case removed
    case updated
    case selected(unselectedId: String?)
}

/// 트랙 이벤트
public struct TrackEvent: Sendable {
    public let trackId: String
    public let trackType: PlayerTrackType
    public let kind: TrackEventKind

    public init(trackId: String, trackType: PlayerTrackType, kind: TrackEventKind) {
        self.trackId = trackId
        self.trackType = trackType
        self.kind = kind
    }
}

// MARK: - Recording Default Implementation

/// 녹화 미지원 엔진을 위한 기본 구현
public extension PlayerEngineProtocol {
    func startRecording(to url: URL) async throws {
        throw PlayerError.recordingFailed("이 엔진은 녹화를 지원하지 않습니다")
    }
    func stopRecording() async {}
    var isRecording: Bool { false }
}

/// 헬스체크 기본 구현 — 엔진별로 오버라이드 가능
public extension PlayerEngineProtocol {
    var isInErrorState: Bool { false }
    func resetRetries() {}
}

/// 트랙 이벤트 기본 구현 — 미지원 엔진용
public extension PlayerEngineProtocol {
    var onTrackEvent: (@Sendable (TrackEvent) -> Void)? {
        get { nil }
        set { _ = newValue }
    }
}

/// 플레이어 엔진 팩토리
public protocol PlayerEngineFactory: Sendable {
    func createEngine(type: PlayerEngineType) -> any PlayerEngineProtocol
}
