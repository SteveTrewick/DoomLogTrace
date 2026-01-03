# DoomLogTrace – Spec

## Goal
Build a small Swift Package that provides **debug-focused**, **non-critical**, **non-realtime** instrumentation by reading Apple Unified Logging entries for the **current process** and exposing them as an `AsyncSequence`.

This is intended as “tools to make tools” scaffolding for build/debug sessions. It should be safe to leave in the repo, but easy to compile out for release.

## Non-goals
- A guaranteed real-time stream or lossless delivery.
- Reliance on private Apple APIs.
- A full featured log viewer UI (package is headless/core only).
- Cross-process/system-wide log collection by default (keep it simple and safe).

## Platform / Tooling
- Swift Package Manager package.
- Swift 6, concurrency-first APIs.
- Targets:
  - macOS 12+ (primary)
  - iOS 15+ (best effort, API availability permitting)
- Uses **Unified Logging** frameworks:
  - `OSLog`
  - `OSLogStore` (available on Apple platforms; gate APIs by availability)

> Note: Some `OSLogStore` capabilities vary by platform and entitlements. The package must degrade gracefully with clear errors.

## Public API
Expose a minimal and stable API surface.

### Types
#### `public struct DoomLogTraceConfig: Sendable`
Configuration for a trace instance.

Fields:
- `subsystem: String?`
- `category: String?`
- `minimumLevel: DoomLogTraceLevel` (default: `.debug`)
- `pollInterval: Duration` (default: 250ms)
- `lookback: Duration` (default: 2s)
- `maxEventsPerPoll: Int` (default: 2000)
- `dedupeWindow: Int` (default: 4096)
- `includeSignposts: Bool` (default: false)
- `includeTraceIDs: Bool` (default: true if available)
- `enabledInRelease: Bool` (default: false)

#### `public enum DoomLogTraceLevel: Int, Sendable, Comparable`
- `debug`, `info`, `notice`, `error`, `fault`

#### `public struct DoomLogTraceEvent: Sendable, Codable`
- `timestamp: Date`
- `level: DoomLogTraceLevel`
- `subsystem: String?`
- `category: String?`
- `process: String?`
- `pid: Int?`
- `threadID: UInt64?`
- `message: String`
- `activityID: UInt64?`
- `raw: [String:String]?`

### Entry Point
#### `public struct DoomLogTrace: Sendable`
- `init(config: DoomLogTraceConfig) throws`
- `func events() -> AsyncThrowingStream<DoomLogTraceEvent, Error>`

Convenience:
- `static func makeDefault(subsystem: String, category: String? = nil) -> DoomLogTraceConfig`
- `static var isSupported: Bool`
- `static var isEnabledByBuild: Bool`

### Errors
#### `public enum DoomLogTraceError: Error, Sendable`
- `unsupportedPlatform`
- `storeUnavailable(String)`
- `permissionDenied(String)`
- `iterationFailed(String)`
- `disabledInThisBuild`

## Behavior Requirements
### Store Scope
- `OSLogStore(scope: .currentProcessIdentifier)`

### Streaming Model
Polling-based “fake stream”:
1. cursor = `now - lookback`
2. enumerate forward
3. emit
4. advance cursor + epsilon

### Filtering
- Hard filter: `NSPredicate` (subsystem/category/process)
- Soft filter: level, signposts

### De-duplication
- Fingerprint ring buffer (`dedupeWindow`)
- Skip duplicates at cursor boundary

### Backpressure
- Cap at `maxEventsPerPoll`
- Advance cursor even when truncating
- DEBUG-only diagnostic via `Logger(subsystem:…, category:"DoomLogTrace")`

### Cancellation
- Clean `AsyncThrowingStream` termination
- Task cancellation aware

### Build Gating
- DEBUG-only by default
- Release throws unless `enabledInRelease == true`

## Utilities (Optional)
### JSONL Writer
`DoomLogTraceJSONLWriter`

### Ring Buffer
`DoomLogTraceRingBuffer`

## Package Structure
- Package: `DoomLogTrace`
- Targets:
  - `DoomLogTrace`
  - `DoomLogTraceTests`

Suggested layout:
- `Sources/DoomLogTrace/DoomLogTrace.swift`
- `Sources/DoomLogTrace/DoomLogTraceConfig.swift`
- `Sources/DoomLogTrace/DoomLogTraceEvent.swift`
- `Sources/DoomLogTrace/Internal/OSLogStoreStreamer.swift`

## Tests
- Mockable entry source
- De-dupe
- Cursor advance
- Backpressure
- Cancellation
- Build gating

## Example
```swift
import DoomLogTrace

let config = DoomLogTraceConfig(
  subsystem: "com.yourco.yourapp",
  category: "FailQuiet",
  minimumLevel: .debug
)

let trace = try DoomLogTrace(config: config)

Task {
  for try await e in trace.events() {
    print("\(e.timestamp) [\(e.level)] \(e.message)")
  }
}
