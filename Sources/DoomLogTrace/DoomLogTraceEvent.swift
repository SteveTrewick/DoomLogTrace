import Foundation

public struct DoomLogTraceEvent: Sendable, Codable {
    public let timestamp: Date
    public let level: DoomLogTraceLevel
    public let subsystem: String?
    public let category: String?
    public let process: String?
    public let pid: Int?
    public let threadID: UInt64?
    public let message: String
    public let activityID: UInt64?
    public let raw: [String: String]?

    public init(
        timestamp: Date,
        level: DoomLogTraceLevel,
        subsystem: String?,
        category: String?,
        process: String?,
        pid: Int?,
        threadID: UInt64?,
        message: String,
        activityID: UInt64?,
        raw: [String: String]?
    ) {
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.process = process
        self.pid = pid
        self.threadID = threadID
        self.message = message
        self.activityID = activityID
        self.raw = raw
    }
}
