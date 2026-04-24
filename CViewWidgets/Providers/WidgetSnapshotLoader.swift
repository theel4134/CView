// MARK: - WidgetSnapshotLoader.swift
// 위젯 extension 측: App Group 컨테이너에서 스냅샷 로드.
//
// CViewCore.WidgetSnapshot 의 정적 load() 를 그대로 사용하지만,
// extension 전용 placeholder/sample 헬퍼를 한 곳에 모은다.

import Foundation
import CViewCore

enum WidgetSnapshotLoader {
    /// App Group(또는 fallback) 에서 최신 스냅샷 로드.
    static func load() -> WidgetSnapshot {
        WidgetSnapshot.load() ?? .empty
    }

    /// 위젯 갤러리 placeholder/preview 용 mock.
    static var preview: WidgetSnapshot { .preview }
}
