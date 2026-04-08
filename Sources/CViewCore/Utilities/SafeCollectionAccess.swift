// MARK: - CViewCore/Utilities/SafeCollectionAccess.swift
// 안전한 컬렉션 인덱스 접근 — 인덱스 초과 크래시 방지

extension Collection {
    /// 안전한 인덱스 접근 — 범위 초과 시 nil 반환 (크래시 방지)
    public subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
