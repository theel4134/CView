// MARK: - PlayerModelsTests.swift
// CViewCore 플레이어 모델 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - PlayerState Tests

@Suite("PlayerState")
struct PlayerStateTests {

    @Test("기본 init")
    func defaultInit() {
        let state = PlayerState()
        #expect(state.phase == .idle)
        #expect(state.currentTime == 0)
        #expect(state.duration == 0)
        #expect(state.playbackRate == 1.0)
        #expect(state.volume == 1.0)
        #expect(state.latency == nil)
        #expect(state.quality == .auto)
    }

    @Test("isActive — playing")
    func isActivePlaying() {
        let state = PlayerState(phase: .playing)
        #expect(state.isActive == true)
    }

    @Test("isActive — buffering")
    func isActiveBuffering() {
        let state = PlayerState(phase: .buffering(progress: 0.5))
        #expect(state.isActive == true)
    }

    @Test("isActive — paused")
    func isActivePaused() {
        let state = PlayerState(phase: .paused)
        #expect(state.isActive == true)
    }

    @Test("isActive — idle")
    func isActiveIdle() {
        let state = PlayerState(phase: .idle)
        #expect(state.isActive == false)
    }

    @Test("isActive — loading")
    func isActiveLoading() {
        let state = PlayerState(phase: .loading)
        #expect(state.isActive == false)
    }

    @Test("isActive — error")
    func isActiveError() {
        let state = PlayerState(phase: .error(.streamNotFound))
        #expect(state.isActive == false)
    }

    @Test("isActive — ended")
    func isActiveEnded() {
        let state = PlayerState(phase: .ended)
        #expect(state.isActive == false)
    }
}

// MARK: - PlaybackOptions Presets Tests

@Suite("PlaybackOptions")
struct PlaybackOptionsTests {

    @Test("ultraLowLatency 프리셋")
    func ultraLowLatency() {
        let opts = PlaybackOptions.ultraLowLatency
        #expect(opts.lowLatencyMode == true)
        #expect(opts.networkCaching == 200)
        #expect(opts.liveCaching == 200)
        #expect(opts.catchupEnabled == true)
        #expect(opts.maxCatchupRate == 1.25)
    }

    @Test("balanced 프리셋")
    func balanced() {
        let opts = PlaybackOptions.balanced
        #expect(opts.networkCaching == 1000)
        #expect(opts.liveCaching == 1000)
        #expect(opts.maxCatchupRate == 1.1)
    }

    @Test("stable 프리셋")
    func stable() {
        let opts = PlaybackOptions.stable
        #expect(opts.lowLatencyMode == false)
        #expect(opts.networkCaching == 3000)
        #expect(opts.catchupEnabled == false)
        #expect(opts.maxCatchupRate == 1.0)
    }
}

// MARK: - PlayerEngineType Tests

@Suite("PlayerEngineType")
struct PlayerEngineTypeTests {

    @Test("displayName 확인")
    func displayNames() {
        #expect(PlayerEngineType.vlc.displayName == "VLC (고급)")
        #expect(PlayerEngineType.avPlayer.displayName == "AVPlayer (기본·저전력)")
        #expect(PlayerEngineType.hlsjs.displayName == "HLS.js (저지연)")
    }

    @Test("rawValue 매핑")
    func rawValues() {
        #expect(PlayerEngineType.vlc.rawValue == "VLC")
        #expect(PlayerEngineType.avPlayer.rawValue == "AVPlayer")
        #expect(PlayerEngineType.hlsjs.rawValue == "HLS.js")
    }

    @Test("CaseIterable")
    func caseIterable() {
        #expect(PlayerEngineType.allCases.count == 3)
    }
}

// MARK: - PlaybackSpeed Tests

@Suite("PlaybackSpeed")
struct PlaybackSpeedTests {

    @Test("displayName — 기본 속도")
    func displayNameDefault() {
        #expect(PlaybackSpeed.x100.displayName == "1x (기본)")
    }

    @Test("displayName — 정수 배속")
    func displayNameInteger() {
        #expect(PlaybackSpeed.x200.displayName == "2x")
    }

    @Test("displayName — 소수 배속")
    func displayNameFraction() {
        #expect(PlaybackSpeed.x125.displayName == "1.2x")
        #expect(PlaybackSpeed.x050.displayName == "0.5x")
        #expect(PlaybackSpeed.x075.displayName == "0.75x")
    }

    @Test("CaseIterable — 8가지 속도")
    func caseIterable() {
        #expect(PlaybackSpeed.allCases.count == 8)
    }

    @Test("id는 rawValue")
    func identifiable() {
        #expect(PlaybackSpeed.x150.id == 1.5)
    }
}

// MARK: - VODPlaybackState Tests

@Suite("VODPlaybackState")
struct VODPlaybackStateTests {

    @Test("Equatable — error 비교")
    func equatable() {
        #expect(VODPlaybackState.idle == VODPlaybackState.idle)
        #expect(VODPlaybackState.playing == VODPlaybackState.playing)
        #expect(VODPlaybackState.error("A") == VODPlaybackState.error("A"))
        #expect(VODPlaybackState.error("A") != VODPlaybackState.error("B"))
    }
}
