// MARK: - MultiLivePlayerPane.swift
import SwiftUI
import CViewCore
import CViewPlayer

// MARK: - Player Pane
struct MLPlayerPane: View {
    let session: MultiLiveSession
    let appState: AppState

    var body: some View {
        switch session.loadState {
        case .idle:
            Color.black.overlay(ProgressView().tint(.white))
        case .loading:
            MLLoadingState(session: session)
        case .playing:
            HSplitView {
                MLVideoArea(session: session, appState: appState)
                    .frame(minWidth: 340)
                if session.isChatVisible {
                    ChatPanelView(chatVM: session.chatViewModel, onOpenSettings: {})
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 400)
                }
            }
        case .offline:
            ZStack {
                Color.black
                if let url = session.thumbnailURL {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                            .blur(radius: 24).opacity(0.22)
                    } placeholder: { Color.clear }
                    .ignoresSafeArea()
                }
                Color.black.opacity(0.7)
                VStack(spacing: 18) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.05)).frame(width: 80, height: 80)
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).frame(width: 80, height: 80)
                        Image(systemName: "tv.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    VStack(spacing: 8) {
                        Text("방송이 종료되었습니다")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        let name = session.channelName.isEmpty ? session.channelId : session.channelName
                        Text(name)
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                    }
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.retry(using: api, appState: appState) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                            Text("다시 확인")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.11)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .error(let msg):
            ZStack {
                Color.black
                if let url = session.thumbnailURL {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                            .blur(radius: 24).opacity(0.18)
                    } placeholder: { Color.clear }
                    .ignoresSafeArea()
                }
                Color.black.opacity(0.72)
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.orange.opacity(0.10)).frame(width: 76, height: 76)
                        Circle().stroke(Color.orange.opacity(0.18), lineWidth: 1).frame(width: 76, height: 76)
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 26)).foregroundStyle(.orange)
                    }
                    VStack(spacing: 6) {
                        Text("연결 오류")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Text(msg)
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                    Button {
                        guard let api = appState.apiClient else { return }
                        Task { await session.retry(using: api, appState: appState) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                            Text("재시도")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(Color.orange.opacity(0.17)))
                        .overlay(Capsule().stroke(Color.orange.opacity(0.32), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Grid Layout
struct MLGridLayout: View {
    let manager: MultiLiveSessionManager
    let appState: AppState
    var onAdd: (() -> Void)? = nil

    /// 포커스 모드: 더블클릭 시 해당 셀을 메인으로 확대
    @State private var focusedSessionId: UUID? = nil

    var body: some View {
        let sessions = manager.sessions
        let count = sessions.count
        GeometryReader { geo in
            if let focusedId = focusedSessionId,
               let focused = sessions.first(where: { $0.id == focusedId }) {
                // ── 포커스 모드: 메인 셀 + 하단 썸네일 스트립 ──
                let others = sessions.filter { $0.id != focusedId }
                VStack(spacing: 2) {
                    MLGridCell(
                        session: focused,
                        manager: manager,
                        appState: appState,
                        focusedSessionId: $focusedSessionId,
                        isFocused: true
                    )
                    if !others.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(others) { session in
                                MLGridCell(
                                    session: session,
                                    manager: manager,
                                    appState: appState,
                                    focusedSessionId: $focusedSessionId,
                                    isFocused: false
                                )
                                .frame(height: min(geo.size.height * 0.22, 140))
                            }
                        }
                        .frame(height: min(geo.size.height * 0.22, 140))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                // ── 일반 그리드 모드 ──
                normalGrid(sessions: sessions, count: count)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: focusedSessionId)
    }

    @ViewBuilder
    private func normalGrid(sessions: [MultiLiveSession], count: Int) -> some View {
        if count == 2 {
            HStack(spacing: 2) {
                ForEach(sessions) { session in
                    MLGridCell(session: session, manager: manager, appState: appState, focusedSessionId: $focusedSessionId, isFocused: false)
                }
                // 빈 슬롯(채널 추가)
                if let onAdd, count < MultiLiveSessionManager.maxSessions {
                    addSlotView(onAdd: onAdd)
                }
            }
        } else {
            // 3개 이상: 2×2 그리드 (빈 슬롯에 채널 추가 버튼)
            let cols = 2
            let rows = 2
            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<cols, id: \.self) { col in
                            let idx = row * cols + col
                            if idx < sessions.count {
                                MLGridCell(session: sessions[idx], manager: manager, appState: appState, focusedSessionId: $focusedSessionId, isFocused: false)
                            } else if let onAdd, count < MultiLiveSessionManager.maxSessions {
                                addSlotView(onAdd: onAdd)
                            } else {
                                Color.black
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func addSlotView(onAdd: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))
                Text("채널 추가")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.13))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .white.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onAdd() }
    }
}

// MARK: - Grid Cell
struct MLGridCell: View {
    let session: MultiLiveSession
    let manager: MultiLiveSessionManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let isFocused: Bool

    @State private var showOverlay = false
    @State private var hideTask: Task<Void, Never>?

    private var isAudioActive: Bool {
        (manager.audioSessionId ?? manager.selectedSessionId) == session.id
    }

    var body: some View {
        ZStack {
            PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
                .background(Color.black)
                // isAudioOnly 표시는 AVPlayerLayer.isHidden / VLC videoTrack으로 처리.
                // SwiftUI .opacity()는 오프스크린 compositing 버퍼를 강제 생성하므로 제거.
                .overlay(alignment: .topLeading) {
                    // 채널명 미니 배지 (오버레이 숨김 시 표시)
                    HStack(spacing: 4) {
                        // 오디오 활성 표시
                        if isAudioActive && !session.isMuted {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                        }
                        Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.black.opacity(0.62))
                    .clipShape(Capsule())
                    .padding(7)
                    .opacity(showOverlay ? 0 : 1)
                    .animation(.easeInOut(duration: 0.12), value: showOverlay)
                }
                // 오디오 활성 셀 테두리 강조
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            isAudioActive
                                ? DesignTokens.Colors.chzzkGreen.opacity(0.65)
                                : Color.clear,
                            lineWidth: 2
                        )
                )

            // 버퍼링 인디케이터
            if session.playerViewModel.streamPhase == .buffering
                || session.playerViewModel.streamPhase == .connecting {
                ProgressView().scaleEffect(0.9).tint(.white)
                    .background(Circle().fill(Color.black.opacity(0.4)).frame(width: 38, height: 38))
            }

            // 세션 상태 오버레이 (loading / offline / error)
            switch session.loadState {
            case .loading:
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(.white)
                    .background(
                        Circle().fill(Color.black.opacity(0.55)).frame(width: 36, height: 36)
                    )
            case .offline:
                VStack(spacing: 6) {
                    Image(systemName: "tv.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("방송 종료")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            case .error:
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange.opacity(0.85))
                    Text("연결 오류")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.75))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            default:
                EmptyView()
            }

            // 컨트롤 오버레이 (hover 시)
            MLGridControlOverlay(
                session: session,
                manager: manager,
                appState: appState,
                focusedSessionId: $focusedSessionId,
                isFocused: isFocused
            )
            .opacity(showOverlay ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: showOverlay)
        }
        .contentShape(Rectangle())
        .onHover { h in
            hideTask?.cancel()
            withAnimation { showOverlay = h }
            if h { scheduleHide() }
        }
        .onTapGesture(count: 2) {
            // 더블클릭 → 포커스 모드 진입/해제
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                focusedSessionId = (focusedSessionId == session.id) ? nil : session.id
            }
        }
        .onTapGesture(count: 1) {
            hideTask?.cancel()
            withAnimation { showOverlay.toggle() }
            if showOverlay { scheduleHide() }
        }
    }

    private func scheduleHide() {
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { showOverlay = false }
        }
    }
}

