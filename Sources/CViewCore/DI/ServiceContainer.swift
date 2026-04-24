// MARK: - CViewCore/DI/ServiceContainer.swift
// Actor 기반 DI 컨테이너 — Swift 6 Concurrency 완전 호환

import Foundation
import Synchronization

/// Actor 기반 서비스 컨테이너 — lock-free, 재진입 안전
public actor ServiceContainer {
    public static let shared = ServiceContainer()

    private var factories: [ObjectIdentifier: @Sendable () -> any Sendable] = [:]
    private var singletons: [ObjectIdentifier: any Sendable] = [:]

    private init() {}

    // MARK: - Registration

    /// 싱글톤 인스턴스 등록
    public func register<T: Sendable>(_ type: T.Type, instance: T) {
        singletons[ObjectIdentifier(type)] = instance
    }

    /// 팩토리 등록 (매 resolve마다 새 인스턴스)
    public func registerFactory<T: Sendable>(_ type: T.Type, factory: @escaping @Sendable () -> T) {
        factories[ObjectIdentifier(type)] = factory
    }

    // MARK: - Resolution

    /// 서비스 해석 (Optional — fatalError 방지)
    public func resolve<T: Sendable>(_ type: T.Type) -> T? {
        let key = ObjectIdentifier(type)

        // 싱글톤 우선 확인
        if let singleton = singletons[key] as? T {
            return singleton
        }

        // 팩토리로 생성
        if let factory = factories[key], let instance = factory() as? T {
            return instance
        }

        return nil
    }

    /// 서비스 해석 (필수 — DEBUG 에서 assertionFailure, RELEASE 에서는 nil 반환)
    /// [Code Review 2026-04-24] `require` 명칭은 "반드시 존재" 의미를 주지만 실제는 Optional 를 반환해
    /// 계약이 모순되었다. 호출자가 "DEBUG assert + nil-fallback" 의도임을 알 수 있도록
    /// `resolveAsserted` 로 명칭 변경. 호출자는 없으므로 호환성 파쇄 없음.
    public func resolveAsserted<T: Sendable>(_ type: T.Type, file: String = #file, line: Int = #line) -> T? {
        guard let service = resolve(type) else {
            #if DEBUG
            assertionFailure("[\(file):\(line)] Service not registered: \(type)")
            #endif
            return nil
        }
        return service
    }

    /// 등록된 서비스 확인
    public func isRegistered<T: Sendable>(_ type: T.Type) -> Bool {
        let key = ObjectIdentifier(type)
        return singletons[key] != nil || factories[key] != nil
    }

    /// 모든 등록 해제 (테스트용)
    public func reset() {
        factories.removeAll()
        singletons.removeAll()
    }
}
