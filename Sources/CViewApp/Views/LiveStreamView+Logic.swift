// MARK: - LiveStreamView+Logic.swift
// CViewApp - 스트림 시작/중지, PiP, 즐겨찾기, 시청기록, 라이브 상태 폴링, 메트릭 피드

import SwiftUI
import CViewCore
import CViewPlayer
import CViewChat
import CViewNetworking
import CViewMonitoring
import CViewPersistence

extension LiveStreamView {

    // MARK: - PiP

    func togglePiP() {
        guard let engine = playerVM?.mediaPlayer else { return }
        // PiP 컨트롤러에 콜백 주입
        PiPController.shared.onToggleMute = { playerVM?.toggleMute() }
        PiPController.shared.isMuted = playerVM?.isMuted ?? false
        PiPController.shared.onReturnToMain = nil  // bringToFront는 PiPController 내부에서 처리
        PiPController.shared.togglePiP(vlcEngine: engine, avEngine: nil, title: playerVM?.channelName ?? "PiP")
    }

    // MARK: - Stream + Chat Start

    func startStreamAndChat() async {
        guard !isLoadingStream else { return }

        // --- 새 창(분리 창) 케이스: 동일 채널이 이미 재생 중이면 엔진 재생성 없이 화면만 바인딩 ---
        // VLCVideoView.updateNSView가 makeNSView 시 이 창의 native view를 drawable로 자동 설정함
        if isDetachedWindow,
           let vm = playerVM,
           vm.streamPhase == .playing || vm.streamPhase == .buffering,
           vm.currentChannelId == channelId {
            isLoadingStream = false
            loadError = nil
            viewerCount = vm.viewerCount
            isFavorite = (try? await appState.dataStore?.isFavorite(channelId: channelId)) ?? false
            startLiveStatusPolling()
            startMetricsFeed()
            return
        }
        isLoadingStream = true
        loadError = nil

        do {
            // [2026-04-19] 분리 인스턴스(자식 프로세스) 대응:
            // 자식 프로세스가 막 부팅한 직후에는 `AppState.initialize(...)` 가 아직 완료되지
            // 않아 `appState.apiClient` 가 nil 일 수 있음. `.task(id: channelId)` 는 한 번만
            // 실행되므로 그 틈에 에러로 떨어지면 "다시 시도"를 눌러야만 재생이 시작됨.
            // → 최대 ~8s 동안 100ms 간격으로 초기화 완료를 기다림.
            // 추가로 `isAuthInitialized` 도 함께 대기 — 자식 프로세스는 자체 HTTPCookieStorage 를
            // 가지므로 authManager.initialize() 가 끝나 키체인 NID 쿠키가 복원되기 전에 채팅이
            // 연결되면 "로그인 필요" 상태로 뜬다.
            var waitIterations = 0
            while (appState.apiClient == nil || !appState.isAuthInitialized) && waitIterations < 80 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waitIterations += 1
            }
            guard let apiClient = appState.apiClient else {
                loadError = "API 클라이언트가 초기화되지 않았습니다."
                isLoadingStream = false
                return
            }

            // ─── P2: 프리페치 캐시 확인 — 호버 시 미리 가져온 결과 사용 ───
            let liveInfo: LiveInfo
            let streamURL: URL
            let channelName: String
            let liveTitle: String
            var prefetchedManifest: MasterPlaylist? = nil

            if let prefetched = await appState.hlsPrefetchService?.consumePrefetchedStream(channelId: channelId) {
                // 캐시 히트: API 호출 생략 (~400ms 절약)
                liveInfo = prefetched.liveInfo
                streamURL = prefetched.streamURL
                channelName = prefetched.channelName
                liveTitle = prefetched.liveTitle
                // [Opt: Single VLC] 프리페치 매니페스트도 전달 → variant 해석 네트워크 절약
                prefetchedManifest = prefetched.masterPlaylist
            } else {
                // 캐시 미스: 기존 경로로 liveDetail API 호출
                let info = try await apiClient.liveDetail(channelId: channelId)

                guard let playbackJSON = info.livePlaybackJSON,
                      let jsonData = playbackJSON.data(using: .utf8) else {
                    loadError = "재생 정보를 찾을 수 없습니다."
                    isLoadingStream = false
                    return
                }

                let playback = try JSONDecoder().decode(LivePlayback.self, from: jsonData)
                let media = playback.media.first { $0.mediaProtocol?.uppercased() == "HLS" }
                    ?? playback.media.first

                guard let mediaPath = media?.path,
                      let url = URL(string: mediaPath) else {
                    loadError = "HLS 스트림 URL을 찾을 수 없습니다."
                    isLoadingStream = false
                    return
                }

                liveInfo = info
                streamURL = url
                channelName = info.channel?.channelName ?? ""
                liveTitle = info.liveTitle
            }

            let ps = appState.settingsStore.player

            // ─── 영상 즉시 시작 + 로딩 오버레이 즉시 해제 ───
            let _prefetchedManifest = prefetchedManifest
            let _channelId = channelId
            let _apiClient = appState.apiClient
            Task { @MainActor in
                // 재생 직전 최신 설정의 엔진 타입 반영 (앱 실행 중 설정 변경 대응)
                playerVM?.preferredEngineType = ps.preferredEngine
                // 방송 종료 확인 콜백 설정 — 재연결 시 API로 라이브 상태 확인
                playerVM?.onCheckStreamEnded = { [weak _apiClient] in
                    guard let api = _apiClient else { return false }
                    do {
                        let status = try await api.liveStatus(channelId: _channelId)
                        return status.status == .close
                    } catch {
                        return false
                    }
                }
                // [No-Proxy] VLC 가 chzzk CDN 을 처리하지 못해 자동 폴백을 요청하면
                // AVPlayer 엔진으로 startStream() 을 재호출한다.
                // (preferredEngineType 은 PlayerViewModel 내부에서 .avPlayer 로 이미 전환됨)
                playerVM?.onEngineFallbackRequested = { @Sendable [weak playerVM] _ in
                    Task { @MainActor [weak playerVM] in
                        guard let vm = playerVM else { return }
                        await vm.stopStream()
                        await vm.startStream(
                            channelId: _channelId,
                            streamUrl: streamURL,
                            channelName: channelName,
                            liveTitle: liveTitle,
                            thumbnailURL: liveInfo.liveImageURL,
                            prefetchedManifest: _prefetchedManifest,
                            playerSettings: ps
                        )
                    }
                }
                isStreamOffline = false
                await playerVM?.startStream(
                    channelId: channelId,
                    streamUrl: streamURL,
                    channelName: channelName,
                    liveTitle: liveTitle,
                    thumbnailURL: liveInfo.liveImageURL,
                    prefetchedManifest: _prefetchedManifest,
                    playerSettings: ps
                )
                playerVM?.applySettings(volume: ps.volumeLevel, lowLatency: ps.lowLatencyMode, catchupRate: ps.catchupRate)
                playerVM?.applyForceHighestQuality(ps.forceHighestQuality)
                playerVM?.applySharpPixelScaling(ps.sharpPixelScaling)
            }
            isLoadingStream = false  // 영상 버퍼링은 VLC streamPhase 스피너가 처리

            // ─── 메트릭/시청기록 fire-and-forget (크리티컬 패스 외) ───
            let _channelName = channelName
            let _streamURL = streamURL
            Task { await appState.metricsForwarder?.activateChannel(channelId: channelId, channelName: _channelName, streamUrl: _streamURL.absoluteString) }

            // 엔진별 메트릭 콜백 연결 — 모든 재생 엔진의 메트릭을 서버로 전달
            let _forwarder = appState.metricsForwarder
            playerVM?.setVLCMetricsCallback { metrics in
                Task { await _forwarder?.updateVLCMetrics(metrics) }
            }
            playerVM?.setAVPlayerMetricsCallback { metrics in
                Task { await _forwarder?.updateAVPlayerMetrics(metrics) }
            }
            playerVM?.setHLSJSMetricsCallback { metrics in
                Task { await _forwarder?.updateHLSJSMetrics(metrics) }
            }

            // 서버 동기화 추천 → VLC 재생 속도 적용 콜백
            let _playerVM = playerVM
            Task {
                await _forwarder?.setSyncSpeedCallback { [weak _playerVM] speed in
                    Task { @MainActor [weak _playerVM] in _playerVM?.applySyncSpeed(speed) }
                }
                // [Fix 20] PID 활성 상태 콜백 — PID 능동 제어 중이면 서버 추천 무시
                await _forwarder?.setPIDActiveCallback { [weak _playerVM] in
                    guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return false }
                    return await coord.lowLatencyController?.isPIDActive ?? false
                }
                // [Fix 20 Phase3] PID 현재 배율 콜백 — Rate Arbiter 통합 속도 결정
                await _forwarder?.setPIDCurrentRateCallback { [weak _playerVM] in
                    guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return 1.0 }
                    return await coord.lowLatencyController?.currentRate ?? 1.0
                }
                // 현재 엔진의 목표 레이턴시를 서버 동기화 기준값으로 전달
                if let targetLatencyMs = _playerVM?.currentLatencyTargets()?.syncTargetMs {
                    await _forwarder?.setTargetLatency(targetLatencyMs)
                }
                // 레이턴시(ms) 콜백 — StreamCoordinator에서 직접 조회
                await _forwarder?.setLatencyMsCallback { [weak _playerVM] in
                    guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return 0 }
                    let latency = await coord.currentLatencySeconds() ?? 0
                    return latency * 1000
                }
                // 재생 위치(currentTime) 콜백 연결
                await _forwarder?.setCurrentTimeCallback { [weak _playerVM] in
                    await MainActor.run { _playerVM?.currentTime ?? 0 }
                }
                // PDT 기반 레이턴시 콜백 — StreamCoordinator에서 직접 조회 (초 단위)
                await _forwarder?.setPDTLatencyCallback { [weak _playerVM] in
                    guard let coord = await MainActor.run(body: { _playerVM?.streamCoordinator }) else { return nil }
                    if let latency = await coord.currentLatencySeconds() {
                        return latency
                    }
                    return nil
                }
            }

            Task { await recordWatch(channelName: _channelName, thumbnailURL: liveInfo.liveImageURL?.absoluteString, categoryName: liveInfo.liveCategoryValue) }

            // ─── 채팅 준비: 백그라운드에서 병렬 로드 (영상과 동시 진행) ───
            if let chatChannelId = liveInfo.chatChannelId {
                let _chatVM = chatVM

                // 캐시된 기본 이모티콘 즉시 적용 (API 로드 전에 사용 가능)
                let cachedMap = appState.cachedBasicEmoticonMap
                let cachedPacks = appState.cachedBasicEmoticonPacks
                if !cachedMap.isEmpty {
                    _chatVM?.channelEmoticons = cachedMap
                    _chatVM?.emoticonPacks = cachedPacks
                }

                Task { [isLoggedIn = appState.isLoggedIn, fallbackUid = appState.isLoggedIn ? appState.userChannelId : nil] in
                    do {
                        let tokenTask = Task { try await apiClient.chatAccessToken(chatChannelId: chatChannelId) }
                        let userTask  = Task<UserStatusInfo?, Never> {
                            guard isLoggedIn else { return nil }
                            return try? await apiClient.userStatus()
                        }
                        let packsTask = Task { await apiClient.basicEmoticonPacks(channelId: _channelId) }

                        let tokenInfo = try await tokenTask.value
                        let userInfo  = await userTask.value
                        let packs     = await packsTask.value
                        let (emoMap, loadedPacks) = await apiClient.resolveEmoticonPacks(packs)

                        // 채널별 이모티콘을 캐시된 기본 이모티콘과 병합
                        let mergedMap = cachedMap.merging(emoMap) { _, channel in channel }
                        let mergedPacks = cachedPacks + loadedPacks.filter { pack in
                            !cachedPacks.contains(where: { $0.id == pack.id })
                        }

                        Log.chat.info("채널 이모티콘: \(mergedMap.count)개 로드 완료 (팩 \(mergedPacks.count)개, 기본 \(cachedMap.count)개 포함)")
                        _chatVM?.channelEmoticons = mergedMap
                        _chatVM?.emoticonPacks = mergedPacks

                        let uid: String? = userInfo?.userIdHash ?? fallbackUid
                        if let uid { _chatVM?.currentUserUid = uid }
                        _chatVM?.currentUserNickname = userInfo?.nickname

                        await _chatVM?.connect(
                            chatChannelId: chatChannelId,
                            accessToken: tokenInfo.accessToken,
                            extraToken: tokenInfo.extraToken,
                            uid: uid,
                            channelId: _channelId
                        )
                    } catch {
                        Log.chat.error("채팅 연결 실패: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            isLoadingStream = false
        } catch {
            loadError = "스트림 로드 실패: \(error.localizedDescription)"
            Log.app.error("스트림 로드 실패: \(error.localizedDescription, privacy: .public)")
            isLoadingStream = false
        }
    }

    // MARK: - Favorite & Watch History

    func loadFavoriteStatus() async {
        guard let dataStore = appState.dataStore else { return }
        do {
            isFavorite = try await dataStore.isFavorite(channelId: channelId)
        } catch {
            Log.app.error("즐겨찾기 상태 로드 실패: \(error.localizedDescription)")
        }
    }

    func toggleFavorite() async {
        guard let dataStore = appState.dataStore else { return }
        do {
            if let apiClient = appState.apiClient {
                let channelInfo = try await apiClient.channelInfo(channelId: channelId)
                try await dataStore.saveChannel(channelInfo, isFavorite: !isFavorite)
            }
            isFavorite.toggle()
        } catch {
            Log.app.error("즐겨찾기 토글 실패: \(error.localizedDescription)")
        }
    }

    func recordWatch(channelName: String, thumbnailURL: String?, categoryName: String?) async {
        guard let dataStore = appState.dataStore else { return }
        do {
            if let apiClient = appState.apiClient {
                let info = try await apiClient.channelInfo(channelId: channelId)
                try await dataStore.saveChannel(info)
            }
            try await dataStore.updateLastWatched(channelId: channelId)

            // WatchHistory 기록 시작
            _ = try await dataStore.startWatchRecord(
                channelId: channelId,
                channelName: channelName,
                thumbnailURL: thumbnailURL,
                categoryName: categoryName
            )
            watchStartedAt = .now
        } catch {
            Log.app.error("시청 기록 저장 실패: \(error.localizedDescription)")
        }
    }

    func endWatchRecord() async {
        guard let dataStore = appState.dataStore, let startedAt = watchStartedAt else { return }
        do {
            try await dataStore.endWatchRecord(channelId: channelId, startedAt: startedAt)
        } catch {
            Log.app.error("시청 종료 기록 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - Live Status Polling

    func startLiveStatusPolling() {
        liveStatusTask?.cancel()
        liveStatusTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await pollLiveStatus()
            }
        }
    }

    private func pollLiveStatus() async {
        guard let apiClient = appState.apiClient else { return }
        do {
            let status = try await apiClient.liveStatus(channelId: channelId)
            viewerCount = status.concurrentUserCount
            if status.status == .close {
                isStreamOffline = true
                await playerVM?.stopStream()
            }
        } catch {
            Log.app.debug("방송 상태 폴링 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    var formattedViewerCount: String {
        if viewerCount >= 10_000 {
            return String(format: "%.1f만", Double(viewerCount) / 10_000.0)
        }
        return "\(viewerCount)"
    }
    
    func startMetricsFeed() {
        metricsFeedTask?.cancel()
        metricsFeedTask = Task { @MainActor in
            while !Task.isCancelled {
                // [최적화] 2초 → 5초: VLC statTimer(5초)와 동기화, actor hop 60% 감소
                // latency/buffer는 빠른 변동이 없으므로 5초 주기로 충분
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                if let vm = playerVM {
                    let latency = vm.latencyInfo?.current ?? 0
                    let bufferPct = vm.bufferHealth?.currentLevel ?? 0
                    await performanceMonitor.updateLatency(latency * 1000)
                    await performanceMonitor.updateBufferHealth(bufferPct * 100)
                }
            }
        }
    }
}
