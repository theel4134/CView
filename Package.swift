// swift-tools-version:6.0
// CView v2 — chzzkView 차세대 재설계 프로젝트

import PackageDescription

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
        .package(url: "https://github.com/tylerjonesio/vlckit-spm.git", from: "3.6.0"),
    ],
    targets: [
        // MARK: - Core Module (도메인 모델, 프로토콜, 유틸리티)
        .target(
            name: "CViewCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Networking Module (API 클라이언트, 엔드포인트)
        .target(
            name: "CViewNetworking",
            dependencies: ["CViewCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Auth Module (인증, 키체인, 쿠키)
        .target(
            name: "CViewAuth",
            dependencies: ["CViewCore", "CViewNetworking"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Persistence Module (SwiftData, 설정 저장)
        .target(
            name: "CViewPersistence",
            dependencies: ["CViewCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Chat Module (채팅 엔진, WebSocket)
        .target(
            name: "CViewChat",
            dependencies: ["CViewCore", "CViewNetworking"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Player Module (플레이어 엔진, HLS, 동기화)
        .target(
            name: "CViewPlayer",
            dependencies: [
                "CViewCore",
                "CViewNetworking",
                .product(name: "VLCKitSPM", package: "vlckit-spm"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - UI Module (디자인 시스템, 공유 컴포넌트)
        .target(
            name: "CViewUI",
            dependencies: ["CViewCore", "CViewNetworking"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Monitoring Module (성능, 메트릭)
        .target(
            name: "CViewMonitoring",
            dependencies: ["CViewCore", "CViewNetworking"],
            swiftSettings: [.swiftLanguageMode(.v6)],
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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // MARK: - Tests
        .testTarget(
            name: "CViewCoreTests",
            dependencies: ["CViewCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CViewNetworkingTests",
            dependencies: ["CViewNetworking", "CViewCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CViewChatTests",
            dependencies: ["CViewChat", "CViewCore", "CViewNetworking"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CViewPlayerTests",
            dependencies: ["CViewPlayer", "CViewCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CViewAuthTests",
            dependencies: ["CViewAuth", "CViewCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
