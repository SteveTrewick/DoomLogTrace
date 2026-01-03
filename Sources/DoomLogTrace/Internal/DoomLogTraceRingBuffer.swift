struct DoomLogTraceRingBuffer {
    private let capacity: Int
    private var buffer: [Int] = []
    private var index: Int = 0
    private var seen: Set<Int> = []

    init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.buffer.reserveCapacity(max(0, capacity))
    }

    mutating func containsOrInsert(_ value: Int) -> Bool {
        guard capacity > 0 else {
            return false
        }

        if seen.contains(value) {
            return true
        }

        if buffer.count < capacity {
            buffer.append(value)
            seen.insert(value)
            return false
        }

        let old = buffer[index]
        seen.remove(old)
        buffer[index] = value
        seen.insert(value)
        index = (index + 1) % capacity
        return false
    }
}
