import Foundation
@preconcurrency import OSLog

struct LogRecord: Sendable {
    let timestamp: Date
    let level: DoomLogTraceLevel
    let subsystem: String?
    let category: String?
    let process: String?
    let pid: Int?
    let threadID: UInt64?
    let message: String
    let activityID: UInt64?
    let raw: [String: String]?
}

protocol LogStoreProviding: Sendable {
    func fetchEntries(
        since timeIntervalSinceBoot: TimeInterval,
        predicate: NSPredicate?
    ) throws -> [LogRecord]

    var bootDate: Date { get }
    var nowUptime: TimeInterval { get }
}

struct OSLogStoreProvider: LogStoreProviding, @unchecked Sendable {
    private let store: OSLogStore
    let bootDate: Date

    init() throws {
        self.store = try OSLogStore(scope: .currentProcessIdentifier)
        let uptime = ProcessInfo.processInfo.systemUptime
        self.bootDate = Date(timeIntervalSinceNow: -uptime)
    }

    var nowUptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func fetchEntries(
        since timeIntervalSinceBoot: TimeInterval,
        predicate: NSPredicate?
    ) throws -> [LogRecord] {
        let position = store.position(timeIntervalSinceLatestBoot: timeIntervalSinceBoot)
        let entries = try store.getEntries(at: position, matching: predicate)

        return entries.compactMap { entry in
            if let log = entry as? OSLogEntryLog {
                return LogRecord(
                    timestamp: log.date,
                    level: DoomLogTraceLevel(logLevel: log.level),
                    subsystem: log.subsystem,
                    category: log.category,
                    process: log.process,
                    pid: Int(log.processIdentifier),
                    threadID: log.threadIdentifier,
                    message: log.composedMessage,
                    activityID: log.activityIdentifier,
                    raw: nil
                )
            }
            if let signpost = entry as? OSLogEntrySignpost {
                let name = signpost.signpostName
                let message = "signpost \(name)"
                return LogRecord(
                    timestamp: signpost.date,
                    level: .info,
                    subsystem: signpost.subsystem,
                    category: signpost.category,
                    process: signpost.process,
                    pid: Int(signpost.processIdentifier),
                    threadID: signpost.threadIdentifier,
                    message: message,
                    activityID: signpost.activityIdentifier,
                    raw: [
                        "signpostName": name
                    ]
                )
            }
            return nil
        }
    }
}

private extension DoomLogTraceLevel {
    init(logLevel: OSLogEntryLog.Level) {
        switch logLevel {
        case .debug:
            self = .debug
        case .info:
            self = .info
        case .notice:
            self = .notice
        case .error:
            self = .error
        case .fault:
            self = .fault
        case .undefined:
            self = .debug
        @unknown default:
            self = .debug
        }
    }
}
