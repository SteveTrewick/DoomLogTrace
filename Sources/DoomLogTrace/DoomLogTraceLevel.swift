public enum DoomLogTraceLevel: Int, Sendable, Comparable, Codable {
    case debug = 0
    case info = 1
    case notice = 2
    case error = 3
    case fault = 4

    public static func < (lhs: DoomLogTraceLevel, rhs: DoomLogTraceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
