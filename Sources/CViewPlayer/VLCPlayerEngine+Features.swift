// MARK: - VLCPlayerEngine+Features.swift
// CViewPlayer — drawable 재바인딩, 재사용, 녹화, 메트릭 수집

import Foundation
import QuartzCore
import CViewCore
@preconcurrency import VLCKitSPM

extension VLCPlayerEngine {
    
    // MARK: - drawable 재바인딩

    /// 마지막 drawable refresh 시각 — 500ms 쿨다운으로 중복 vout 재생성 방지
    private static let _drawableRefreshCooldown: TimeInterval = 0.5

    /// VLC drawable을 nil → playerView 순서로 강제 리셋하여 vout 재생성을 트리거한다.
    /// 500ms 쿨다운: 멀티라이브에서 buffering→playing 사이클 + recoverFromBackground 등
    /// 여러 경로에서 중복 호출되어 검은 프레임이 반복 발생하는 것을 방지한다.
    /// force=true: 쿨다운을 무시하고 강제 리셋 (세션 추가/그리드 재구성 시)
    public func refreshDrawable(force: Bool = false) {
        let doRefresh = { [weak self] in
            guard let self else { return }
            let now = Date()
            if !force,
               let last = self._lastDrawableRefreshTime,
               now.timeIntervalSince(last) < Self._drawableRefreshCooldown {
                return  // 쿨다운 중 — 중복 refresh 스킵
            }
            self._lastDrawableRefreshTime = now
            // [플리커 방지] CATransaction으로 drawable 스왕을 원자적으로 처리 —
            // nil→playerView 사이의 CA 레이어 변경이 단일 프레임에 커밋되어
            // 중간 검은 프레임 노출을 최소화한다.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.player.drawable = nil
            self.player.drawable = self.playerView
            CATransaction.commit()
        }
        if Thread.isMainThread {
            doRefresh()
        } else {
            DispatchQueue.main.async { doRefresh() }
        }
    }

