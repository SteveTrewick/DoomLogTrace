import Foundation

public struct DoomLogTraceConfig: Sendable {
    public var subsystem: String?
    public var category: String?
    public var minimumLevel: DoomLogTraceLevel
    public var pollInterval: Duration
    public var lookback: Duration
    public var maxEventsPerPoll: Int
    public var dedupeWindow: Int
    public var includeSignposts: Bool
    public var includeTraceIDs: Bool
    public var enabledInRelease: Bool

    public init(
        subsystem: String? = nil,
        category: String? = nil,
        minimumLevel: DoomLogTraceLevel = .debug,
        pollInterval: Duration = .milliseconds(250),
        lookback: Duration = .seconds(2),
        maxEventsPerPoll: Int = 2000,
        dedupeWindow: Int = 4096,
        includeSignposts: Bool = false,
        includeTraceIDs: Bool = true,
        enabledInRelease: Bool = false
    ) {
        self.subsystem = subsystem
        self.category = category
        self.minimumLevel = minimumLevel
        self.pollInterval = pollInterval
        self.lookback = lookback
        self.maxEventsPerPoll = maxEventsPerPoll
        self.dedupeWindow = dedupeWindow
        self.includeSignposts = includeSignposts
        self.includeTraceIDs = includeTraceIDs
        self.enabledInRelease = enabledInRelease
    }
}
