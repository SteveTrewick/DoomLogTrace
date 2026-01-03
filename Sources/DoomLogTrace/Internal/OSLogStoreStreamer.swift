import Foundation
#if DEBUG
import OSLog
#endif

struct OSLogStoreStreamer {
    private let config: DoomLogTraceConfig
    private let storeProvider: LogStoreProviding
#if DEBUG
    private let logger = Logger(subsystem: "DoomLogTrace", category: "DoomLogTrace")
#endif

    init(config: DoomLogTraceConfig, storeProvider: LogStoreProviding) {
        self.config = config
        self.storeProvider = storeProvider
    }

    func run(emit: @Sendable (DoomLogTraceEvent) -> Void) async throws {
        var cursor = max(0, storeProvider.nowUptime - config.lookback.seconds)
        var dedupe = DoomLogTraceRingBuffer(capacity: config.dedupeWindow)
        let predicate = makePredicate(for: config)
        let maxEvents = max(0, config.maxEventsPerPoll)

        while !Task.isCancelled {
            let records: [LogRecord]
            do {
                records = try storeProvider.fetchEntries(since: cursor, predicate: predicate)
            } catch {
                throw DoomLogTraceError.iterationFailed(error.localizedDescription)
            }

            let lastFetchedTimestamp = records.last?.timestamp
            var emitted = 0

            for record in records {
                if maxEvents == 0 {
                    break
                }

                if record.level < config.minimumLevel {
                    continue
                }

                if !config.includeSignposts, record.raw?["signpostName"] != nil {
                    continue
                }

                let event = DoomLogTraceEvent(
                    timestamp: record.timestamp,
                    level: record.level,
                    subsystem: record.subsystem,
                    category: record.category,
                    process: record.process,
                    pid: record.pid,
                    threadID: config.includeTraceIDs ? record.threadID : nil,
                    message: record.message,
                    activityID: config.includeTraceIDs ? record.activityID : nil,
                    raw: record.raw
                )

                let fingerprint = fingerprint(for: event)
                if dedupe.containsOrInsert(fingerprint) {
                    continue
                }

                emit(event)
                emitted += 1

                if emitted >= maxEvents {
                    break
                }
            }

            if maxEvents > 0, records.count > maxEvents {
#if DEBUG
                logger.debug("Backpressure: emitted \(emitted) of \(records.count) records")
#endif
            }

            if let lastFetchedTimestamp {
                let nextCursor = lastFetchedTimestamp.timeIntervalSince(storeProvider.bootDate) + 0.000_001
                cursor = max(cursor, nextCursor)
            } else {
                cursor = max(cursor, storeProvider.nowUptime - 0.001)
            }

            if Task.isCancelled {
                break
            }

            try await Task.sleep(nanoseconds: config.pollInterval.nanoseconds)
        }
    }

    private func makePredicate(for config: DoomLogTraceConfig) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        if let subsystem = config.subsystem {
            predicates.append(NSPredicate(format: "subsystem == %@", subsystem))
        }

        if let category = config.category {
            predicates.append(NSPredicate(format: "category == %@", category))
        }

        if predicates.isEmpty {
            return nil
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private func fingerprint(for event: DoomLogTraceEvent) -> Int {
        var hasher = Hasher()
        hasher.combine(event.timestamp.timeIntervalSince1970)
        hasher.combine(event.level.rawValue)
        hasher.combine(event.subsystem ?? "")
        hasher.combine(event.category ?? "")
        hasher.combine(event.message)
        hasher.combine(event.activityID ?? 0)
        return hasher.finalize()
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let components = self.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds + attoseconds
    }

    var nanoseconds: UInt64 {
        let total = seconds * 1_000_000_000
        return total <= 0 ? 0 : UInt64(total)
    }
}
