// StreamCoordinator+LowLatency.swift
// CView_v2 — Low Latency Sync & PDT Provider

import Foundation
import CViewCore

extension StreamCoordinator {

    /// PDT 모니터링만 시작 (PID 제어 없음) — 멀티라이브 레이턴시 측정용
    func startPDTMonitoring() async {
        let mediaPlaylistURL = await resolveMediaPlaylistURL()
        guard let mediaPlaylistURL else {
            logger.info("PDT monitoring: Media playlist URL unavailable")
            return
        }
        let provider = PDTLatencyProvider(playlistURL: mediaPlaylistURL)
        await provider.start()
        pdtProvider = provider

        // PDT 초기 안정화 대기 (최대 6초)
        for _ in 0..<6 {
            if await provider.isReady { break }
            try? await Task.sleep(for: .seconds(1))
        }
        logger.info("PDT monitoring active (no PID): \(mediaPlaylistURL.lastPathComponent, privacy: .public)")
    }

    func startLowLatencySync() async {
        guard let controller = lowLatencyController else { return }
        
        await controller.setOnRateChange { [weak self] rate in
            Task { [weak self] in
                await self?.playerEngine?.setRate(Float(rate))
            }
        }

        // 매 측정마다 latencyUpdate 이벤트 발행 → PlayerViewModel.latencyInfo 갱신
        await controller.setOnLatencyMeasured { [weak self] current, ewma, target in
            Task { [weak self] in
                let info = LatencyInfo(current: current, target: target, ewma: ewma)
                await self?.emitEvent(.latencyUpdate(info))
            }
        }

        // 버퍼 건강도 제공 — PID 가속 댐핑에 사용
        // [Fix 25B] Mutex 기반 thread-safe 접근
        await controller.setBufferHealthProvider { [weak self] in
            guard let self else { return 1.0 }
            return self._bufferState.withLock { $0.bufferHealth }
        }
        
        await controller.setOnSeekRequired { [weak self] targetLatency in
            Task { [weak self] in
                guard let engine = await self?.playerEngine else { return }
                // 라이브 HLS에서 duration = 버퍼 내 총 길이, currentTime = 현재 위치
                // targetLatency초 뒤에서 재생하려면 버퍼 끝(duration)에서 빼기
                // VLC 내부 디코더 파이프라인 지연(~1s) 고려하여 약간 앞으로 seek
                let vlcPipelineDelay: TimeInterval = 1.0
                let seekTarget = engine.duration - max(targetLatency - vlcPipelineDelay, 1.0)
                if seekTarget > 0 {
                    engine.seek(to: seekTarget)
                }
            }
        }
        
        // Method A: 미디어 플레이리스트 URL 확보 (마스터 플레이리스트 파싱)
        // loadManifestInfo가 백그라운드 Task이므로 직접 fetch해서 타이밍 문제 해결
        let mediaPlaylistURL = await resolveMediaPlaylistURL()
        
        if let mediaPlaylistURL {
            let provider = PDTLatencyProvider(playlistURL: mediaPlaylistURL)
            await provider.start()
            pdtProvider = provider
            
            // PDT 초기 안정화 대기 (최대 6초, 값이 준비되면 즉시 진행)
            for _ in 0..<6 {
                if await provider.isReady { break }
                try? await Task.sleep(for: .seconds(1))
            }
            
            logger.info("PDT sync active: \(mediaPlaylistURL.lastPathComponent, privacy: .public)")
            
            await controller.startSync { [weak provider, weak self] in
                // [Fix 21] 실제 체감 레이턴시 = PDT(보정됨) + VLC 버퍼 지연(스무딩)
                if let pdtLatency = await provider?.currentLatency() {
                    let bufferDelay = await self?.smoothedVlcBufferLatency() ?? 0
                    return pdtLatency + bufferDelay
                }
                // Fallback: VLC 버퍼 스무딩 레이턴시 (PDT 없을 때)
                return await self?.smoothedVlcBufferLatency()
            }
        } else {
            // 마스터 플레이리스트 fetch 실패 - VLC 버퍼 fallback
            logger.info("Media playlist URL unavailable, using VLC buffer latency")
            await controller.startSync { [weak self] in
                await self?.smoothedVlcBufferLatency()
            }
        }
    }
    
    /// 마스터 플레이리스트에서 첫 번째 미디어 플레이리스트 URL을 가져옴
    /// 이미 파싱된 경우 즉시 반환, 없으면 _streamURL에서 직접 fetch
    func resolveMediaPlaylistURL() async -> URL? {
        // 이미 파싱된 경우 즉시 반환
        if let url = _masterPlaylist?.variants.first?.uri {
            return url
        }
        // 직접 fetch
        guard let streamURL = _streamURL else { return nil }
        do {
            var request = URLRequest(url: streamURL)
            request.setValue(
                CommonHeaders.safariUserAgent,
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue(CommonHeaders.chzzkReferer, forHTTPHeaderField: "Referer")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            let (data, _) = try await hlsSession.data(for: request)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            if content.contains("#EXT-X-STREAM-INF") {
                let master = try hlsParser.parseMasterPlaylist(content: content, baseURL: streamURL)
                // 파싱 결과로 내부 상태도 업데이트 (loadManifestInfo 중복 방지 효과)
                if _masterPlaylist == nil {
                    await updateMasterPlaylist(master)
                }
                return master.variants.first?.uri
            } else if content.contains("#EXTINF") {
                // 이미 미디어 플레이리스트인 경우
                return streamURL
            }
        } catch {
            logger.warning("Master playlist fetch failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }
    
    /// VLC 내부 버퍼 기반 레이턴시 (PDT 없을 때 fallback)
    func vlcBufferLatency() async -> TimeInterval? {
        guard let engine = playerEngine else { return nil }
        guard engine.isPlaying else { return nil }
        let duration = engine.duration
        let current = engine.currentTime
        guard duration > 0, current > 0 else { return nil }
        let latency = duration - current
        guard latency > 0, latency < 60 else { return nil }
        return latency
    }
    
    /// [Fix 21] EWMA 스무딩된 VLC 버퍼 레이턴시 — 톱니파 노이즈 제거
    /// 세그먼트 도착/소비에 따른 duration 급변을 완화하여 PID 입력 안정화
    func smoothedVlcBufferLatency() async -> TimeInterval? {
        guard let raw = await vlcBufferLatency() else { return _vlcBufferEWMA }
        if let prev = _vlcBufferEWMA {
            _vlcBufferEWMA = 0.3 * raw + 0.7 * prev
        } else {
            _vlcBufferEWMA = raw
        }
        return _vlcBufferEWMA
    }
}
