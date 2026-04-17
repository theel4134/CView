// MARK: - MultiLiveManager.swift
// CViewApp — 통합 엔진 풀 기반 멀티라이브 세션 매니저
// 최대 4개 채널 동시 시청, 각 세션은 독립 PlayerViewModel(VLC/AVPlayer) + ChatViewModel

import Foundation
import SwiftUI
import CViewCore
import CViewNetworking
import CViewPlayer
import CViewPersistence
import CViewMonitoring

// MARK: - Multi Live Manager

@Observable
@MainActor
public final class MultiLiveManager {

    // MARK: - Constants

    static let maxSessions = 4

    /// 설정 기반 최대 세션 수
    var effectiveMaxSessions: Int {
        settingsStore?.multiLive.maxConcurrentSessions ?? Self.maxSessions
    }

    // MARK: - State

    var sessions: [MultiLiveSession] = []
    var selectedSessionId: UUID?
    var isGridLayout: Bool = false

    // MARK: - 그리드/오디오 확장 상태 (MultiLiveSessionManager 병합)
    var gridLayoutMode: MultiLiveGridLayoutMode = .preset
    var layoutRatios: MultiLiveLayoutRatios = MultiLiveLayoutRatios()
    var draggingSessionIndex: Int? = nil
    var audioSessionId: UUID?
    var isMultiAudioMode: Bool = false
    var audioEnabledSessionIds: Set<UUID> = []

    /// 현재 추가 중인 채널 ID 세트 (중복 추가 방지)
    private var addingChannelIds: Set<String> = []
    private var removingSessionIds: Set<UUID> = []  // [Fix 24A] 중복 제거 방지 가드

    /// 앱 종료 중 플래그 — saveState() 재호출 방지
    var isTerminating = false

    /// 통합 엔진 풀 (VLC + AVPlayer)
    let enginePool = MultiLiveEnginePool(maxPoolSize: maxSessions)

    /// 대역폭 코디네이터 (flashls AutoLevelManager/AutoBufferManager 참조)
    let bandwidthCoordinator = MultiLiveBandwidthCoordinator()

    /// 대역폭 코디네이터 주기적 업데이트 태스크
    private var bwCoordinatorTask: Task<Void, Never>?

    /// 선택된 세션
    var selectedSession: MultiLiveSession? {
        sessions.first { $0.id == selectedSessionId }
    }

    /// 오디오 활성 세션
    var audioSession: MultiLiveSession? {
        guard let id = audioSessionId else { return selectedSession }
        return sessions.first { $0.id == id }
    }

    /// 활성(재생 중) 세션 수
    var activeSessionCount: Int {
        sessions.filter { if case .playing = $0.loadState { return true } else { return false } }.count
    }

    /// 세션 추가 가능 여부
    var canAddSession: Bool {
        sessions.count < effectiveMaxSessions
    }

    // MARK: - 의존성

    private weak var apiClient: ChzzkAPIClient?
    private weak var settingsStore: SettingsStore?
    private let logger = AppLogger.player

    /// 메트릭 전송 포워더 (AppState에서 주입)
    var metricsForwarder: MetricsForwarder?

    /// 로그인 사용자 정보 (세션 채팅 전송용)
    private var userUid: String?
    private var userNickname: String?

    /// 캐시된 기본 이모티콘 (AppState에서 주입)
    private var cachedBasicEmoticonMap: [String: String] = [:]
    private var cachedBasicEmoticonPacks: [EmoticonPack] = []

    // MARK: - Init

    init() {}

