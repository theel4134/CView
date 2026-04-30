// MARK: - AppGroupContainer.swift
// 메인 앱과 Widget Extension 이 공유하는 컨테이너 디렉토리 추상화
//
// [Phase 1: Widget 통합 2026-04-24]
// - App Group entitlement 가 있으면 그 그룹 컨테이너를 사용 (정식)
// - 없으면 ~/Library/Application Support/CView/.shared/ 로 fallback (ad-hoc 빌드 호환)
//
// Widget Extension 도 sandbox 강제 시 fallback 경로 접근 불가 → 정식 배포는 App Group 필수

import Foundation

/// 메인 앱과 Widget Extension 사이의 공유 데이터 디렉토리 위치를 결정하는 헬퍼.
///
/// 단일 진실 공급원: `identifier` 만 변경하면 양쪽 코드 어디서든 같은 컨테이너를 사용한다.
public enum AppGroupContainer {

    /// App Group entitlement 식별자.
    /// Apple Developer 등록 후 메인 앱/위젯 양쪽 entitlements 에 동일 값 추가 필요.
    public static let identifier = "group.com.cview.app.shared"

    /// 공유 컨테이너 루트 URL.
    ///
    /// 우선순위:
    /// 1. App Group container (entitlement 등록된 경우)
    /// 2. `~/Library/Application Support/CView/.shared/` fallback
    /// 3. nil (Application Support 접근 자체 실패 — 정상 macOS 환경에서는 발생 X)
    public static var containerURL: URL? {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            ensureDirectory(at: groupURL)
            return groupURL
        }
        return fallbackURL
    }

    /// App Group 사용 여부 (디버깅/로그용).
    public static var isUsingAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }

    // MARK: - Subdirectories

    /// Widget snapshot JSON 파일 경로 (`<container>/widget-snapshot.json`).
    public static var widgetSnapshotURL: URL? {
        containerURL?.appendingPathComponent("widget-snapshot.json")
    }

    /// 인증 토큰 공유 디렉토리 (Phase 2 에서 KeychainService 마이그레이션 대상).
    /// `<container>/.auth-store/`
    public static var sharedAuthStoreURL: URL? {
        guard let root = containerURL else { return nil }
        let url = root.appendingPathComponent(".auth-store", isDirectory: true)
        ensureDirectory(at: url)
        return url
    }

    // MARK: - Internals

    private static var fallbackURL: URL? {
        guard let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        else { return nil }
        let url = appSupport
            .appendingPathComponent("CView", isDirectory: true)
            .appendingPathComponent(".shared", isDirectory: true)
        ensureDirectory(at: url)
        return url
    }

    private static func ensureDirectory(at url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
