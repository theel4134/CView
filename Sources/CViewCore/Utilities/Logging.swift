// MARK: - CViewCore/Utilities/Logging.swift
// 구조화된 로깅 시스템 — OSLog 기반

import Foundation
import os.log

/// 앱 로거 — OSLog 기반 구조화된 로깅
public enum AppLogger {
    // MARK: - Subsystems

    private static let subsystem = "com.cview.app"

    public static let network = Logger(subsystem: subsystem, category: "Network")
    public static let api = Logger(subsystem: subsystem, category: "API")
    public static let auth = Logger(subsystem: subsystem, category: "Auth")
    public static let chat = Logger(subsystem: subsystem, category: "Chat")
    public static let player = Logger(subsystem: subsystem, category: "Player")
    public static let hls = Logger(subsystem: subsystem, category: "HLS")
    public static let sync = Logger(subsystem: subsystem, category: "Sync")
    public static let gpu = Logger(subsystem: subsystem, category: "GPU")
    public static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    public static let ui = Logger(subsystem: subsystem, category: "UI")
    public static let performance = Logger(subsystem: subsystem, category: "Performance")
    public static let app = Logger(subsystem: subsystem, category: "App")
    public static let general = Logger(subsystem: subsystem, category: "General")
}

/// Backward compatibility alias
public typealias Log = AppLogger
