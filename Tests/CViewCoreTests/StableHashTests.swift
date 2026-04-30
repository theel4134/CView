// MARK: - StableHashTests.swift
// CViewCore - StableHash (FNV-1a) 결정성 + 매핑 테스트

import Testing
import Foundation
@testable import CViewCore

@Suite("StableHash (FNV-1a)")
struct StableHashTests {

    @Test("Empty string has canonical FNV offset basis")
    func emptyString() {
        #expect(StableHash.fnv1a("") == 0xcbf29ce484222325)
    }

    @Test("Same input produces same hash (determinism)")
    func determinism() {
        let samples = ["리그 오브 레전드", "스타크래프트", "발로란트", "", "A", "🎮"]
        for s in samples {
            let h1 = StableHash.fnv1a(s)
            let h2 = StableHash.fnv1a(s)
            #expect(h1 == h2, "hash should be deterministic for: \(s)")
        }
    }

    @Test("Different inputs produce different hashes (basic collision sanity)")
    func collisionSanity() {
        let unique = Set(["a", "b", "c", "ab", "ba", "리그", "발로", "스타"]
            .map { StableHash.fnv1a($0) })
        #expect(unique.count == 8)
    }

    @Test("Known FNV-1a test vector — 'a'")
    func knownVectorA() {
        // FNV-1a 64-bit of "a" = 0xaf63dc4c8601ec8c (official test vector)
        #expect(StableHash.fnv1a("a") == 0xaf63dc4c8601ec8c)
    }

    @Test("Known FNV-1a test vector — 'foobar'")
    func knownVectorFoobar() {
        // FNV-1a 64-bit of "foobar" = 0x85944171f73967e8
        #expect(StableHash.fnv1a("foobar") == 0x85944171f73967e8)
    }

    // MARK: - index(modulo:)

    @Test("index(modulo:) returns value in [0, count)")
    func indexBounds() {
        let samples = ["카테고리1", "category_xyz", "", "a"]
        for s in samples {
            for count in [1, 3, 8, 16, 100] {
                let idx = StableHash.index(s, modulo: count)
                #expect(idx >= 0 && idx < count,
                        "idx=\(idx) out of range for count=\(count), input=\(s)")
            }
        }
    }

    @Test("index(modulo:) is deterministic across calls")
    func indexDeterministic() {
        let input = "발로란트"
        let runs = (0..<100).map { _ in StableHash.index(input, modulo: 8) }
        #expect(Set(runs).count == 1, "index should be stable across repeated calls")
    }
}
