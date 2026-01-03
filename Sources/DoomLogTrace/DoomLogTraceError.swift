public enum DoomLogTraceError: Error, Sendable {
    case unsupportedPlatform
    case storeUnavailable(String)
    case permissionDenied(String)
    case iterationFailed(String)
    case disabledInThisBuild
}
