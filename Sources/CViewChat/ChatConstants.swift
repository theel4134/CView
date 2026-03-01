// MARK: - ChatConstants.swift
// CViewChat 모듈 매직 넘버 상수화

import Foundation

// MARK: - WebSocket

public enum WSDefaults {
    /// 핑 전송 간격 (초)
    public static let pingInterval: TimeInterval = 20
    /// 최대 메시지 크기 (1MB)
    public static let maxMessageSize = 1_048_576
    /// WS 세션 요청 타임아웃 (초)
    public static let requestTimeout: TimeInterval = 90
    /// WS 세션 리소스 타임아웃 (초, 15분)
    public static let resourceTimeout: TimeInterval = 900
    /// WebSocket 프로토콜 버전
    public static let protocolVersion = "13"
    /// Keep-Alive 헤더 값
    public static let keepAliveHeader = "timeout=120, max=200"
}

// MARK: - Chat Engine

public enum ChatDefaults {
    /// 최대 메시지 버퍼 크기
    public static let maxMessageBuffer = 500
    /// 채팅 엔진 핑 간격 (초)
    public static let pingInterval: TimeInterval = 20
    /// 디바이스 타입 코드
    public static let deviceType = 2001
    /// 최근 채팅 기본 요청 수
    public static let recentChatDefaultCount = 50
    /// 최대 표시 메시지 수 (ViewModel)
    public static let maxVisibleMessages = 500
    /// 기본 채팅 금지 지속 시간 (초, 5분)
    public static let defaultMuteDurationSecs: TimeInterval = 300
}

// MARK: - Reconnection Policy

public enum ReconnectDefaults {
    /// 기본 최대 재시도 딜레이 (초)
    public static let defaultMaxDelay: TimeInterval = 30.0
    /// 기본 최대 재시도 횟수
    public static let defaultMaxAttempts = 10
    /// 기본 지터 팩터
    public static let defaultJitter: Double = 0.25
    /// 재시도 횟수 리셋 임계값 (초)
    public static let resetThreshold: TimeInterval = 60.0
    /// 공격적 모드 최대 딜레이 (초)
    public static let aggressiveMaxDelay: TimeInterval = 10.0
    /// 공격적 모드 최대 재시도
    public static let aggressiveMaxAttempts = 20
}
