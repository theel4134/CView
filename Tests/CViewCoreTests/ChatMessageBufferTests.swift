// MARK: - ChatMessageBufferTests.swift
// CViewCore — ChatMessageBuffer 링 버퍼 테스트

import Testing
import Foundation
@testable import CViewCore

// MARK: - Test Helpers

private func makeItem(_ content: String, id: String? = nil) -> ChatMessageItem {
    ChatMessageItem(
        id: id ?? UUID().uuidString,
        userId: "user1",
        nickname: "테스터",
        content: content,
        timestamp: Date(),
        type: .normal,
        badgeImageURL: nil,
        emojis: [:],
        donationAmount: nil,
        donationType: nil,
        subscriptionMonths: nil,
        profileImageUrl: nil,
        isNotice: false,
        isSystem: false
    )
}

// MARK: - Initialization

@Suite("ChatMessageBuffer — Initialization")
struct ChatMessageBufferInitTests {

    @Test("Default capacity is 200")
    func defaultCapacity() {
        let buffer = ChatMessageBuffer()
        #expect(buffer.capacity == 200)
    }

    @Test("Custom capacity is respected")
    func customCapacity() {
        let buffer = ChatMessageBuffer(capacity: 50)
        #expect(buffer.capacity == 50)
    }

    @Test("Minimum capacity is enforced to 10")
    func minimumCapacity() {
        let buffer = ChatMessageBuffer(capacity: 3)
        #expect(buffer.capacity == 10)
    }

    @Test("Initial state is empty")
    func initialEmpty() {
        let buffer = ChatMessageBuffer()
        #expect(buffer.isEmpty)
        #expect(buffer.count == 0)
        #expect(buffer.first == nil)
        #expect(buffer.last == nil)
    }
}

// MARK: - Append

@Suite("ChatMessageBuffer — Append")
struct ChatMessageBufferAppendTests {

    @Test("Single append increments count")
    func singleAppend() {
        var buffer = ChatMessageBuffer(capacity: 10)
        buffer.append(makeItem("hello"))
        #expect(buffer.count == 1)
        #expect(!buffer.isEmpty)
    }

    @Test("Append preserves order (oldest first)")
    func appendOrder() {
        var buffer = ChatMessageBuffer(capacity: 10)
        buffer.append(makeItem("first"))
        buffer.append(makeItem("second"))
        buffer.append(makeItem("third"))

        #expect(buffer[0].content == "first")
        #expect(buffer[1].content == "second")
        #expect(buffer[2].content == "third")
    }

    @Test("first and last return correct items")
    func firstLast() {
        var buffer = ChatMessageBuffer(capacity: 10)
        buffer.append(makeItem("A"))
        buffer.append(makeItem("B"))
        buffer.append(makeItem("C"))

        #expect(buffer.first?.content == "A")
        #expect(buffer.last?.content == "C")
    }

    @Test("Eviction at capacity drops oldest")
    func eviction() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<15 {
            buffer.append(makeItem("msg\(i)"))
        }

        #expect(buffer.count == 10)
        // Oldest 5 evicted; remaining: msg5..msg14
        #expect(buffer.first?.content == "msg5")
        #expect(buffer.last?.content == "msg14")
    }

    @Test("Append contentsOf multiple items")
    func appendContentsOf() {
        var buffer = ChatMessageBuffer(capacity: 10)
        let items = (0..<5).map { makeItem("batch\($0)") }
        buffer.append(contentsOf: items)

        #expect(buffer.count == 5)
        #expect(buffer[0].content == "batch0")
        #expect(buffer[4].content == "batch4")
    }

    @Test("Append contentsOf exceeding capacity keeps last N")
    func appendContentsOfOverflow() {
        var buffer = ChatMessageBuffer(capacity: 10)
        let items = (0..<20).map { makeItem("overflow\($0)") }
        buffer.append(contentsOf: items)

        #expect(buffer.count == 10)
        // Only the last 10 survive
        #expect(buffer.first?.content == "overflow10")
        #expect(buffer.last?.content == "overflow19")
    }
}

// MARK: - Removal

@Suite("ChatMessageBuffer — Removal")
struct ChatMessageBufferRemovalTests {

    @Test("removeAll clears buffer")
    func removeAll() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<5 { buffer.append(makeItem("msg\(i)")) }
        buffer.removeAll()

