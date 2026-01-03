import Foundation

public struct DoomLogTrace: Sendable {
    private let config: DoomLogTraceConfig
    private let storeProvider: LogStoreProviding

    public init(config: DoomLogTraceConfig) throws {
        guard Self.isSupported else {
            throw DoomLogTraceError.unsupportedPlatform
        }
        if !Self.isEnabledByBuild && !config.enabledInRelease {
            throw DoomLogTraceError.disabledInThisBuild
        }

        let provider: LogStoreProviding
        do {
            provider = try OSLogStoreProvider()
        } catch {
            throw DoomLogTraceError.storeUnavailable(error.localizedDescription)
        }

        self.config = config
        self.storeProvider = provider
    }

    init(config: DoomLogTraceConfig, storeProvider: LogStoreProviding) throws {
        guard Self.isSupported else {
            throw DoomLogTraceError.unsupportedPlatform
        }
        if !Self.isEnabledByBuild && !config.enabledInRelease {
            throw DoomLogTraceError.disabledInThisBuild
        }
        self.config = config
        self.storeProvider = storeProvider
    }

    public func events() -> AsyncThrowingStream<DoomLogTraceEvent, Error> {
        let config = config
        let storeProvider = storeProvider

        return AsyncThrowingStream { continuation in
            let task = Task {
                let streamer = OSLogStoreStreamer(config: config, storeProvider: storeProvider)
                do {
                    try await streamer.run { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func makeDefault(subsystem: String, category: String? = nil) -> DoomLogTraceConfig {
        DoomLogTraceConfig(subsystem: subsystem, category: category)
    }

    public static var isSupported: Bool {
#if canImport(OSLog)
        if #available(macOS 13, iOS 16, *) {
            return true
        }
        return false
#else
        return false
#endif
    }

    public static var isEnabledByBuild: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }
}
