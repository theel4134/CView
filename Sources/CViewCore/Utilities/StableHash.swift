// MARK: - StableHash.swift
// CViewCore/Utilities - Deterministic string hashing
//
// Swift의 `String.hashValue`는 프로세스마다 랜덤화된 seed를 사용하므로
// UI 색/아이콘 선택 같이 **프로세스 간 일관성**이 필요한 곳에서는 사용 불가.
// FNV-1a 64비트 해시를 사용하여 같은 입력 → 같은 출력 보장.

import Foundation

public enum StableHash {

    /// FNV-1a 64bit 해시.
    /// - 재시작 후에도 동일 문자열 → 동일 해시 보장.
    /// - 암호학적 용도 아님. UI 파생 인덱스용.
    public static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return h
    }

    /// 문자열을 주어진 배열 길이 `count`에 맞는 인덱스로 매핑.
    public static func index(_ s: String, modulo count: Int) -> Int {
        precondition(count > 0, "count must be > 0")
        return Int(fnv1a(s) % UInt64(count))
    }
}