        #expect(buffer.isEmpty)
        #expect(buffer.count == 0)
    }

    @Test("removeAll(where:) filters correctly")
    func removeWhere() {
        var buffer = ChatMessageBuffer(capacity: 10)
        buffer.append(makeItem("keep", id: "k1"))
        buffer.append(makeItem("remove", id: "r1"))
        buffer.append(makeItem("keep", id: "k2"))

        buffer.removeAll { $0.content == "remove" }

        #expect(buffer.count == 2)
        #expect(buffer[0].id == "k1")
        #expect(buffer[1].id == "k2")
    }
}

// MARK: - Bulk Operations

@Suite("ChatMessageBuffer — Bulk Operations")
struct ChatMessageBufferBulkTests {

    @Test("replaceAll resets buffer with new items")
    func replaceAll() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<5 { buffer.append(makeItem("old\(i)")) }

        let newItems = (0..<3).map { makeItem("new\($0)") }
        buffer.replaceAll(with: newItems)

        #expect(buffer.count == 3)
        #expect(buffer[0].content == "new0")
    }

    @Test("mapInPlace transforms all items")
    func mapInPlace() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<3 { buffer.append(makeItem("msg\(i)", id: "id\(i)")) }

        buffer.mapInPlace { item in
            ChatMessageItem(
                id: item.id, userId: item.userId, nickname: "변환됨",
                content: item.content.uppercased(), timestamp: item.timestamp,
                type: item.type, badgeImageURL: nil, emojis: [:],
                donationAmount: nil, donationType: nil, subscriptionMonths: nil,
                profileImageUrl: nil, isNotice: false, isSystem: false
            )
        }

        #expect(buffer[0].content == "MSG0")
        #expect(buffer[0].nickname == "변환됨")
        #expect(buffer.count == 3)
    }

    @Test("toArray exports in order")
    func toArray() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<5 { buffer.append(makeItem("msg\(i)")) }

        let array = buffer.toArray()
        #expect(array.count == 5)
        #expect(array.first?.content == "msg0")
        #expect(array.last?.content == "msg4")
    }

    @Test("toArray after wrap-around is ordered")
    func toArrayAfterWrap() {
        var buffer = ChatMessageBuffer(capacity: 10)
        // Fill + overflow to cause wrap-around
        for i in 0..<15 { buffer.append(makeItem("msg\(i)")) }

        let array = buffer.toArray()
        #expect(array.count == 10)
        #expect(array.first?.content == "msg5")
        #expect(array.last?.content == "msg14")
    }
}

// MARK: - Resize

@Suite("ChatMessageBuffer — Resize")
struct ChatMessageBufferResizeTests {

    @Test("Resize larger preserves all items")
    func resizeLarger() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<5 { buffer.append(makeItem("msg\(i)")) }

        buffer.resize(to: 20)
        #expect(buffer.capacity == 20)
        #expect(buffer.count == 5)
        #expect(buffer[0].content == "msg0")
    }

    @Test("Resize smaller keeps most recent")
    func resizeSmaller() {
        var buffer = ChatMessageBuffer(capacity: 20)
        for i in 0..<15 { buffer.append(makeItem("msg\(i)")) }

        buffer.resize(to: 10)
        #expect(buffer.capacity == 10)
        #expect(buffer.count == 10)
        // Keeps last 10: msg5..msg14
        #expect(buffer.first?.content == "msg5")
        #expect(buffer.last?.content == "msg14")
    }

    @Test("Resize to same capacity is no-op")
    func resizeSame() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<5 { buffer.append(makeItem("msg\(i)")) }

        buffer.resize(to: 10)
        #expect(buffer.count == 5)
    }

    @Test("Resize enforces minimum of 10")
    func resizeMinimum() {
        var buffer = ChatMessageBuffer(capacity: 20)
        buffer.resize(to: 3)
        #expect(buffer.capacity == 10)
    }
}

// MARK: - RandomAccessCollection

@Suite("ChatMessageBuffer — Collection Conformance")
struct ChatMessageBufferCollectionTests {

    @Test("Iteration order matches index order")
    func iteration() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<5 { buffer.append(makeItem("msg\(i)")) }

        var contents: [String] = []
        for item in buffer {
            contents.append(item.content)
        }

        #expect(contents == ["msg0", "msg1", "msg2", "msg3", "msg4"])
    }

    @Test("startIndex is 0, endIndex is count")
    func indices() {
        var buffer = ChatMessageBuffer(capacity: 10)
        for i in 0..<3 { buffer.append(makeItem("msg\(i)")) }

        #expect(buffer.startIndex == 0)
        #expect(buffer.endIndex == 3)
    }
}
