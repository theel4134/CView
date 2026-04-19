// swift-tools-version:6.0
// CView v2 — chzzkView 차세대 재설계 프로젝트

import PackageDescription

// MARK: - 공통 Swift 빌드 설정
/// Debug: 타입 체크 경고로 느린 컴파일 감지 / Release: 크로스 모듈 최적화
private let commonSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .unsafeFlags([
        "-Xfrontend", "-warn-long-function-bodies=200",
        "-Xfrontend", "-warn-long-expression-type-checking=200",
    ], .when(configuration: .debug)),
]

let package = Package(
    name: "CView_v2",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CViewCore", targets: ["CViewCore"]),
        .library(name: "CViewNetworking", targets: ["CViewNetworking"]),
        .library(name: "CViewAuth", targets: ["CViewAuth"]),
        .library(name: "CViewPersistence", targets: ["CViewPersistence"]),
        .library(name: "CViewChat", targets: ["CViewChat"]),
        .library(name: "CViewPlayer", targets: ["CViewPlayer"]),
        .library(name: "CViewUI", targets: ["CViewUI"]),
        .library(name: "CViewMonitoring", targets: ["CViewMonitoring"]),
        .executable(name: "CViewApp", targets: ["CViewApp"]),
    ],
    dependencies: [
        // VLCKitSPM — 리비전 고정으로 매 빌드마다 branch 해시 조회 방지
        .package(url: "https://github.com/rursache/VLCKitSPM.git", revision: "94ca521c32a9c1cd76824a34ab82e9ddb3360e65"),
    ],
    targets: [
        // MARK: - Core Module (도메인 모델, 프로토콜, 유틸리티)
        .target(
            name: "CViewCore",
            swiftSettings: commonSwiftSettings,
            // IOKit: PowerSourceMonitor 가 IOPSGetProvidingPowerSourceType / IOPSNotificationCreateRunLoopSource 사용
            linkerSettings: [.linkedFramework("IOKit")]
        ),

        // MARK: - Networking Module (API 클라이언트, 엔드포인트)
        .target(
            name: "CViewNetworking",
            dependencies: ["CViewCore"],
            swiftSettings: commonSwiftSettings
        ),

        // MARK: - Auth Module (인증, 키체인, 쿠키)
        .target(
            name: "CViewAuth",
            dependencies: ["CViewCore", "CViewNetworking"],
            swiftSettings: commonSwiftSettings
        ),

        // MARK: - Persistence Module (SwiftData, 설정 저장)
        .target(
            name: "CViewPersistence",
            dependencies: ["CViewCore"],
            swiftSettings: commonSwiftSettings
        ),

        // MARK: - Chat Module (채팅 엔진, WebSocket)
        .target(
            name: "CViewChat",
            dependencies: ["CViewCore", "CViewNetworking"],
            swiftSettings: commonSwiftSettings
        ),

        // MARK: - Player Module (플레이어 엔진, HLS, 동기화)
        .target(
            name: "CViewPlayer",
            dependencies: [
                "CViewCore",
                "CViewNetworking",
                .product(name: "VLCKitSPM", package: "VLCKitSPM"),
            ],
            resources: [
                .copy("Resources/hlsjs-player.html"),
                .copy("Resources/hls.min.js"),
            ],
            swiftSettings: commonSwiftSettings
        ),

        // MARK: - UI Module (디자인 시스템, 공유 컴포넌트)
        .target(
            name: "CViewUI",
            dependencies: ["CViewCore", "CViewNetworking"],
            swiftSettings: commonSwiftSettings
        ),

        // MARK: - Monitoring Module (성능, 메트릭)
        .target(
            name: "CViewMonitoring",
            dependencies: ["CViewCore", "CViewNetworking"],
            swiftSettings: commonSwiftSettings,
            linkerSettings: [.linkedFramework("IOKit")]
        ),

        // MARK: - App Target (메인 앱)
        .executableTarget(
            name: "CViewApp",
            dependencies: [
                "CViewCore",
                "CViewNetworking",
                "CViewAuth",
                "CViewPersistence",
                "CViewChat",
                "CViewPlayer",
                "CViewUI",
                "CViewMonitoring",
            ],
            swiftSettings: commonSwiftSettings
        ),

        // MARK: - Tests
        .testTarget(
            name: "CViewCoreTests",
            dependencies: ["CViewCore"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "CViewNetworkingTests",
            dependencies: ["CViewNetworking", "CViewCore"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "CViewChatTests",
            dependencies: ["CViewChat", "CViewCore", "CViewNetworking"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "CViewPlayerTests",
            dependencies: ["CViewPlayer", "CViewCore"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "CViewAuthTests",
            dependencies: ["CViewAuth", "CViewCore"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "CViewPersistenceTests",
            dependencies: ["CViewPersistence", "CViewCore"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "CViewMonitoringTests",
            dependencies: ["CViewMonitoring", "CViewCore", "CViewNetworking"],
            swiftSettings: commonSwiftSettings
        ),
    ]
)
