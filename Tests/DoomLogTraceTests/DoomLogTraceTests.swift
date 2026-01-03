import Foundation
import Testing
@testable import DoomLogTrace

@Test func dedupesIdenticalEntries() async throws {
    let bootDate = Date(timeIntervalSince1970: 0)
    let message = "duplicate"
    let record = LogRecord(
        timestamp: bootDate.addingTimeInterval(1),
        level: .info,
        subsystem: "test",
        category: "dedupe",
        process: "proc",
        pid: 1,
        threadID: 2,
        message: message,
        activityID: 3,
        raw: nil
    )

    let provider = TestLogStoreProvider(
        bootDate: bootDate,
        nowUptime: 5,
        entries: [record, record]
    )

    let config = DoomLogTraceConfig(
        subsystem: "test",
        category: "dedupe",
        pollInterval: .milliseconds(10),
        lookback: .seconds(10),
        maxEventsPerPoll: 10,
        dedupeWindow: 16
    )

    let events = try await collectEvents(config: config, provider: provider, duration: .milliseconds(50))
    #expect(events.count == 1)
}

@Test func backpressureAdvancesCursor() async throws {
    let bootDate = Date(timeIntervalSince1970: 0)
    let entries = [
        makeRecord(bootDate: bootDate, seconds: 1, message: "one"),
        makeRecord(bootDate: bootDate, seconds: 2, message: "two"),
        makeRecord(bootDate: bootDate, seconds: 3, message: "three")
    ]

    let provider = TestLogStoreProvider(
        bootDate: bootDate,
        nowUptime: 10,
        entries: entries
    )

    let config = DoomLogTraceConfig(
        pollInterval: .milliseconds(5),
        lookback: .seconds(10),
        maxEventsPerPoll: 1,
        dedupeWindow: 8
    )

    let events = try await collectEvents(config: config, provider: provider, duration: .milliseconds(50))
    #expect(events.count == 1)

    let cursors = provider.fetchCursors()
    #expect(cursors.count >= 2)
    #expect(cursors[1] >= 3)
}

@Test func cancellationStopsPolling() async throws {
    let bootDate = Date(timeIntervalSince1970: 0)
    let provider = TestLogStoreProvider(
        bootDate: bootDate,
        nowUptime: 1,
        entries: []
    )

    let config = DoomLogTraceConfig(pollInterval: .milliseconds(5))
    let streamer = OSLogStoreStreamer(config: config, storeProvider: provider)

    let task = Task {
        try await streamer.run { _ in }
    }

    try await Task.sleep(nanoseconds: 20_000_000)
    task.cancel()

    let result = await task.result
    switch result {
    case .success:
        break
    case .failure(let error):
        #expect(error is CancellationError)
    }
}

@Test func debugBuildEnabled() async throws {
    #expect(DoomLogTrace.isEnabledByBuild == true)
}

private func makeRecord(bootDate: Date, seconds: TimeInterval, message: String) -> LogRecord {
    LogRecord(
        timestamp: bootDate.addingTimeInterval(seconds),
        level: .info,
        subsystem: "test",
        category: "backpressure",
        process: "proc",
        pid: 1,
        threadID: 2,
        message: message,
        activityID: 3,
        raw: nil
    )
}

private func collectEvents(
    config: DoomLogTraceConfig,
    provider: TestLogStoreProvider,
    duration: Duration
) async throws -> [DoomLogTraceEvent] {
    let streamer = OSLogStoreStreamer(config: config, storeProvider: provider)
    let collector = EventCollector()

    let task = Task {
        try await streamer.run { event in
            collector.append(event)
        }
    }

    try await Task.sleep(nanoseconds: duration.nanoseconds)
    task.cancel()
    _ = await task.result
    return collector.values()
}

private final class TestLogStoreProvider: LogStoreProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [LogRecord]
    let bootDate: Date
    var nowUptime: TimeInterval
    private var cursors: [TimeInterval] = []

    init(bootDate: Date, nowUptime: TimeInterval, entries: [LogRecord]) {
        self.bootDate = bootDate
        self.nowUptime = nowUptime
        self.entries = entries
    }

    func fetchEntries(since timeIntervalSinceBoot: TimeInterval, predicate: NSPredicate?) throws -> [LogRecord] {
        lock.lock()
        cursors.append(timeIntervalSinceBoot)
        let snapshot = entries.filter { entry in
            entry.timestamp.timeIntervalSince(bootDate) >= timeIntervalSinceBoot
        }
        lock.unlock()
        return snapshot
    }

    func fetchCursors() -> [TimeInterval] {
        lock.lock()
        let snapshot = cursors
        lock.unlock()
        return snapshot
    }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DoomLogTraceEvent] = []

    func append(_ event: DoomLogTraceEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func values() -> [DoomLogTraceEvent] {
        lock.lock()
        let snapshot = events
        lock.unlock()
        return snapshot
    }
}

private extension Duration {
    var nanoseconds: UInt64 {
        let components = self.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        let total = (seconds + attoseconds) * 1_000_000_000
        return total <= 0 ? 0 : UInt64(total)
    }
}