// MARK: - Grid Control Overlay (셀 전용)
struct MLGridControlOverlay: View {
    let session: MultiLiveSession
    let manager: MultiLiveSessionManager
    let appState: AppState
    @Binding var focusedSessionId: UUID?
    let isFocused: Bool

    private var isAudioActive: Bool {
        (manager.audioSessionId ?? manager.selectedSessionId) == session.id
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .clear, location: 0.65),
                    .init(color: .black.opacity(0.75), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack {
                // 상단: 채널명 + 시청자 + 포커스 버튼
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Circle().fill(DesignTokens.Colors.live).frame(width: 5, height: 5)
                        Text("LIVE").font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2.5)
                    .background(DesignTokens.Colors.live.opacity(0.85))
                    .clipShape(Capsule())

                    Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .lineLimit(1)

                    Spacer()

                    if session.viewerCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill").font(.system(size: 9))
                            Text(formattedViewers).font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())
                    }

                    // 포커스 토글 버튼
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            focusedSessionId = (focusedSessionId == session.id) ? nil : session.id
                        }
                    } label: {
                        Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .help(isFocused ? "포커스 해제" : "포커스 확대")
                }
                .padding(.horizontal, 10).padding(.top, 10)

                Spacer()

                // 하단: 음량 + 오디오 라우팅
                HStack(spacing: 8) {
                    // 오디오 라우팅 버튼
                    Button {
                        manager.routeAudio(to: session)
                    } label: {
                        Image(systemName: isAudioActive
                              ? (session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                              : "speaker.zzz.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(isAudioActive
                                             ? (session.isMuted ? .orange : DesignTokens.Colors.chzzkGreen)
                                             : .white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(
                                isAudioActive
                                    ? DesignTokens.Colors.chzzkGreen.opacity(0.18)
                                    : Color.black.opacity(0.4)
                            ))
                    }
                    .buttonStyle(.plain)
                    .help(isAudioActive ? "현재 오디오 채널" : "이 채널로 오디오 전환")

                    if isAudioActive {
                        // 오디오 활성 채널만 볼륨 슬라이더 표시
                        HStack(spacing: 5) {
                            Button { session.setMuted(!session.isMuted) } label: {
                                Image(systemName: session.isMuted ? "speaker.slash" : "speaker.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(session.isMuted ? .orange : .white.opacity(0.7))
                            }
                            .buttonStyle(.plain)

                            Slider(
                                value: Binding(
                                    get: { session.isMuted ? 0 : Double(session.playerViewModel.volume) },
                                    set: { v in
                                        session.playerViewModel.setVolume(Float(v))
                                        if session.isMuted && v > 0 { session.setMuted(false) }
                                    }
                                ),
                                in: 0...1
                            )
                            .frame(width: 70)
                            .tint(DesignTokens.Colors.chzzkGreen)

                            Text("\(Int((session.isMuted ? 0 : session.playerViewModel.volume) * 100))%")
                                .font(.system(size: 9, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(width: 26, alignment: .leading)
                        }
                    }

                    Spacer()

                    // 오프라인/에러 상태에서 재시도 버튼
                    if case .offline = session.loadState {
                        retryButton()
                    } else if case .error = session.loadState {
                        retryButton()
                    }

                    if let quality = session.playerViewModel.currentQuality {
                        Text(quality.name)
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(DesignTokens.Colors.accentBlue.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func retryButton() -> some View {
        Button {
            guard let api = appState.apiClient else { return }
            Task { await session.retry(using: api, appState: appState) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                Text("재시도")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var formattedViewers: String {
        let n = session.viewerCount
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000  { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Loading State
struct MLLoadingState: View {
    let session: MultiLiveSession
    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black
            if let url = session.thumbnailURL {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 28).opacity(0.25)
                } placeholder: { Color.clear }
                .ignoresSafeArea()
            }
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(DesignTokens.Colors.chzzkGreen.opacity(0.15), lineWidth: 2)
                        .frame(width: 60, height: 60)
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(
                            AngularGradient(
                                colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.chzzkGreen.opacity(0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                }
                .onAppear { spin = true }
                VStack(spacing: 6) {
                    let name = session.channelName.isEmpty ? session.channelId : session.channelName
                    Text(name)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text("스트림 연결 중...")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }
}

// MARK: - Video Area (탭 모드 전용)
struct MLVideoArea: View {
    let session: MultiLiveSession
    let appState: AppState
    @State private var showOverlay = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            PlayerVideoView(videoView: session.playerViewModel.currentVideoView)
                .background(Color.black)
                // isAudioOnly는 AVPlayerLayer.isHidden / VLC videoTrack으로 처리.

            if session.playerViewModel.isAudioOnly {
                ZStack {
                    Color.black
                    // 블러 썸네일 배경
                    if let url = session.thumbnailURL {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                                .blur(radius: 30).opacity(0.28)
                        } placeholder: { Color.clear }
                        .ignoresSafeArea()
                    }
                    // 어두운 스크림
                    Color.black.opacity(0.62)
                    // 콘텐츠
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(DesignTokens.Colors.chzzkGreen.opacity(0.11))
                                .frame(width: 84, height: 84)
                            Circle()
                                .stroke(DesignTokens.Colors.chzzkGreen.opacity(0.22), lineWidth: 1)
                                .frame(width: 84, height: 84)
                            Image(systemName: "waveform")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(DesignTokens.Colors.chzzkGreen)
                                .symbolEffect(.pulse)
                        }
                        VStack(spacing: 5) {
                            let name = session.channelName.isEmpty ? session.channelId : session.channelName
                            Text(name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("오디오 전용 모드")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.42))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if session.playerViewModel.streamPhase == .buffering
                || session.playerViewModel.streamPhase == .connecting {
                ProgressView().scaleEffect(1.3).tint(.white)
                    .background(Circle().fill(Color.black.opacity(0.4)).frame(width: 46, height: 46))
            }

            if session.isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "tv.slash").font(.system(size: 13))
                    Text("방송 종료").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.9))
                .clipShape(Capsule())
            }

            // 엔진 뱃지
            VStack {
                HStack {
                    PlayerEngineBadge(engineType: session.playerViewModel.currentEngineType)
                        .padding(8)
                    Spacer()
                }
                Spacer()
            }

            MLControlOverlay(session: session, appState: appState)
                .opacity(showOverlay ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: showOverlay)
        }
        .contentShape(Rectangle())
        .onHover { h in
            hideTask?.cancel()
            withAnimation { showOverlay = h }
            if h { scheduleHide() }
        }
        .onTapGesture {
            hideTask?.cancel()
            withAnimation { showOverlay.toggle() }
            if showOverlay { scheduleHide() }
        }
    }

    private func scheduleHide() {
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { showOverlay = false }
        }
    }
}

// MARK: - Control Overlay (탭 모드 전용)
struct MLControlOverlay: View {
    let session: MultiLiveSession
    let appState: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.65),
                    .init(color: .black.opacity(0.78), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack {
                topBar.padding(.horizontal, 14).padding(.top, 12)
                Spacer()
                bottomBar.padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(DesignTokens.Colors.live).frame(width: 6, height: 6)
                Text("LIVE").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(DesignTokens.Colors.live.opacity(0.85))
            .clipShape(Capsule())

            Text(session.channelName.isEmpty ? session.channelId : session.channelName)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4)
                .lineLimit(1)

            if !session.liveTitle.isEmpty {
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text(session.liveTitle)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            if session.viewerCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(.system(size: 10))
                    Text(formattedViewers).font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.black.opacity(0.4))
                .clipShape(Capsule())
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { session.setMuted(!session.isMuted) } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(session.isMuted ? .orange : .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(session.isMuted ? "음소거 해제" : "음소거")

            Slider(
                value: Binding(
                    get: { session.isMuted ? 0 : Double(session.playerViewModel.volume) },
                    set: { v in
                        session.playerViewModel.setVolume(Float(v))
                        if session.isMuted && v > 0 { session.setMuted(false) }
                    }
                ),
                in: 0...1
            )
            .frame(width: 80)
            .tint(DesignTokens.Colors.chzzkGreen)

            Spacer()

            Text(session.playerViewModel.formattedUptime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))

            if let quality = session.playerViewModel.currentQuality {
                Text(quality.name)
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(DesignTokens.Colors.accentBlue.opacity(0.8))
                    .clipShape(Capsule())
            }

            // 오류/오프라인 상태 재시도
            switch session.loadState {
            case .error, .offline:
                Button {
                    guard let api = appState.apiClient else { return }
                    Task { await session.retry(using: api, appState: appState) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.orange.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("재시도")
            default:
                EmptyView()
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    session.isChatVisible.toggle()
                }
            } label: {
                Image(systemName: session.isChatVisible
                      ? "bubble.left.and.bubble.right.fill"
                      : "bubble.left.and.bubble.right")
                    .font(.system(size: 13))
                    .foregroundStyle(session.isChatVisible ? DesignTokens.Colors.chzzkGreen : .white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(
                        session.isChatVisible
                            ? DesignTokens.Colors.chzzkGreen.opacity(0.18)
                            : Color.white.opacity(0.12)
                    ))
            }
            .buttonStyle(.plain)
            .help(session.isChatVisible ? "채팅 숨기기" : "채팅 보기")
        }
    }

    private var formattedViewers: String {
        let n = session.viewerCount
        if n >= 10_000 { return String(format: "%.1f만", Double(n) / 10_000) }
        if n >= 1_000  { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Empty State
struct MLEmptyState: View {
    let onAdd: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [DesignTokens.Colors.chzzkGreen.opacity(0.05), Color.clear],
                center: .center, startRadius: 0, endRadius: 300
            )
            .ignoresSafeArea()
            VStack(spacing: 28) {
                ZStack {
                    Circle().fill(DesignTokens.Colors.chzzkGreen.opacity(0.05)).frame(width: 130, height: 130)
                    Circle().fill(DesignTokens.Colors.chzzkGreen.opacity(0.09)).frame(width: 96, height: 96)
                    Image(systemName: "rectangle.split.3x1.fill")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DesignTokens.Colors.chzzkGreen, DesignTokens.Colors.accentBlue],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(appeared ? 1 : 0.75)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text("멀티 라이브")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text("최대 4개 채널을 탭으로 동시에 시청할 수 있습니다.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

                HStack(spacing: 12) {
                    featureCard(icon: "rectangle.grid.2x2", label: "그리드 모드")
                    featureCard(icon: "speaker.wave.2", label: "오디오 라우팅")
                    featureCard(icon: "bubble.left.and.bubble.right", label: "채팅 분리")
                    featureCard(icon: "arrow.up.left.and.arrow.down.right", label: "포커스 확대")
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                Button(action: onAdd) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 15))
                        Text("채널 추가").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 11)
                    .background(
                        Capsule().fill(DesignTokens.Colors.chzzkGreen)
                            .shadow(color: DesignTokens.Colors.chzzkGreen.opacity(0.35), radius: 14, y: 5)
                    )
                }
                .buttonStyle(.plain)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.06)) {
                appeared = true
            }
        }
    }

    private func featureCard(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16))
                .foregroundStyle(DesignTokens.Colors.chzzkGreen.opacity(0.65))
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
        }
        .frame(width: 74).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
    }
}


