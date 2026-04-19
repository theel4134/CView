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

    // [BW Smoothing] 네트워크 사용률 변동 완화용 — 마지막 적용된 ABR cap / 해상도 캡 추적
    /// 세션별 마지막 적용 ABR 비트레이트 (bps). EMA + 데드밴드 비교에 사용.
    private var _lastAppliedABRBitrate: [UUID: Double] = [:]
    /// 세션별 마지막 적용 해상도 캡(높이). 동일값 재적용 차단.
    private var _lastAppliedCapHeight: [UUID: Int] = [:]

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
    /// 멀티라이브 자식 프로세스 launcher (프로세스 격리 모드에서 사용)
    private weak var processLauncher: MultiLiveProcessLauncher?
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
    func configure(
        apiClient: ChzzkAPIClient?,
        settingsStore: SettingsStore? = nil,
        userUid: String? = nil,
        userNickname: String? = nil,
        metricsForwarder: MetricsForwarder? = nil,
        processLauncher: MultiLiveProcessLauncher? = nil
    ) {
        self.apiClient = apiClient
        self.settingsStore = settingsStore
        self.userUid = userUid
        self.userNickname = userNickname
        self.metricsForwarder = metricsForwarder
        self.processLauncher = processLauncher
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
    /// - Parameter presentationOverride: nil 이면 설정값(`useSeparateProcesses`) 기반,
    ///   `.embedded` 전달 시 라이브 메뉴 인라인 패널 등 부모 창 임베드 컨텍스트를 강제.
    func addSession(
        channelId: String,
        preferredEngine: PlayerEngineType? = nil,
        startImmediately: Bool = true,
        presentationOverride: MultiLiveProcessPresentation? = nil
    ) async {
        // [프로세스 격리 2026-04-19] 분리 인스턴스 모드(독립 창)만 자식 프로세스 경로로 라우팅한다.
        // 라이브 메뉴 인라인 패널(`presentationOverride == .embedded`)은 기존 in-process MLGridLayout으로
        // 렌더링되므로 launcher 경로를 건너뛰고 아래 레거시 패스로 세션을 추가한다 (채팅도 sessions onChange로 자동 추가됨).
        let routeViaLauncher: Bool = {
            if presentationOverride == .embedded { return false }
            if presentationOverride == .standalone { return true }
            return (settingsStore?.multiLive.useSeparateProcesses ?? false)
        }()
        if routeViaLauncher, let launcher = processLauncher {
            // 이미 자식으로 떠 있으면 forefront
            if let existing = launcher.instanceId(forChannel: channelId) {
                launcher.activate(instanceId: existing)
                return
            }

            let isolationSettings = settingsStore?.multiLive ?? .default
            let presentation = presentationOverride ?? isolationSettings.effectivePresentation
            let layoutMode = isolationSettings.processLayoutMode
            let newIndex = launcher.instances.count
            let initialFrame = launcher.suggestedInitialFrame(
                for: newIndex,
                totalAfterLaunch: newIndex + 1,
                mode: layoutMode,
                presentation: presentation
            )

            // 채널명을 알기 위해 가볍게 liveDetail 조회 (실패 시 channelId 그대로 사용)
            var displayName = channelId
            if let api = apiClient {
                if let info = try? await api.liveDetail(channelId: channelId),
                   let name = info.channel?.channelName, !name.isEmpty {
                    displayName = name
                }
            }
            await launcher.launchChild(
                channelId: channelId,
                channelName: displayName,
                initialFrame: initialFrame,
                initialVolume: 1.0,
                startMuted: false,
                borderless: presentation == .embedded,
                hideFromDock: presentation == .embedded
            )
            // launch 후 현재 선택된 표시 방식 + 배치 모드 재적용
            try? await Task.sleep(nanoseconds: 600_000_000)
            launcher.applyLayout(mode: layoutMode, presentation: presentation)
            return
        }

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

            // [No-Proxy] VLC 폴백 — 세션의 playerVM 이 AVPlayer 전환을 요청하면
            // MultiLiveManager 가 enginePool 을 통해 엔진 교체 + 재시작.
            session.playerViewModel.onEngineFallbackRequested = { @Sendable [weak self, weak session] _ in
                Task { @MainActor [weak self, weak session] in
                    guard let self, let session else { return }
                    await self.switchEngine(session: session, to: .avPlayer)
                }
            }

            // 대역폭 코디네이터에 세션 등록
            let isFirst = sessions.count == 1
            await bandwidthCoordinator.registerStream(
                sessionId: session.id,
                isSelected: isFirst
            )

            // 첫 세션이면 자동 선택 + 오디오 활성화
            if sessions.count == 1 {
                selectedSessionId = session.id
                // [Quality 2026-04-18] 첫 세션은 곧바로 선택되므로 multiLiveHQ 프로파일로 승격.
                // injectEngine() 가 .multiLive 로 초기화하지만, 첫 시작 시 isSelected=true 이므로
                // multiLiveHQ 옵션(adaptive-maxheight=0, manifestRefresh=5s, decoderThreads=3, ...)으로
                // 미디어가 생성되도록 사전 설정한다. 추가 세션은 .multiLive 유지.
                if let vlc = session.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.streamingProfile = .multiLiveHQ
                    vlc.isSelectedSession = true
                    vlc.sessionTier = .active
                }
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
    ///
    /// ## 수정 내역 (검은 화면 버그)
    /// 이전에는 `detachEngine()`을 `session.stop()` 보다 먼저 호출하여
    /// `playerViewModel.stopStream()`이 `isPreallocated=false` 분기로 들어갔다.
    /// `streamCoordinator.stopStream()`이 엔진 참조로 `stop()`을 호출하긴 했으나,
    /// `session.stop()` 이후 `startStream()` 재진입 시 새 엔진의 `videoView`가 SwiftUI
    /// 레이아웃 패스에 마운트되기 전 `play()`가 선행되어 VLC vout이 구 레이어 계층에
    /// 바인딩되는 문제가 발생. 전환 후 검은 화면만 남는 증상으로 나타난다.
    ///
    /// 개선 사항:
    /// 1. `session.stop()` 을 `detachEngine()` 보다 먼저 호출 — 엔진 참조가 정상 유지된
    ///    상태에서 coordinator/playerViewModel가 일관된 종료 경로로 이동.
    /// 2. `injectEngine` 후 `Task.yield()` 로 SwiftUI 의 `PlayerContainerView.attachVideoView()`
    ///    가 실행되도록 1 RunLoop 양보 → VLC drawable 이 새 컨테이너에 바인딩.
    /// 3. 세션 선택 상태(`isSelectedSession`), 백그라운드 모드(`setBackgroundMode`),
    ///    멀티라이브 제약(`applyMultiLiveConstraints`)을 새 엔진에 재적용.
    /// 4. 이전 세션의 `errorMessage` 를 제거하여 전환 직후 오류 오버레이가 남지 않도록 보정.
    func switchEngine(session: MultiLiveSession, to newType: PlayerEngineType) async {
        let currentType = session.playerViewModel.currentEngineType
        guard currentType != newType else { return }

        logger.info("MultiLive: 엔진 전환 시작 \(currentType.rawValue) → \(newType.rawValue) [\(session.channelName)]")

        // 1) 세션을 완전히 정지 (엔진이 playerViewModel에 연결된 상태에서)
        await session.stop()

        // 2) 엔진 분리 → 풀 반납
        if let oldEngine = session.playerViewModel.detachEngine() {
            await enginePool.release(oldEngine)
        }

        // 3) 새 엔진 획득 (실패 시 이전 엔진 타입으로 복구 재시작)
        guard let newEngine = await enginePool.acquire(type: newType) else {
            logger.error("MultiLive: 엔진 전환 실패 — 풀 할당 불가 (\(newType.rawValue))")
            if let fallback = await enginePool.acquire(type: currentType) {
                session.playerViewModel.injectEngine(fallback)
                await session.start()
            }
            return
        }

        // 4) 새 엔진 주입 + preferredEngineType 동기화
        session.playerViewModel.preferredEngineType = newType
        session.playerViewModel.injectEngine(newEngine)

        // 5) 세션 상태 반영 — resetForReuse 가 기본값(isSelectedSession=true, tier=.active)으로
        //    리셋하므로 비선택/백그라운드 세션이면 보정
        let isSelected = session.id == selectedSessionId
        if let vlc = newEngine as? VLCPlayerEngine, !isSelected {
            vlc.isSelectedSession = false
        }
        if session.isBackground {
            session.playerViewModel.setBackgroundMode(true)
        }

        // 6) 이전 스트림의 잔여 에러 메시지 제거 — 전환 직후 오버레이 잔존 방지
        session.playerViewModel.errorMessage = nil

        // 7) SwiftUI re-render 대기 — PlayerContainerView.attachVideoView() 가
        //    새 engine.videoView 를 마운트해야 VLC vout 이 올바른 레이어에 바인딩된다.
        //    Task.yield() + 1프레임(17ms) 대기로 레이아웃 확정.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)

        // 8) 재생 재시작
        await session.start()

        // 9) 멀티라이브 제약/설정 재적용 (parameterless start는 이 작업을 수행하지 않음)
        session.playerViewModel.applyMultiLiveConstraints(paneCount: sessions.count)
        if let ps = settingsStore?.player {
            session.playerViewModel.applySettings(
                volume: ps.volumeLevel,
                lowLatency: ps.lowLatencyMode,
                catchupRate: ps.catchupRate
            )
            session.playerViewModel.applyForceHighestQuality(ps.forceHighestQuality)
            session.playerViewModel.applySharpPixelScaling(ps.sharpPixelScaling)
        }

        logger.info("MultiLive: 엔진 전환 완료 → \(newType.rawValue) [\(session.channelName)]")
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
        // [BW Smoothing] 평활화 추적 캐시도 정리
        _lastAppliedABRBitrate.removeValue(forKey: id)
        _lastAppliedCapHeight.removeValue(forKey: id)
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
            // [Quality Lock 2026-04-18] 최고 화질 유지 모드에서는 비선택 세션도 1080p(HQ) 를 유지하여
            // 탭 전환 시 화질 다운/스위치 미디어 검은 프레임을 모두 제거한다.
            //   · VLC: updateSessionTier(.visible) 강등 스킵 (1080p 프로파일 유지)
            //   · AVPlayer: isSelectedMultiLiveSession=false / isWarmingUpForHQ=false 강등 스킵
            //     (긴 버퍼·preferredPeakBitRate ceiling 모두 HQ 유지)
            let qualityLocked = settingsStore?.player.forceHighestQuality ?? true
            if let prev = sessions.first(where: { $0.id == previousId }) {
                if !isMultiAudioMode {
                    if !prev.playerViewModel.isMuted {
                        prev.playerViewModel.toggleMute()
                    }
                }
                prev.chatViewModel.isBackgroundMode = true
                prev.playerViewModel.setBackgroundMode(true)
                // [GPU] quality-lock 과 독립적으로 compositor 렌더 스케일만 축소
                //   · 디코딩 해상도는 건드리지 않음 (1080p 유지)
                //   · CALayer.contentsScale 을 0.75× 로 낮춰 Metal drawable 픽셀 ~44% 감소
                //   · 비선택 패널에서만 적용되므로 화질 저하 체감 최소
                if let vlc = prev.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.setGPURenderTier(.visible)
                }
                if let av = prev.playerViewModel.playerEngine as? AVPlayerEngine {
                    av.setGPURenderTier(.visible)
                }
                if !qualityLocked {
                    // [P0: 적응형 해상도] 비선택 세션 → 720p 다운그레이드 (잠금 해제 시에만)
                    if let vlc = prev.playerViewModel.playerEngine as? VLCPlayerEngine {
                        vlc.updateSessionTier(.visible)  // 비선택 → multiLive 프로파일로 강등
                    }
                    // [P0: AVPlayer 이원화] 비선택 세션은 긴 버퍼 유지 (잠금 해제 시에만)
                    if let av = prev.playerViewModel.playerEngine as? AVPlayerEngine {
                        av.isWarmingUpForHQ = false
                        av.isSelectedMultiLiveSession = false
                    }
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
                // [GPU] 선택 세션 → compositor 풀 스케일 복원 (Retina 원본)
                if let vlc = current.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.setGPURenderTier(.active)
                }
                if let av = current.playerViewModel.playerEngine as? AVPlayerEngine {
                    av.setGPURenderTier(.active)
                }
                // [P0: 적응형 해상도] 선택된 세션 → 1080p 업그레이드 (multiLiveHQ)
                if let vlc = current.playerViewModel.playerEngine as? VLCPlayerEngine {
                    vlc.updateSessionTier(.active)   // 선택 → multiLiveHQ로 승격
                }
                // [P0: AVPlayer warm-up → lock 2단계 승격]
                //   1) 선택 즉시 isSelectedMultiLiveSession=true + warming=true (2.5s 버퍼)
                //   2) ~1.2s 후 warming=false로 해제하여 1.5s 이하 짧은 버퍼로 고정
                if let av = current.playerViewModel.playerEngine as? AVPlayerEngine {
                    av.isSelectedMultiLiveSession = true
                    av.isWarmingUpForHQ = true
                    // [Quality 2026-04-18] 비선택 동안 ABR 이 720p 이하로 강등되었을 가능성 → 즉시 nudge
                    //   워치독 60s 쿨다운/3샘플 누적을 기다리지 않고 곧바로 ceiling 재평가 트리거.
                    av.nudgeQualityCeiling(reason: "session-selected")
                    let targetId = id
                    Task { @MainActor [weak self, weak av] in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        guard let self else { return }
                        // 승격 완료 시점에도 여전히 선택 상태인 경우에만 lock 단계로 전환
                        guard self.selectedSessionId == targetId else { return }
                        av?.isWarmingUpForHQ = false
                    }
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
                    // [BW Smoothing] 코디네이터 주기에 ±18% 지터를 추가하여
                    // 다중 세션의 ABR 재평가 / 매니페스트 리프레시가 동일 시점에 정렬되어
                    // 네트워크 사용률이 톱니파(주기적 스파이크) 형태로 보이는 현상을 완화.
                    let baseInterval = PowerAwareInterval.scaled(MultiLiveBWDefaults.updateIntervalSecs)
                    let jitter = Double.random(in: -0.18...0.18) * baseInterval
                    try await Task.sleep(for: .seconds(max(2.0, baseInterval + jitter)))
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
    ///
    /// [BW Smoothing] 네트워크 사용률 변동 완화 정책
    /// 1. **선택 세션 ABR 캡 면제**: 포커스 세션은 사용자 체감 화질 유지 우선.
    ///    `setMaxAllowedBitrate(0)`로 잠금 해제하여 코디네이터의 분배가
    ///    체감 화질을 흔들지 못하게 한다. (긴급 강등 시에도 보호)
    /// 2. **EMA 평활화 (α=0.4)**: 새 어드바이스를 직접 적용하지 않고
    ///    이전값과 가중 평균하여 P20 분위수 추정 변동의 영향을 완화.
    /// 3. **데드밴드 12%**: 직전 적용값과 12% 미만 차이는 무시 → 잦은
    ///    ABR 변종 스위칭으로 인한 burst 스파이크 방지.
    /// 4. **해상도 캡 동일값 무시**: VLC 엔진에 같은 maxAdaptiveHeight 재할당
    ///    하지 않아 내부 ABR 재평가 트리거 빈도 감소.
    /// 5. **순차 적용 분산**: 세션별 setMaxAllowedBitrate 호출 사이에 짧은
    ///    sleep을 삽입해 매니페스트 fetch / variant switch 가 동시 발생하지
    ///    않게 한다. (코디네이터 8s 주기 내에서만 적용 가능한 작은 분산)
    private func applyBandwidthAdvices(_ advices: [BandwidthAdvice]) {
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

            let isSelected = (advice.sessionId == selectedSessionId)

            // [BW Smoothing #1] 선택 세션 ABR 캡 면제
            // — 코디네이터 분배 비트레이트가 체감 화질을 좌우하지 않도록
            //   포커스 세션은 항상 잠금 해제(maxBps=0). 화면 캡핑도 적용하지 않음.
            if isSelected {
                if let vlc { vlc.maxAdaptiveHeight = 0 }
                // 이전 cap 추적값 정리 — 추후 비선택 전환 시 재차 EMA 처음부터 시작
                _lastAppliedABRBitrate[advice.sessionId] = 0
                _lastAppliedCapHeight[advice.sessionId] = 0
                abrUpdates.append((session.playerViewModel, 0))
                continue
            }

            // [BW Smoothing #4] 해상도 캡: 동일값이면 재적용 생략
            if let vlc, advice.cappedMaxHeight > 0 {
                let lastH = _lastAppliedCapHeight[advice.sessionId] ?? 0
                if lastH != advice.cappedMaxHeight {
                    vlc.maxAdaptiveHeight = advice.cappedMaxHeight
                    _lastAppliedCapHeight[advice.sessionId] = advice.cappedMaxHeight
                }
            }

            // [BW Smoothing #2/#3] EMA 평활화 + 데드밴드
            let raw = Double(advice.maxAllowedBitrate)
            let last = _lastAppliedABRBitrate[advice.sessionId] ?? raw
            let smoothed = (last == 0) ? raw : (0.4 * raw + 0.6 * last)
            // 데드밴드: 직전 적용값과의 비율 차가 12% 미만이면 push 생략
            let baseline = max(1, last)
            let relDelta = abs(smoothed - last) / baseline
            if last > 0, relDelta < 0.12, !advice.emergencyDowngrade {
                // 변화가 작으면 적용 자체를 건너뜀 — 네트워크 트래픽 일정성 우선
            } else {
                _lastAppliedABRBitrate[advice.sessionId] = smoothed
                abrUpdates.append((session.playerViewModel, smoothed))
            }

            // 긴급 강등: 버퍼 부족 시 최저 품질 트리거 (선택 세션은 위에서 이미 continue 됨)
            if advice.emergencyDowngrade {
                if let vlc {
                    vlc.onQualityAdaptationRequest?(.downgrade(reason: "BW 코디네이터 긴급 강등"))
                }
            }
        }
        // [BW Smoothing #5] 세션별 setMaxAllowedBitrate 호출 사이 80ms 분산
        // — 코디네이터 8s 주기 내 작은 분산이지만, 동일 시점 다중 ABR 변종 스위칭
        //   (= burst spike) 발생을 차단한다.
        if !abrUpdates.isEmpty {
            Task {
                for (i, pair) in abrUpdates.enumerated() {
                    if i > 0 {
                        try? await Task.sleep(nanoseconds: 80_000_000)
                    }
                    await pair.0.streamCoordinator?.setMaxAllowedBitrate(pair.1)
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
