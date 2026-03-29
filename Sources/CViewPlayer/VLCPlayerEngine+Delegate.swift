// VLCPlayerEngine+Delegate.swift
// CViewPlayer — VLCMediaPlayerDelegate (VLCKit 4.0)

import Foundation
import CViewCore
@preconcurrency import VLCKitSPM

// MARK: - VLCMediaPlayerDelegate (VLCKit 4.0)

extension VLCPlayerEngine: VLCMediaPlayerDelegate {

    /// 재생 상태 변경 — VLCKit 4.0: State를 직접 파라미터로 받음 (Notification 아님)
    ///
    /// [프레임 기반 버퍼링 필터링]
    /// VLC는 라이브 HLS 중 네트워크 버퍼를 채울 때 수시로 .buffering 상태를 보고하지만,
    /// 이 시점에도 프레임이 실제로 디코딩/표시되고 있을 수 있다.
    /// VLC가 .buffering을 보고해도 최근 프레임이 디코딩되었다면 상위 레이어에 전파하지 않는다.
    /// 이로써 "영상은 잘 나오는데 버퍼링 스피너가 계속 뜨는" 문제를 엔진 레벨에서 차단.
    public func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Log.player.debug("[DIAG] VLC stateChanged: \(newState.rawValue) (0=stopped,1=stopping,2=opening,3=buffering,4=error,5=playing,6=paused)")
        let phase: PlayerState.Phase
        switch newState {
        case .opening:
            phase = .loading
        case .buffering:
            // 프레임 기반 필터링: 이미 재생 중이었고 프레임이 디코딩되고 있으면
            // .buffering 상태를 상위에 전파하지 않는다 (VLC 내부 버퍼 리필일 뿐)
            // [수정] 누적값이 아닌 delta 비교 — 장시간 재생 후에도 정확 감지
            // [C1 fix] 시간 기반 override: delta>0 필터가 5초 이상 지속되면
            // 실제 버퍼링으로 간주하고 강제 전파 (CDN 403 시 VLC가 간헐적으로
            // 1-2프레임 디코딩하면서 무한 필터링 되는 것을 방지)
            if case .playing = _state.withLock({ $0.currentPhase }) {
                let decoded = player.media?.statistics.decodedVideo ?? 0
                let delta = decoded - _lastBufferingDecodedCount
                _lastBufferingDecodedCount = decoded
                if delta > 0 {
                    // 이전 체크 이후 새 프레임이 디코딩됨
                    let now = Date()
                    if let filterStart = _bufferingFilterStartTime {
                        if now.timeIntervalSince(filterStart) >= 3.0 {
                            // [Fix 16h-opt3] 5→3초: 실제 버퍼링 감지 2초 빨라짐
                            _bufferingFilterStartTime = nil
                        } else {
                            return  // 아직 5초 미만, 필터 유지
                        }
                    } else {
                        _bufferingFilterStartTime = now
                        return  // 최초 필터링, 타이머 시작
                    }
                } else {
                    // delta == 0: 프레임 디코딩 없음 → 필터 타이머 리셋 (진짜 버퍼링)
                    _bufferingFilterStartTime = nil
                }
            }
            phase = .buffering(progress: 0)
        case .playing:
            _bufferingFilterStartTime = nil  // C1: .playing 전이 시 필터 타이머 리셋
            phase = .playing
        case .paused:
            phase = .paused
        case .stopped, .stopping:
            phase = .idle
        case .error:
            phase = .error(.decodingFailed("VLC 재생 오류"))
        @unknown default:
            phase = .loading
        }
        _setPhase(phase)
    }

    /// 재생 위치 변경 — VLCKit 4.0: Notification 파라미터
    /// [스로틀링] VLC는 초당 10~30회 호출 → 멀티라이브 4세션 = 초당 40~120회
    /// 1초 미만 간격의 콜백은 무시하여 CPU 부하 대폭 감소
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - _lastTimeChangeNotify >= _timeChangeThrottleNs else { return }
        _lastTimeChangeNotify = now
        let t = TimeInterval(player.time.intValue) / 1000.0
        let d = TimeInterval(player.media?.length.intValue ?? 0) / 1000.0
        onTimeChange?(t, d)
    }

    /// 미디어 길이 확정 — VLCKit 4.0: Int64 직접 파라미터
    public func mediaPlayerLengthChanged(_ length: Int64) {
        let t = TimeInterval(player.time.intValue) / 1000.0
        let d = TimeInterval(length) / 1000.0
        onTimeChange?(t, d)
    }

    // MARK: - 트랙 Delegate

    public func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        let type = playerTrackType(trackType)
        onTrackEvent?(TrackEvent(trackId: trackId, trackType: type, kind: .added))
    }

    public func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
        let type = playerTrackType(trackType)
        onTrackEvent?(TrackEvent(trackId: trackId, trackType: type, kind: .removed))
    }

    public func mediaPlayerTrackUpdated(_ trackId: String, with trackType: VLCMedia.TrackType) {
        let type = playerTrackType(trackType)
        onTrackEvent?(TrackEvent(trackId: trackId, trackType: type, kind: .updated))
    }

    public func mediaPlayerTrackSelected(_ trackType: VLCMedia.TrackType, selectedId: String, unselectedId: String) {
        let type = playerTrackType(trackType)
        onTrackEvent?(TrackEvent(trackId: selectedId, trackType: type, kind: .selected(unselectedId: unselectedId)))
    }

    func playerTrackType(_ vlcType: VLCMedia.TrackType) -> PlayerTrackType {
        switch vlcType {
        case .audio: return .audio
        case .video: return .video
        case .text: return .text
        @unknown default: return .unknown
        }
    }
}