    /// API 클라이언트 + 사용자 정보 설정 (AppState에서 지연 주입)
    func configure(apiClient: ChzzkAPIClient?, settingsStore: SettingsStore? = nil, userUid: String? = nil, userNickname: String? = nil, metricsForwarder: MetricsForwarder? = nil) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.userUid = userUid
        self.userNickname = userNickname
        self.metricsForwarder = metricsForwarder
    }

    /// 캐시된 기본 이모티콘 업데이트 (프리로드 완료 후 호출)
    func updateCachedEmoticons(map: [String: String], packs: [EmoticonPack]) {
        self.cachedBasicEmoticonMap = map
        self.cachedBasicEmoticonPacks = packs
    }

    /// 사용자 정보 업데이트 (로그인/로그아웃 시)
    func updateUserInfo(uid: String?, nickname: String?) {
        self.userUid = uid
        self.userNickname = nickname
        // 기존 세션의 chatViewModel에도 반영
        for session in sessions {
            session.chatViewModel.currentUserUid = uid
            session.chatViewModel.currentUserNickname = nickname
        }
    }

    // MARK: - 세션 관리

    /// 설정에서 선호 엔진 타입 조회 — 멀티라이브 전용 설정 우선, 미설정 시 플레이어 설정 폴백
    private var configuredEngine: PlayerEngineType {
        settingsStore?.multiLive.preferredEngine ?? settingsStore?.player.preferredEngine ?? .vlc
    }

    /// 채널 ID로 새 세션 추가 (엔진 풀에서 엔진 할당)
    func addSession(channelId: String, preferredEngine: PlayerEngineType? = nil, startImmediately: Bool = true) async {
        let preferredEngine = preferredEngine ?? configuredEngine
        let maxSessions = effectiveMaxSessions
        guard canAddSession else {
            logger.warning("MultiLive: 최대 세션 수(\(maxSessions)) 도달")
            return
        }
        guard !sessions.contains(where: { $0.channelId == channelId }) else {
            logger.info("MultiLive: 이미 존재하는 채널 \(channelId)")
            return
        }
        guard !addingChannelIds.contains(channelId) else { return }
        addingChannelIds.insert(channelId)
        defer { addingChannelIds.remove(channelId) }

        guard let apiClient else {
            logger.error("MultiLive: API 클라이언트 없음")
            return
        }

        // 첫 세션 시 warmup
        if sessions.isEmpty {
            await enginePool.warmup(count: 2, type: preferredEngine)
        }

        // 엔진 풀에서 엔진 획득
        guard let engine = await enginePool.acquire(type: preferredEngine) else {
            logger.error("MultiLive: 엔진 풀 할당 실패")
            return
        }

        do {
            let liveInfo = try await apiClient.liveDetail(channelId: channelId)

            // ISSUE-4 fix: await 이후 세션 수 재확인
            guard sessions.count < maxSessions else {
                logger.warning("MultiLive: await 이후 최대 세션 수 도달 — 추가 취소")
                await enginePool.release(engine)
                return
            }
            // ISSUE-4 fix: await 이후 동일 채널 재확인
            guard !sessions.contains(where: { $0.channelId == channelId }) else {
                logger.info("MultiLive: await 이후 중복 채널 감지 — 추가 취소 (\(channelId))")
                await enginePool.release(engine)
                return
            }

            let channelName = liveInfo.channel?.channelName ?? channelId
            let profileImageURL = liveInfo.channel?.channelImageURL

            let session = MultiLiveSession(
                channelId: channelId,
                channelName: channelName,
                profileImageURL: profileImageURL,
                liveInfo: liveInfo,
                apiClient: apiClient,
                userUid: userUid,
                userNickname: userNickname,
                cachedBasicEmoticonMap: cachedBasicEmoticonMap,
                cachedBasicEmoticonPacks: cachedBasicEmoticonPacks,
                engineType: preferredEngine,
                engine: engine
            )
            session.metricsForwarder = metricsForwarder
            sessions.append(session)

            // 대역폭 코디네이터에 세션 등록
            let isFirst = sessions.count == 1
            await bandwidthCoordinator.registerStream(
                sessionId: session.id,
                isSelected: isFirst
            )

            // 첫 세션이면 자동 선택 + 오디오 활성화
            if sessions.count == 1 {
                selectedSessionId = session.id
            } else {
                // 추가 세션은 음소거 + 백그라운드 모드로 시작
                session.playerViewModel.toggleMute()
                session.chatViewModel.isBackgroundMode = true
                session.setBackgroundMode(true)
                // [P0: 적응형 해상도] 비선택 세션은 720p로 시작
                if let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.isSelectedSession = false
                }
            }

            // 멀티라이브 제약 조건 적용
            let paneCount = sessions.count
            for s in sessions { s.playerViewModel.applyMultiLiveConstraints(paneCount: paneCount) }

            // [drawable 복구] 기존 세션의 drawable 재바인딩은
            // PlayerContainerView.attachVideoView()에서 SwiftUI 레이아웃 변경 시 자동 처리.
            // 여기서 중복 호출하면 500ms 후 2차 검은 프레임 플래시 발생.

            // 스트림 시작 (비동기) — restoreState에서는 startImmediately=false로
            // 모든 세션 추가 후 레이아웃 안정화 뒤 일괄 시작
            if startImmediately {
                Task {
                    await session.start()
                }
            }

            // 2개 이상 세션에서 대역폭 코디네이션 자동 시작
            if sessions.count >= 2 {
                startBandwidthCoordination()
            }

            saveState()
            logger.info("MultiLive: 세션 추가 — \(channelName) (\(channelId)) [\(preferredEngine.rawValue)]")
        } catch {
            // API 실패 시 엔진 풀에 반환
            await enginePool.release(engine)
            logger.error("MultiLive: 세션 추가 실패 — \(error.localizedDescription)")
        }
    }

    /// 세션 엔진 전환 — 정지 → 엔진 교체 → 재시작
    func switchEngine(session: MultiLiveSession, to newType: PlayerEngineType) async {
        let oldEngine = session.playerViewModel.detachEngine()
        await session.stop()
        if let oldEngine { await enginePool.release(oldEngine) }

        guard let engine = await enginePool.acquire(type: newType) else {
            logger.error("MultiLive: 엔진 전환 실패 — 풀 할당 불가")
            // 복구: 이전 엔진 재획득 시도
            if let fallback = await enginePool.acquire(type: session.playerViewModel.currentEngineType) {
                session.playerViewModel.injectEngine(fallback)
            }
            return
        }

        session.playerViewModel.preferredEngineType = newType
        session.playerViewModel.injectEngine(engine)
        await session.start()
        logger.info("MultiLive: 엔진 전환 → \(newType.rawValue) [\(session.channelName)]")
    }

    /// 세션 제거 — 엔진 풀 반환 포함
    func removeSession(id: UUID) async {
        // [Fix 24A] 중복 호출 가드 — 빠른 연타·동시 Task 방지
        guard !removingSessionIds.contains(id) else { return }
        guard sessions.contains(where: { $0.id == id }) else { return }
        removingSessionIds.insert(id)
        defer { removingSessionIds.remove(id) }

        guard let session = sessions.first(where: { $0.id == id }) else { return }

        // ⚠️ 세션 정지 후 엔진 분리 → 풀 반납 (순서 중요)
        await session.stop()
        if let engine = session.playerViewModel.detachEngine() {
            await enginePool.release(engine)
        }
        // 대역폭 코디네이터에서 세션 해제
        await bandwidthCoordinator.unregisterStream(sessionId: id)
        // [Fix 24A] await 후 index 재계산 — stale index 크래시 방지
        guard let freshIndex = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: freshIndex)

        // 선택 세션이 제거되면 다른 세션 선택
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
            if let newSelected = selectedSession {
                if newSelected.playerViewModel.isMuted {
                    newSelected.playerViewModel.toggleMute()
                }
                newSelected.playerViewModel.setBackgroundMode(false)
                newSelected.chatViewModel.isBackgroundMode = false
                newSelected.playerViewModel.recoverFromBackground()
            }
        }

        if audioSessionId == id {
            audioSessionId = sessions.first?.id
            if let newId = audioSessionId {
                for s in sessions { s.setMuted(s.id != newId) }
            }
        }
        audioEnabledSessionIds.remove(id)

        if sessions.count <= 1 { isGridLayout = false }

        // 세션 1개 이하이면 코디네이션 불필요
        if sessions.count < 2 {
            stopBandwidthCoordination()
            // [Fix 20-F] 가속 예산 해제 — 남은 세션은 config 기본값 사용
            for s in sessions {
                Task { await s.playerViewModel.streamCoordinator?.lowLatencyController?.setMaxRateOverride(nil) }
            }
        } else {
            updateEstimatedPaneSizes()
        }

        let remaining = sessions.count
        for s in sessions { s.playerViewModel.applyMultiLiveConstraints(paneCount: remaining) }

        // [drawable 복구] 남은 세션의 drawable 재바인딩은
        // PlayerContainerView.attachVideoView()에서 SwiftUI 레이아웃 변경 시 자동 처리.
        // 여기서 중복 호출하면 500ms 후 2차 검은 프레임 플래시 발생.

        saveState()
        logger.info("MultiLive: 세션 제거 — \(session.channelName)")
    }

    /// 세션 선택 (탭 전환)
    func selectSession(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        let previousId = selectedSessionId
        selectedSessionId = id

        // 대역폭 코디네이터: 선택 상태 업데이트
        Task {
            if let prevId = previousId {
                await bandwidthCoordinator.updateSelectedState(sessionId: prevId, isSelected: false)
            }
            await bandwidthCoordinator.updateSelectedState(sessionId: id, isSelected: true)
        }
        
        // [Fix 20-F] 선택 변경 시 가속 예산 즉시 재분배
        applyRateBudget()

        // 오디오 라우팅 + CPU 최적화: 이전 세션 → 백그라운드, 새 세션 → 포그라운드
        if previousId != id {
            if let prev = sessions.first(where: { $0.id == previousId }) {
                if !isMultiAudioMode {
                    if !prev.playerViewModel.isMuted {
                        prev.playerViewModel.toggleMute()
                    }
                }
                prev.chatViewModel.isBackgroundMode = true
                prev.playerViewModel.setBackgroundMode(true)
                // [P0: 적응형 해상도] 비선택 세션 → 720p 다운그레이드
                if let vlc = prev.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.isSelectedSession = false
                }
            }
            if let current = sessions.first(where: { $0.id == id }) {
                if !isMultiAudioMode {
                    if current.playerViewModel.isMuted {
                        current.playerViewModel.toggleMute()
                    }
                }
                current.chatViewModel.isBackgroundMode = false
                current.playerViewModel.setBackgroundMode(false)
                current.playerViewModel.recoverFromBackground()
                // [P0: 적응형 해상도] 선택된 세션 → 1080p 업그레이드
                if let vlc = current.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.isSelectedSession = true
                }
                // 메트릭 포워더: 선택된 세션으로 채널 전환 (기존 주 채널은 부가 채널로 이동)
                if let forwarder = metricsForwarder {
                    let chId = current.channelId
                    let chName = current.channelName
                    Task { await forwarder.switchPrimaryChannel(channelId: chId, channelName: chName) }
                }
            }
        }
        saveState()
    }

    /// 모든 세션 종료 (엔진 풀 반환 포함)
    func removeAllSessions() async {
        for session in sessions {
            await session.stop()
            if let engine = session.playerViewModel.detachEngine() {
                await enginePool.release(engine)
            }
        }
        sessions.removeAll()
        selectedSessionId = nil
    }

    /// 활성 스트림 존재 여부 (App Nap 방지용)
    func hasActiveStreams() -> Bool {
        sessions.contains { if case .playing = $0.loadState { return true } else { return false } }
    }

    // MARK: - 대역폭 코디네이터 관리

    /// 대역폭 코디네이터 설정 업데이트 (설정 변경 시 호출)
    func updateBandwidthCoordinatorConfig() {
        guard let settings = settingsStore?.multiLive else { return }
        let config = BandwidthCoordinatorConfig(
            safetyFactor: MultiLiveBWDefaults.safetyFactor,
            minPerStreamBitrate: MultiLiveBWDefaults.minPerStreamBitrate,
            historySize: MultiLiveBWDefaults.historySize,
            lowBufferThreshold: MultiLiveBWDefaults.lowBufferThreshold,
            highBufferThreshold: MultiLiveBWDefaults.highBufferThreshold,
            enableLevelCapping: settings.levelCappingEnabled,
            selectedSessionWeight: settings.selectedSessionBWWeight,
            emergencyBufferThreshold: MultiLiveBWDefaults.emergencyBufferThreshold
        )
        Task {
            await bandwidthCoordinator.applyConfig(config)
        }
    }

    /// 대역폭 코디네이션 루프 시작 (2개 이상 세션 시)
    func startBandwidthCoordination() {
        guard settingsStore?.multiLive.bandwidthCoordinationEnabled == true else { return }
        guard bwCoordinatorTask == nil else { return }

        updateBandwidthCoordinatorConfig()
        updateEstimatedPaneSizes()

        bwCoordinatorTask = Task { [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(MultiLiveBWDefaults.updateIntervalSecs))
                    guard !Task.isCancelled else { break }

                    // [Fix 24B] MainActor 진입 1회로 통합 — 기존 3회 → 1회
                    // 메트릭 수집 + 어드바이스 적용 + 가속 예산을 한 번에 처리
                    let metricsSnapshot = await MainActor.run {
                        self.collectMetricsSnapshot()
                    }
                    
                    // 코디네이터에 배치 리포트 (actor 격리 내에서 순차 처리)
                    let coordinator = self.bandwidthCoordinator
                    for m in metricsSnapshot {
                        await coordinator.reportBandwidthSample(
                            sessionId: m.sessionId,
                            bitrate: m.bitrateBps,
                            bufferLength: m.bufferLength,
                            fetchDuration: 0.5,
                            segmentDuration: 4.0
                        )
                        if m.playbackRate > 0 {
                            await coordinator.updatePlaybackRate(sessionId: m.sessionId, rate: m.playbackRate)
                        }
                    }

                    // 어드바이스 계산 + MainActor에서 적용
                    let advices = await coordinator.computeAdvice()
                    await MainActor.run {
                        self.applyBandwidthAdvices(advices)
                        self.applyRateBudget()
                    }
                }
            } catch {
                // CancellationError → 정상 종료
            }
        }
        logger.info("MultiLive: 대역폭 코디네이션 시작")
    }

    /// 대역폭 코디네이션 루프 중지
    func stopBandwidthCoordination() {
        bwCoordinatorTask?.cancel()
        bwCoordinatorTask = nil
        logger.info("MultiLive: 대역폭 코디네이션 중지")
    }

    /// 어드바이스를 각 세션에 적용 (MainActor)
    private func applyBandwidthAdvices(_ advices: [BandwidthAdvice]) {
        // [Fix 24B] ABR 설정을 단일 Task에서 배치 적용 (세션당 개별 Task 제거)
        var abrUpdates: [(PlayerViewModel, Double)] = []
        for advice in advices {
            guard let session = sessions.first(where: { $0.id == advice.sessionId }) else { continue }

            // [Quality Lock] 해당 세션이 최고 화질 유지 모드면 모든 캡/강등 무시
            let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine
            let isQualityLocked = vlc?.forceHighestQuality ?? false
            if isQualityLocked {
                if let vlc { vlc.maxAdaptiveHeight = 0 }
                continue
            }

            // VLC 엔진에 해상도 캡핑 적용 (동기 — MainActor에서 직접)
            if let vlc {
                if advice.cappedMaxHeight > 0 {
                    vlc.maxAdaptiveHeight = advice.cappedMaxHeight
                }
            }

            abrUpdates.append((session.playerViewModel, Double(advice.maxAllowedBitrate)))

            // 긴급 강등: 버퍼 부족 시 최저 품질 트리거
            if advice.emergencyDowngrade {
                if let vlc {
                    vlc.onQualityAdaptationRequest?(.downgrade(reason: "BW 코디네이터 긴급 강등"))
                }
            }
        }
        // ABR 비트레이트 설정을 단일 Task에서 순차 처리
        if !abrUpdates.isEmpty {
            Task {
                for (vm, maxBitrate) in abrUpdates {
                    await vm.streamCoordinator?.setMaxAllowedBitrate(maxBitrate)
                }
            }
        }
    }
    
    // MARK: - [Fix 20-F] 멀티라이브 가속 예산 (Rate Budget)
    
    /// 전체 세션의 가속 합산이 총 예산(+12%) 이내로 제한
    /// 선택(포커스) 세션 > 비선택 세션 우선순위
    private func applyRateBudget() {
        let sessionCount = sessions.count
        guard sessionCount >= 2 else {
            // 단일 세션: 오버라이드 해제
            if let session = sessions.first {
                Task {
                    await session.playerViewModel.streamCoordinator?.lowLatencyController?.setMaxRateOverride(nil)
                }
            }
            return
        }
        
        // 총 가속 예산: 전체 세션 합산 최대 +12% (4세션 기준 세션당 평균 +3%)
        let totalBudget = 0.12
        // 선택 세션은 예산의 60% 사용, 나머지를 비선택 세션이 균등 분배
        let selectedBudget = totalBudget * 0.6  // +7.2%
        let remainingBudget = totalBudget - selectedBudget  // +4.8%
        let nonSelectedCount = max(1, sessionCount - 1)
        let perNonSelectedBudget = remainingBudget / Double(nonSelectedCount)
        
        // [Fix 24B] 세션별 개별 Task → 단일 Task로 통합 (4개 → 1개)
        let ratePlan: [(PlayerViewModel, Double)] = sessions.map { session in
            let isSelected = session.id == selectedSessionId
            let maxRate = isSelected ? (1.0 + selectedBudget) : (1.0 + perNonSelectedBudget)
            return (session.playerViewModel, maxRate)
        }
        Task {
            for (vm, rate) in ratePlan {
                await vm.streamCoordinator?.lowLatencyController?.setMaxRateOverride(rate)
            }
        }
    }
    
    /// 각 세션의 VLC/AVPlayer 메트릭을 대역폭 코디네이터에 피딩 (MainActor)
    /// [Fix 24B] 경량 스냅숏 구조체 — fire-and-forget Task 제거
    private struct MetricSnapshot {
        let sessionId: UUID
        let bitrateBps: Double
        let bufferLength: TimeInterval
        let playbackRate: Double
    }
    
    /// [Fix 24B] MainActor에서 메트릭 값만 캡처 → 코디네이터 보고는 밖에서 배치 처리
    private func collectMetricsSnapshot() -> [MetricSnapshot] {
        var snapshots: [MetricSnapshot] = []
        for session in sessions {
            let sessionId = session.id
            if let metrics = session.latestMetrics {
                let bitrateBps = metrics.inputBitrateKbps * 1000.0
                let estimatedBufferSecs: TimeInterval
                if let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine,
                   vlc.isPlaying {
                    let d = vlc.duration
                    let c = vlc.currentTime
                    if d > 0, c > 0, (d - c) > 0, (d - c) < 60 {
                        estimatedBufferSecs = d - c
                    } else {
                        estimatedBufferSecs = metrics.bufferHealth * 10.0
                    }
                } else {
                    estimatedBufferSecs = metrics.bufferHealth * 10.0
                }
                snapshots.append(MetricSnapshot(
                    sessionId: sessionId,
                    bitrateBps: bitrateBps,
                    bufferLength: estimatedBufferSecs,
                    playbackRate: Double(metrics.playbackRate)
                ))
            } else if let avMetrics = session.latestAVMetrics {
                snapshots.append(MetricSnapshot(
                    sessionId: sessionId,
                    bitrateBps: avMetrics.indicatedBitrate,
                    bufferLength: avMetrics.bufferHealth * 10.0,
                    playbackRate: 0
                ))
            }
        }
        return snapshots
    }

    private func feedMetricsToCoordinator() {
        let coordinator = bandwidthCoordinator
        for session in sessions {
            let sessionId = session.id

            // VLC 메트릭이 있으면 대역폭 + 버퍼 데이터 보고
            if let metrics = session.latestMetrics {
                let bitrateBps = metrics.inputBitrateKbps * 1000.0 // kbps → bps
                // [Fix 22C] VLC 실제 버퍼 길이 사용 (duration - currentTime)
                // 기존: bufferHealth × 10.0 추정 → 부정확한 10초 스케일
                // 개선: 실제 VLC 파이프라인 버퍼 측정, 불가 시 기존 추정 폴백
                let estimatedBufferSecs: TimeInterval
                if let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine,
                   vlc.isPlaying {
                    let d = vlc.duration
                    let c = vlc.currentTime
                    if d > 0, c > 0, (d - c) > 0, (d - c) < 60 {
                        estimatedBufferSecs = d - c
                    } else {
                        estimatedBufferSecs = metrics.bufferHealth * 10.0
                    }
                } else {
                    estimatedBufferSecs = metrics.bufferHealth * 10.0
                }
                // [Fix 20 Phase3] 재생 배율 전달 — 대역폭 계산에 가속 소비량 반영
                let rate = Double(metrics.playbackRate)

                Task {
                    await coordinator.reportBandwidthSample(
                        sessionId: sessionId,
                        bitrate: bitrateBps,
                        bufferLength: estimatedBufferSecs,
                        fetchDuration: 0.5, // VLC 내부 페칭 — 근사값
                        segmentDuration: 4.0 // 일반 HLS 세그먼트 길이
                    )
                    await coordinator.updatePlaybackRate(sessionId: sessionId, rate: rate)
                }
            } else if let avMetrics = session.latestAVMetrics {
                // AVPlayer 메트릭
                let bitrateBps = avMetrics.indicatedBitrate // bps 단위
                let estimatedBufferSecs = avMetrics.bufferHealth * 10.0
                Task {
                    await coordinator.reportBandwidthSample(
                        sessionId: sessionId,
                        bitrate: bitrateBps,
                        bufferLength: estimatedBufferSecs,
                        fetchDuration: 0.5,
                        segmentDuration: 4.0
                    )
                }
            }
        }
    }

    /// 세션 수 기반 추정 패인 크기를 코디네이터에 전달
    /// 그리드 2x2 → 각 패인은 화면의 약 50%×50%, 2x1 → 50%×100% 등
    private func updateEstimatedPaneSizes() {
        let count = sessions.count
        guard count > 0 else { return }

        // macOS 기본 디스플레이 크기 기반 추정 (앱 윈도우 크기보다 보수적)
        let screenW = 1920 // 기본 추정
        let screenH = 1080

        let (paneW, paneH): (Int, Int)
        switch count {
        case 1: (paneW, paneH) = (screenW, screenH)
        case 2: (paneW, paneH) = (screenW / 2, screenH)
        case 3, 4: (paneW, paneH) = (screenW / 2, screenH / 2)
        default: (paneW, paneH) = (screenW / 3, screenH / 2)
        }

        let coordinator = bandwidthCoordinator
        Task {
            for session in sessions {
                await coordinator.updatePaneSize(
                    sessionId: session.id,
                    width: paneW,
                    height: paneH
                )
            }
        }
    }

    // MARK: - 세션 선택/제거 편의 메서드 (뷰에서 session 객체로 호출)

    /// 세션 선택 (탭 전환) — session 객체로 호출
    func select(_ session: MultiLiveSession) {
        selectSession(id: session.id)
    }

    /// 세션 제거 — session 객체로 호출
    func removeSession(_ session: MultiLiveSession) async {
        await removeSession(id: session.id)
    }

    // MARK: - 오디오 라우팅

    func routeAudio(to session: MultiLiveSession) {
        guard audioSessionId != session.id else { return }
        audioSessionId = session.id
        for s in sessions { s.setMuted(s.id != session.id) }
    }

    func toggleMultiAudioMode() {
        isMultiAudioMode.toggle()
        if isMultiAudioMode {
            audioEnabledSessionIds.removeAll()
            if let currentAudioId = audioSessionId ?? selectedSessionId {
                audioEnabledSessionIds.insert(currentAudioId)
            }
            for s in sessions {
                s.setMuted(!audioEnabledSessionIds.contains(s.id))
            }
        } else {
            audioEnabledSessionIds.removeAll()
            let activeId = audioSessionId ?? selectedSessionId
            for s in sessions {
                s.setMuted(s.id != activeId)
            }
        }
    }

    func toggleSessionAudio(_ session: MultiLiveSession) {
        guard isMultiAudioMode else {
            routeAudio(to: session)
            return
        }
        if audioEnabledSessionIds.contains(session.id) {
            audioEnabledSessionIds.remove(session.id)
            session.setMuted(true)
        } else {
            audioEnabledSessionIds.insert(session.id)
            session.setMuted(false)
        }
    }

    func isAudioEnabled(for session: MultiLiveSession) -> Bool {
        if isMultiAudioMode {
            return audioEnabledSessionIds.contains(session.id)
        } else {
            return (audioSessionId ?? selectedSessionId) == session.id
        }
    }

    // MARK: - 그리드 관리

    func moveSession(from source: IndexSet, to destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
        saveState()
    }

    func swapSessions(_ i: Int, _ j: Int) {
        guard i != j, sessions.indices.contains(i), sessions.indices.contains(j) else { return }
        sessions.swapAt(i, j)
    }

    func resetLayoutRatios() { layoutRatios = MultiLiveLayoutRatios() }

    func moveSessionLeft(_ session: MultiLiveSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }), idx > 0 else { return }
        sessions.swapAt(idx, idx - 1)
    }

    func moveSessionRight(_ session: MultiLiveSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }), idx < sessions.count - 1 else { return }
        sessions.swapAt(idx, idx + 1)
    }

    func stopAll() async {
        // 순차 해제 (동시 해제 시 VLC 데드락 위험)
        for s in sessions {
            await s.stop()
            if let engine = s.playerViewModel.detachEngine() {
                await enginePool.release(engine)
            }
        }
        sessions.removeAll()
        selectedSessionId = nil
        audioSessionId = nil
        isMultiAudioMode = false
        audioEnabledSessionIds.removeAll()
        isGridLayout = false
        gridLayoutMode = .preset
        layoutRatios = MultiLiveLayoutRatios()
        draggingSessionIndex = nil
        await enginePool.drain()
        await bandwidthCoordinator.reset()
        bwCoordinatorTask?.cancel()
        bwCoordinatorTask = nil
        MultiLivePersistedState.clear()
    }

    // MARK: - 세션 지속성

    func saveState() {
        guard !isTerminating else { return }
        guard !sessions.isEmpty else {
            MultiLivePersistedState.clear()
            return
        }
        let state = MultiLivePersistedState(from: self)
        state.save()
    }

    func saveLayoutChange() {
        saveState()
    }

    @discardableResult
    func restoreState(appState: AppState) async -> Int {
        guard sessions.isEmpty else { return 0 }
        guard let state = MultiLivePersistedState.load() else { return 0 }
        guard !state.channelIds.isEmpty else { return 0 }

        isGridLayout = state.isGridLayout
        gridLayoutMode = state.parsedGridLayoutMode
        layoutRatios.horizontalRatio = CGFloat(state.horizontalRatio)
        layoutRatios.verticalRatio = CGFloat(state.verticalRatio)

        let engine = appState.settingsStore.player.preferredEngine
        var restoredCount = 0

        // Phase 1: 모든 세션을 추가 (스트림 시작 없이)
        // 각 추가 시 SwiftUI가 그리드 레이아웃을 변경하지만, VLC가 아직 재생 전이므로
        // drawable 바인딩 문제가 발생하지 않는다.
        for channelId in state.channelIds {
            await addSession(channelId: channelId, preferredEngine: engine, startImmediately: false)
            restoredCount += 1
        }

        guard restoredCount > 0 else { return 0 }

        // Phase 2: SwiftUI 레이아웃 안정화 대기
        // 모든 PlayerContainerView가 최종 그리드 위치에 마운트될 시간 확보.
        // MainActor yield 2회 + 300ms 대기로 SwiftUI 렌더 사이클 완료 보장.
        await MainActor.run { /* yield to allow SwiftUI layout pass */ }
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Phase 3: 세션 병렬 시작 (staggered fire-and-forget)
        // [Fix 19] 기존: 순차 `await session.start()` → 4세션 × 2-5초 = 최대 20초 메인 스레드 차단
        // 수정: 각 세션을 독립 Task로 시작하되, staggered 딜레이로 CDN 연결 경합 완화.
        // fire-and-forget이므로 메인 스레드 이벤트 루프를 즉시 반환하여 앱 멈춤 방지.
        let sessionsToStart = Array(sessions)
        let selectedFirst = sessionsToStart.sorted { a, b in
            // 선택된 세션을 첫 번째로
            (a.id == selectedSessionId ? 0 : 1) < (b.id == selectedSessionId ? 0 : 1)
        }
        for (index, session) in selectedFirst.enumerated() {
            if let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine {
                vlc.isSelectedSession = (session.id == selectedSessionId)
            }
            let staggerDelay = UInt64(index) * 500_000_000 // 500ms 간격
            Task {
                if staggerDelay > 0 {
                    try? await Task.sleep(nanoseconds: staggerDelay)
                }
                await session.start()
            }
        }

        // [세션 복원 그리드 복구] 세션 시작 후 SwiftUI 레이아웃 안정화 뒤
        // drawable 재바인딩으로 Metal 렌더링 서피스를 올바른 레이어에 연결.
        // forceVoutRecovery(트랙 순환)는 VLC를 paused 상태로 만들어 재생 실패를 유발하므로
        // refreshDrawable만 사용한다.
        if sessionsToStart.count >= 2 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                for s in sessionsToStart {
                    if let vlc = s.playerViewModel.playerEngine as? VLCPlayerEngine {
                        vlc.refreshDrawable()
                    }
                }
            }
        }

        return restoredCount
    }
}