    /// VLC vout 파이프라인 강제 재생성.
    /// refreshDrawable()만으로 부족할 때 — 비디오 트랙을 순환(deselect → select)하여
    /// samplebufferdisplay 모듈을 완전히 파괴 후 재생성한다.
    public func forceVoutRecovery() {
        let doRecovery = { [weak self] in
            guard let self else { return }
            guard self.playerView.window != nil else { return }
            let state = self.player.state
            guard state != .stopped && state != .stopping else { return }
            let wasPlaying = state == .playing || state == .buffering || state == .opening

            self.player.drawable = nil
            self.player.drawable = self.playerView

            guard !self.player.videoTracks.isEmpty else { return }
            self.player.deselectAllVideoTracks()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, !self.player.videoTracks.isEmpty else { return }
                let state = self.player.state
                guard state != .stopped && state != .stopping else { return }
                self.player.selectTrack(at: 0, type: .video)
                if wasPlaying && (state == .paused || !self.player.isPlaying) {
                    self.player.play()
                }
            }
        }
        if Thread.isMainThread {
            doRecovery()
        } else {
            DispatchQueue.main.async { doRecovery() }
        }
    }

    // MARK: - 재사용 지원

    /// 에러 상태 여부 (PlayerEngineProtocol)
    public var isInErrorState: Bool {
        if case .error = _state.withLock({ $0.currentPhase }) { return true }
        return false
    }

    public func resetRetries() {}

    /// 풀 반납 전 엔진 초기화
    public func resetForReuse() {
        playTask?.cancel()
        _startPlayRetryTask?.cancel()
        _startPlayRetryTask = nil
        statsTask?.cancel()
        statsTask = nil
        let p = player
        let pv = playerView
        let doStop = { [weak self] in
            self?._prevStats = nil
            self?._bufferingFilter.withLock { $0 = _BufferingFilterState() }
            self?._zeroFrameCount = 0
            self?._qualityDegradeCount = 0
            self?._qualityStableCount = 0
            self?._ioHealthEWMA = 1.0
            self?._frameDeliveryEWMA = 1.0
            p.delegate = nil
            p.stop()
            p.drawable = nil
            pv.layer?.sublayers?.forEach { sub in
                if sub !== pv.layer { sub.removeFromSuperlayer() }
            }
            self?._setPhase(.idle)
            p.delegate = self
        }
        if Thread.isMainThread {
            doStop()
        } else {
            DispatchQueue.main.async { doStop() }
        }
        onStateChange = nil
        onTimeChange = nil
        onVLCMetrics = nil
        onTrackEvent = nil
        onQualityAdaptationRequest = nil
        onPlaybackStalled = nil
        streamingProfile = .multiLive
        isSelectedSession = true
        sessionTier = .active
    }

    /// 비디오 트랙 활성화/비활성화
    public func setVideoTrackEnabled(_ enabled: Bool) {
        if enabled {
            if !player.videoTracks.isEmpty {
                player.selectTrack(at: 0, type: .video)
            } else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                    if !self.player.videoTracks.isEmpty {
                        self.player.selectTrack(at: 0, type: .video)
                    }
                }
            }
        } else {
            player.deselectAllVideoTracks()
        }
    }

    /// 멀티라이브 GPU 렌더 계층만 조정 (디코딩/프로파일 변경 없음).
    /// `updateSessionTier()` 는 프로파일·트랙·타이밍까지 변경하므로 quality-lock 모드에서
    /// 호출하지 않는다. 이 메서드는 compositor 단의 contentsScale / isHidden 만 수정하여
    /// 디코딩 품질과 완전히 독립적인 GPU 절감을 제공한다.
    public func setGPURenderTier(_ tier: SessionTier) {
        let doApply = { [weak self] in
            self?.playerView.setGPURenderTier(tier)
        }
        if Thread.isMainThread { doApply() }
        else { DispatchQueue.main.async { doApply() } }
    }

    // MARK: - 3-Tier 세션 계층 관리

    /// 멀티라이브 세션 계층을 업데이트하여 리소스를 동적으로 배분한다.
    ///
    /// - `.active`: 선택된 세션 — 풀 해상도(1080p), 정상 통계 수집
    /// - `.visible`: 보이지만 비선택 — 저해상도(480p), 축소된 통계/타이밍
    /// - `.hidden`: 화면 밖 — 비디오 트랙 비활성화로 디코딩/렌더링 CPU 제거
    ///
    /// hidden → visible/active 전환 시 비디오 트랙 재활성화 (키프레임 대기 0.5~2초)
    public func updateSessionTier(_ newTier: SessionTier) {
        let oldTier = sessionTier
        guard oldTier != newTier else { return }
        sessionTier = newTier

        // isSelectedSession도 동기화
        isSelectedSession = (newTier == .active)

        // [HQ 프로파일] 멀티라이브 계열인 경우, 선택 세션은 multiLiveHQ로 자동 승격
        // (프로파일 변경은 다음 play()/switchMedia() 미디어 옵션에 반영된다.
        //  runtime timing 설정은 아래에서 즉시 반영.)
        let oldProfile = streamingProfile
        if streamingProfile.isMultiLiveFamily {
            streamingProfile = (newTier == .active) ? .multiLiveHQ : .multiLive
        }
        let profileChanged = (oldProfile != streamingProfile)

        let doUpdate = { [weak self] in
            guard let self else { return }
            let state = self.player.state
            guard state != .stopped && state != .stopping else { return }

            // [GPU] tier 변경마다 compositor 렌더 스케일/가시성 동기 업데이트
            // (디코딩 경로와 독립이므로 state 체크 이후에도 항상 안전하게 적용)
            self.playerView.setGPURenderTier(newTier)

            switch newTier {
            case .active:
                // Tier 1: 비디오 트랙 활성화 + 정상 타이밍 복원
                if oldTier == .hidden {
                    self.setVideoTrackEnabled(true)
                }
                self.player.minimalTimePeriod = 500_000  // 기본값 복원
                self.player.timeChangeUpdateInterval = 1.0

                // 통계 수집 주기 정상화
                self.startStatsTimer()
                Log.player.info("[Tier] → active: video ON, timing normal, profile=\(String(describing: self.streamingProfile))")

                // [Quality 2026-04-18] multiLive → multiLiveHQ 승격 시 미디어 옵션
                //   (:adaptive-maxheight 등) 이 재생 중에는 변경되지 않으므로,
                //   현재 재생 중인 URL로 switchMedia() 를 호출하여 새 옵션을 반영한다.
                //   짧은 검은 화면(~300ms)을 감수하고 1080p 변종 선택을 즉시 가능하게 한다.
                if profileChanged, let url = self.player.media?.url {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        Log.player.info("[Tier] HQ 프로파일 승격 → switchMedia 재로드")
                        await self.switchMedia(to: url)
                    }
                }

            case .visible:
                // Tier 2: 비디오 유지 + 축소 타이밍
                if oldTier == .hidden {
                    self.setVideoTrackEnabled(true)
                }
                self.player.minimalTimePeriod = 1_000_000  // 1초
                self.player.timeChangeUpdateInterval = 5.0

                // 통계 수집 주기 축소
                self.startStatsTimer()
                Log.player.info("[Tier] → visible: video ON, timing reduced")

            case .hidden:
                // Tier 3: 비디오 트랙 비활성화 → VideoToolbox 세션 중단 + 렌더링 제거
                self.setVideoTrackEnabled(false)
                self.player.minimalTimePeriod = 2_000_000  // 2초
                self.player.timeChangeUpdateInterval = 10.0

                // 통계 수집 중단 (비가시 세션에 불필요)
                self.statsTask?.cancel()
                self.statsTask = nil
                Log.player.info("[Tier] → hidden: video OFF, stats stopped")
            }
        }

        if Thread.isMainThread {
            doUpdate()
        } else {
            DispatchQueue.main.async { doUpdate() }
        }
    }

    /// 백그라운드 모드 시 통계 수집 주기 조절 + 오디오 디코딩 비활성화
    /// [Opt-A4] 추가로 VLC 내부 타이머(minimalTimePeriod/timeChangeUpdateInterval)를
    /// 배경 세션일 때 축소하여 델리게이트 콜백/라이브러리 내부 타임 워커 부하 절감.
    public func setTimeUpdateMode(background: Bool) {
        if background {
            statsTask?.cancel()
            statsTask = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 배경: VLC 내부 타이머 최대한 느슨하게 — 시간 델리게이트 호출 거의 없음
                self.player.minimalTimePeriod = 2_000_000   // 2s
                self.player.timeChangeUpdateInterval = 10.0 // 10s
                self.player.deselectAllAudioTracks()
            }
        } else {
            startStatsTimer()
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 전경 복귀: 프로파일/선택 상태에 맞게 타이밍 복원
                if self.streamingProfile.isMultiLiveFamily {
                    if self.streamingProfile == .multiLiveHQ || self.isSelectedSession {
                        self.player.minimalTimePeriod = 500_000
                        self.player.timeChangeUpdateInterval = 1.0
                    } else {
                        self.player.minimalTimePeriod = 1_000_000
                        self.player.timeChangeUpdateInterval = 5.0
                    }
                } else {
                    self.player.minimalTimePeriod = 500_000
                    self.player.timeChangeUpdateInterval = 1.0
                }
                if !self.player.audioTracks.isEmpty {
                    self.player.selectTrack(at: 0, type: .audio)
                    self.player.currentAudioPlaybackDelay = 0
                }
            }
        }
    }

    // MARK: - 녹화

    public var isRecording: Bool { _state.withLock { $0.isRecording } }

    public func startRecording(to url: URL) async throws {
        guard !_state.withLock({ $0.isRecording }) else { return }
        player.startRecording(atPath: url.path)
        _state.withLock { $0.isRecording = true }
    }

    public func stopRecording() async {
        guard _state.withLock({ $0.isRecording }) else { return }
        player.stopRecording()
        _state.withLock { $0.isRecording = false }
    }

    public func captureSnapshot() -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let name = "snapshot_\(Int(Date().timeIntervalSince1970)).png"
        let url = dir.appendingPathComponent(name)
        player.saveVideoSnapshot(at: url.path, withWidth: 0, andHeight: 0)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - 버퍼 상태

    /// [Fix 21] 복합 버퍼 건강도 — 프레임 비율 기반 + I/O/전달 경고 보호
    /// 정상 상태: frameRatio만 사용 (기존 동작, false-conservative 방지)
    /// I/O 또는 프레임 전달률 < 0.5: min() 보수적 보호 활성화
    @MainActor
    public func bufferHealth() -> BufferHealth {
        guard let stats = player.media?.statistics else {
            return BufferHealth(currentLevel: 0, targetLevel: 1.0, isHealthy: true)
        }
        let displayed = max(Int(stats.displayedPictures), 0)
        let decoded   = max(Int(stats.decodedVideo), 1)
        let lost      = max(Int(stats.lostPictures), 0)
        let ratio     = Float(displayed) / Float(decoded)
        let isBuffering = player.state == .buffering
        let isHealthy   = displayed > 0 && lost == 0 && !isBuffering
        
        let frameRatio = Double(ratio)
        let minAuxiliary = min(_ioHealthEWMA, _frameDeliveryEWMA)
        let compositeLevel: Double
        if minAuxiliary < 0.5 {
            // I/O 또는 프레임 전달 위험 → 보수적 min() 보호
            compositeLevel = min(frameRatio, minAuxiliary)
        } else {
            // 정상 → frameRatio만 사용 (불필요한 가속 억제 방지)
            compositeLevel = frameRatio
        }
        
        return BufferHealth(currentLevel: compositeLevel, targetLevel: 1.0, isHealthy: isHealthy)
    }

    // MARK: - 오디오 트랙

    public func audioTracks() -> [(Int, String)] {
        return player.audioTracks.enumerated().map { (i, t) in (i, t.trackName) }
    }

    public func setAudioTrack(_ index: Int) {
        player.selectTrack(at: index, type: .audio)
    }

    // MARK: - Private Helpers

    func _setPhase(_ phase: PlayerState.Phase) {
        let isDuplicate = (_lastEmittedPhase == phase)
        _state.withLock { $0.currentPhase = phase }
        guard !isDuplicate else { return }
        _lastEmittedPhase = phase
        onStateChange?(phase)
    }

    func startStatsTimer() {
        statsTask?.cancel()
        // [CPU 최적화] 단일 5s → 10s, 멀티 10s → 15s
        // [Power-Aware] 배터리 사용 시 1.5배 올려 추가 절전 (E-core 친화적)
        // — VLC 통계 수집은 player.media?.statistics 접근 시 내부 뮤텍스 경합 가능
        // — PerformanceMonitor가 별도 10s 주기로 시스템 메트릭 수집 중이므로 중복 줄임
        // 비선택 멀티라이브만 15s, 선택(HQ) 세션은 표준 10s 수집
        let baseSecs: Double = (streamingProfile == .multiLive) ? 15 : 10
        let scaledSecs = PowerAwareInterval.scaled(baseSecs)
        let interval: UInt64 = UInt64(scaledSecs * 1_000_000_000)
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) } catch { break }
                guard !Task.isCancelled, let self else { break }
                await self.collectMetrics()
            }
        }
    }

    @MainActor
    func collectMetrics() {
        // [장시간 안정성] playing 상태가 아닌 경우 VLC 통계 접근 스킵
        // buffering/opening 상태에서 player.media?.statistics 접근 시
        // VLC 내부 뮤텍스 경합으로 MainThread 블로킹 가능 (4세션 × 10초 반복 → 누적)
        let currentPhase = _state.withLock { $0.currentPhase }
        // [Fix] .playing뿐 아니라 .buffering에서도 메트릭 수집 허용
        // VLC 라이브 HLS는 프레임 디코딩 중에도 .buffering 상태를 유지하는 경우가 많음
        // player.media?.statistics 접근은 media가 존재하면 안전 (guard let stats로 확인)
        switch currentPhase {
        case .playing, .buffering:
            break  // OK — 통계 수집 진행
        default:
            _zeroFrameCount = 0
            return
        }
        guard let stats = player.media?.statistics else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(_lastMetricsTime)
        _lastMetricsTime = now

        let prev = _prevStats
        _prevStats = stats

        guard let prev else { return }

        let droppedDelta = Int(stats.lostPictures) - Int(prev.lostPictures)
        let decodedDelta = Int(stats.decodedVideo) - Int(prev.decodedVideo)
        let audioLostDelta = Int(stats.lostAudioBuffers) - Int(prev.lostAudioBuffers)
        let lateDelta = Int(stats.latePictures) - Int(prev.latePictures)
        let demuxCorruptDelta = Int(stats.demuxCorrupted) - Int(prev.demuxCorrupted)
        let demuxDiscDelta = Int(stats.demuxDiscontinuity) - Int(prev.demuxDiscontinuity)
        let decodedAudioDelta = Int(stats.decodedAudio) - Int(prev.decodedAudio)
        let displayedDelta = Int(stats.displayedPictures) - Int(prev.displayedPictures)
        let playedAudioDelta = Int(stats.playedAudioBuffers) - Int(prev.playedAudioBuffers)
        let readBytesDelta = Int(stats.readBytes) - Int(prev.readBytes)
        let demuxReadBytesDelta = Int(stats.demuxReadBytes) - Int(prev.demuxReadBytes)

        // [VLC 4.0] readBytes가 불변인 경우 demuxReadBytes를 대역폭 기준으로 사용
        // VLC 4.0은 HLS 라이브 스트림에서 readBytes를 더 이상 갱신하지 않음
        let effectiveBytesDelta = readBytesDelta > 0 ? readBytesDelta : demuxReadBytesDelta
        let netBytesPerSec = elapsed > 0 ? max(0, effectiveBytesDelta) / Int(max(elapsed, 0.001)) : 0
        let inputKbps = elapsed > 0 ? Double(max(0, effectiveBytesDelta)) * 8.0 / elapsed / 1000.0 : 0.0
        let demuxKbps = elapsed > 0 ? Double(max(0, demuxReadBytesDelta)) * 8.0 / elapsed / 1000.0 : 0.0
        let fps = elapsed > 0 ? Double(max(0, decodedDelta)) / elapsed : 0.0

        // [Fix 20 Phase3] I/O 건강도 EWMA 갱신
        // VLC 4.0: readBytes 불변 시 frameDelivery만으로 판단 (ioRatio 갱신 스킵)
        if readBytesDelta > 0, demuxReadBytesDelta > 100 {
            let ioRatio = min(Double(readBytesDelta) / Double(demuxReadBytesDelta), 1.5)
            _ioHealthEWMA = 0.3 * min(ioRatio, 1.0) + 0.7 * _ioHealthEWMA
        }
        
        // [Fix 20 Phase3] 프레임 전달률 EWMA 갱신: (표시 프레임) / (디코딩 프레임)
        // 손실/지연 프레임 반영 → 버퍼 부족 시 즉각 감지
        if decodedDelta > 0 {
            let delivery = Double(max(0, displayedDelta)) / Double(decodedDelta)
            let lossPenalty = (droppedDelta + lateDelta) > 0 ? 0.8 : 1.0
            let effectiveDelivery = min(delivery * lossPenalty, 1.0)
            _frameDeliveryEWMA = 0.3 * effectiveDelivery + 0.7 * _frameDeliveryEWMA
        }

        let size = player.videoSize
        if size != _cachedVideoSize {
            _cachedVideoSize = size
            let w = size.width, h = size.height
            _cachedResolutionString = w > 0 && w.isFinite && h.isFinite ? "\(Int(w))x\(Int(h))" : nil
        }
        let resolution = _cachedResolutionString

        let metrics = VLCLiveMetrics(
            fps: fps,
            droppedFramesDelta: max(0, droppedDelta),
            decodedFramesDelta: max(0, decodedDelta),
            networkBytesPerSec: max(0, netBytesPerSec),
            inputBitrateKbps: inputKbps,
            demuxBitrateKbps: demuxKbps,
            resolution: resolution,
            videoWidth: Double(size.width),
            videoHeight: Double(size.height),
            playbackRate: player.rate,
            bufferHealth: bufferHealth().currentLevel,
            lostAudioBuffersDelta: max(0, audioLostDelta),
            decodedAudioDelta: max(0, decodedAudioDelta),
            playedAudioBuffersDelta: max(0, playedAudioDelta),
            readBytesDelta: max(0, effectiveBytesDelta),
            demuxReadBytesDelta: max(0, demuxReadBytesDelta),
            displayedPicturesDelta: max(0, displayedDelta),
            latePicturesDelta: max(0, lateDelta),
            demuxCorruptedDelta: max(0, demuxCorruptDelta),
            demuxDiscontinuityDelta: max(0, demuxDiscDelta)
        )
        onVLCMetrics?(metrics)

        // [Opt-B3] 통계 기반 자동 화질 적응
        // 프레임 드롭/지연이 급증하면 downgrade 요청, 안정적이면 upgrade 요청
        // (함수 진입 시 .playing 가드 통과했으므로 바로 호출)
        evaluateQualityAdaptation(
            droppedDelta: droppedDelta,
            lateDelta: lateDelta,
            decodedDelta: decodedDelta,
            demuxCorruptDelta: demuxCorruptDelta
        )

        // 재생 정체 감지
        if decodedDelta <= 0 {
            _zeroFrameCount += 1
            if _zeroFrameCount >= _zeroFrameStallThreshold {
                _zeroFrameCount = 0
                onPlaybackStalled?()
            }
        } else {
            _zeroFrameCount = 0
        }
    }

    // MARK: - 통계 기반 화질 적응

    /// 프레임 드롭/지연 통계를 분석하여 StreamCoordinator에 화질 변경을 요청한다.
    /// - 연속 3회 이상 프레임 품질 저하 → downgrade 요청
    /// - 연속 4회 안정 → upgrade 요청 (더 빠른 원본 복귀)
    @MainActor
    func evaluateQualityAdaptation(
        droppedDelta: Int,
        lateDelta: Int,
        decodedDelta: Int,
        demuxCorruptDelta: Int
    ) {
        // hidden 세션에서는 화질 적응 불필요
        guard sessionTier != .hidden else { return }

        // [Quality Lock] 항상 최고 화질 모드: downgrade/upgrade 모두 무시
        // (1080p60 고정 유지 — 프레임 드롭은 VLC가 자체 처리)
        guard !forceHighestQuality else {
            _qualityDegradeCount = 0
            _qualityStableCount = 0
            return
        }

        // [Quality] 임계값 완화: 일시적 네트워크 지터에 의한 불필요한 강등 방지
        let isDropping = droppedDelta > 8 || lateDelta > 12
        let isCorrupted = demuxCorruptDelta > 0
        let isStarved = decodedDelta <= 0

        if isDropping || isCorrupted || isStarved {
            _qualityStableCount = 0
            _qualityDegradeCount += 1
            // [Quality] 연속 3회 불량 샘플 후 강등 (기존 2회 → 3회)
            if _qualityDegradeCount >= 3 {
                _qualityDegradeCount = 0
                let reason: String
                if isStarved { reason = "decode_stall" }
                else if isCorrupted { reason = "demux_corrupt(\(demuxCorruptDelta))" }
                else { reason = "frame_loss(drop=\(droppedDelta),late=\(lateDelta))" }
                Log.player.warning("[QualityAdapt] ⬇ downgrade: \(reason)")
                onQualityAdaptationRequest?(.downgrade(reason: reason))
            }
        } else {
            _qualityDegradeCount = 0
            _qualityStableCount += 1
            // [Quality] 4회 연속 안정 → 빠른 원본 복귀 (기존 6회 → 4회, 단일=20초, 멀티=40초)
            if _qualityStableCount >= 4 {
                _qualityStableCount = 0
                Log.player.info("[QualityAdapt] ⬆ upgrade: stable_\(self.streamingProfile == .multiLive ? "40s" : "20s") profile=\(String(describing: self.streamingProfile))")
                onQualityAdaptationRequest?(.upgrade(reason: "stable"))
            }
        }
    }
}
