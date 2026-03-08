// MARK: - ChatMessageBuffer.swift
// CViewCore - Ring buffer for chat message virtualization
// O(1) append with automatic oldest-message eviction at capacity

import Foundation

/// A fixed-capacity ring buffer for chat messages.
/// Automatically evicts the oldest messages when capacity is exceeded.
/// Conforms to `RandomAccessCollection` for direct use with SwiftUI `ForEach`.
public struct ChatMessageBuffer: RandomAccessCollection, Sendable {
    public typealias Element = ChatMessageItem
    public typealias Index = Int

    // MARK: - Storage

    /// Internal ring buffer storage (fixed-size, optional slots)
    private var storage: ContiguousArray<ChatMessageItem?>
    /// Index of the oldest (first) logical element
    private var head: Int = 0
    /// Number of valid/active elements
    private var _count: Int = 0
    /// Maximum number of messages to retain
    public private(set) var capacity: Int

    // MARK: - Initialization

    /// Create a buffer with specified capacity (minimum 10).
    public init(capacity: Int = 200) {
        self.capacity = Swift.max(capacity, 10)
        self.storage = ContiguousArray(repeating: nil, count: self.capacity)
    }

    // MARK: - RandomAccessCollection

    public var startIndex: Int { 0 }
    public var endIndex: Int { _count }
    public var count: Int { _count }
    public var isEmpty: Bool { _count == 0 }

    /// Access the element at `logicalIndex` (0 = oldest visible message).
    public subscript(logicalIndex: Int) -> ChatMessageItem {
        precondition(logicalIndex >= 0 && logicalIndex < _count,
                     "ChatMessageBuffer index \(logicalIndex) out of range [0..<\(_count)]")
        guard let item = storage[(head + logicalIndex) % storage.count] else {
            fatalError("ChatMessageBuffer corrupted: nil at valid index \(logicalIndex)")
        }
        return item
    }

    public var first: ChatMessageItem? {
        guard _count > 0 else { return nil }
        return storage[head]
    }

    public var last: ChatMessageItem? {
        guard _count > 0 else { return nil }
        return storage[(head + _count - 1) % storage.count]
    }

    // MARK: - Append

    /// Append a single message. O(1). Evicts the oldest when at capacity.
    public mutating func append(_ element: ChatMessageItem) {
        let insertIdx = (head + _count) % storage.count
        storage[insertIdx] = element
        if _count == capacity {
            // Buffer full — advance head to drop oldest
            head = (head + 1) % storage.count
        } else {
            _count += 1
        }
    }

    /// Append multiple messages. Evicts oldest as needed.
    /// Optimized: if `elements.count >= capacity`, only the last `capacity` elements survive.
    public mutating func append(contentsOf elements: [ChatMessageItem]) {
        if elements.count >= capacity {
            // More new items than capacity; reset and fill from tail
            let start = elements.count - capacity
            head = 0
            _count = 0
            for i in start..<elements.count {
                let idx = _count
                storage[idx] = elements[i]
                _count += 1
            }
            return
        }
        for element in elements {
            append(element)
        }
    }

    // MARK: - Removal

    /// Remove all messages.
    public mutating func removeAll(keepingCapacity keep: Bool = false) {
        // Nil out all slots
        for i in 0..<storage.count { storage[i] = nil }
        head = 0
        _count = 0
    }

    /// Remove all messages matching a predicate. O(n) rebuild.
    public mutating func removeAll(where predicate: (ChatMessageItem) -> Bool) {
        let surviving = toArray().filter { !predicate($0) }
        removeAll(keepingCapacity: true)
        for item in surviving { append(item) }
    }

    // MARK: - Bulk Operations

    /// Replace all items with a new array (e.g., after re-filtering).
    public mutating func replaceAll(with items: [ChatMessageItem]) {
        removeAll(keepingCapacity: true)
        append(contentsOf: items)
    }

    /// Transform every item in place without reallocation.
    public mutating func mapInPlace(_ transform: (ChatMessageItem) -> ChatMessageItem) {
        for i in 0..<_count {
            let idx = (head + i) % storage.count
            if let item = storage[idx] {
                storage[idx] = transform(item)
            }
        }
    }

    // MARK: - Capacity Management

    /// Resize the buffer. Keeps the most recent `min(count, newCapacity)` messages.
    public mutating func resize(to newCapacity: Int) {
        let newCap = Swift.max(newCapacity, 10)
        guard newCap != capacity else { return }
        let currentItems = toArray()
        capacity = newCap
        storage = ContiguousArray(repeating: nil, count: newCap)
        head = 0
        _count = 0
        // Re-add keeping only the tail
        let start = Swift.max(0, currentItems.count - newCap)
        for i in start..<currentItems.count {
            append(currentItems[i])
        }
    }

    // MARK: - Conversion

    /// Export items as an ordered array (oldest → newest).
    public func toArray() -> [ChatMessageItem] {
        var result = [ChatMessageItem]()
        result.reserveCapacity(_count)
        for i in 0..<_count {
            if let item = storage[(head + i) % storage.count] {
                result.append(item)
            }
        }
        return result
    }
}
