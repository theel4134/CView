// MARK: - CViewAuth/KeychainService.swift
// 보안 토큰 저장 — 파일 기반 (ad-hoc 서명 호환)

import Foundation
import CViewCore

/// 보안 토큰 저장소 (actor 기반, 파일 기반)
/// ad-hoc 서명("Sign to Run Locally")에서 레거시 키체인 암호 프롬프트를 회피합니다.
/// Application Support 내 .cview-auth/ 디렉토리에 파일로 저장합니다.
public actor KeychainService {
    private let serviceName: String
    private let storageDir: URL

    public init(serviceName: String = "com.cview.auth") {
        self.serviceName = serviceName

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageDir = appSupport.appendingPathComponent("CView").appendingPathComponent(".auth-store")

        // 디렉토리 생성
        do {
            try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        } catch {
            Log.auth.warning("Auth store directory creation failed: \(error.localizedDescription)")
        }

        // 디렉토리 숨김 처리 (.로 시작하므로 기본 숨김)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = storageDir
        do {
            try mutableDir.setResourceValues(resourceValues)
        } catch {
            Log.auth.debug("Auth store resource values failed: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD

    /// 데이터 저장
    public func save(key: String, data: Data) throws {
        let fileURL = fileURL(for: key)
        try data.write(to: fileURL, options: [.atomic])
        // macOS에서 .completeFileProtection은 무효 — POSIX 파일 퍼미션으로 소유자만 읽기/쓰기
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        Log.auth.debug("Auth store saved: \(key, privacy: .private)")
    }

    /// 데이터 읽기
    public func load(key: String) throws -> Data? {
        let fileURL = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    /// 삭제
    public func delete(key: String) throws {
        let fileURL = fileURL(for: key)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Convenience

    /// 문자열 저장
    public func saveString(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        try save(key: key, data: data)
    }

    /// 문자열 읽기
    public func loadString(key: String) throws -> String? {
        guard let data = try load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Codable 저장
    public func saveCodable<T: Codable & Sendable>(key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        try save(key: key, data: data)
    }

    /// Codable 읽기
    public func loadCodable<T: Codable & Sendable>(key: String, as type: T.Type) throws -> T? {
        guard let data = try load(key: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    /// 전체 삭제 (로그아웃 시)
    public func deleteAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
        Log.auth.info("Auth store cleared")
    }
    
    // MARK: - Private

    private func fileURL(for key: String) -> URL {
        // 키를 안전한 파일명으로 변환
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return storageDir.appendingPathComponent(safeKey)
    }
}
