# LogTap – Spec

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
#### `public struct LogTapConfig: Sendable`
Configuration for a tap instance.

Fields:
- `subsystem: String?`  
- `category: String?`
- `minimumLevel: LogTapLevel` (default: `.debug`)
- `pollInterval: Duration` (default: 250ms)
- `lookback: Duration` (default: 2s) – initial “catch-up” window
- `maxEventsPerPoll: Int` (default: 2000) – backpressure guard
- `dedupeWindow: Int` (default: 4096) – number of recent event fingerprints to remember
- `includeSignposts: Bool` (default: false)
- `includeTraceIDs: Bool` (default: true if available)
- `enabledInRelease: Bool` (default: false)

#### `public enum LogTapLevel: Int, Sendable, Comparable`
Represents levels in increasing severity:
- `debug`, `info`, `notice`, `error`, `fault`

Provide a comparator and mapping from `OSLogEntryLog.Level` when available.

#### `public struct LogEvent: Sendable, Codable`
Normalized event model (not tied to OSLog types):
- `timestamp: Date`
- `level: LogTapLevel`
- `subsystem: String?`
- `category: String?`
- `process: String?`
- `pid: Int?`
- `threadID: UInt64?` (if obtainable)
- `message: String`
- `activityID: UInt64?` (if obtainable)
- `raw: [String:String]?` (optional extra fields for forward compat)

### Entry Point
#### `public struct LogTap: Sendable`
Create a tap that reads unified log entries and emits `LogEvent`s.

API:
- `public init(config: LogTapConfig) throws`
- `public func events() -> AsyncThrowingStream<LogEvent, Error>`

Convenience:
- `public static func makeDefault(subsystem: String, category: String? = nil) -> LogTapConfig`
- `public static var isSupported: Bool` (availability check)
- `public static var isEnabledByBuild: Bool`  
  - true in DEBUG
  - false in Release unless `enabledInRelease == true`

### Error Model
#### `public enum LogTapError: Error, Sendable`
- `unsupportedPlatform`
- `storeUnavailable(String)`
- `permissionDenied(String)`
- `iterationFailed(String)`
- `disabledInThisBuild`

Errors should be human-readable and include a brief “what to do next” hint.

## Behavior Requirements
### Store Scope
- Default to `OSLogStore(scope: .currentProcessIdentifier)`.

### Streaming Model (Polling)
- Implement “fake streaming” by polling:
  1. establish a cursor date = `now - lookback`
  2. on each tick:
     - compute store position at cursor date
     - enumerate entries matching predicate
     - emit new entries
     - advance cursor date to newest emitted timestamp + epsilon

### Filtering
- Hard filter with `NSPredicate` when possible:
  - subsystem/category
  - process/pid when available
- Soft filter in Swift:
  - minimum level mapping
  - include/exclude signposts
- Do not rely on `composedMessage` parsing beyond taking it as the message string.

### De-duplication
Because polling can re-read at the cursor boundary:
- Maintain an LRU-ish ring of recent fingerprints (`dedupeWindow`).
- Fingerprint suggestion:
  - `timestamp.timeIntervalSinceReferenceDate`
  - `level`
  - `message`
  - `subsystem/category` (if present)
- If a fingerprint is already in the ring, skip.

### Backpressure
If more than `maxEventsPerPoll` are encountered in one tick:
- Emit up to the cap.
- Advance cursor date to the latest timestamp seen among scanned events (even if not emitted) to avoid getting stuck.
- Optionally log a diagnostic to `Logger(subsystem:..., category:"LogTap")` indicating truncation (DEBUG only).

### Cancellation / Termination
- `AsyncThrowingStream` should cancel cleanly:
  - stop polling when task is cancelled
  - finish stream on cancellation without throwing
- Provide `onTermination` to cancel the polling task.

### Build Gating
- Default: compile and run only in DEBUG builds.
- In Release:
  - if `enabledInRelease == false`, constructing `LogTap` throws `disabledInThisBuild`.
  - If enabled, behavior is the same but be conservative about overhead (increase poll interval minimum to e.g. 1s).

## Output Helpers (Optional, but useful)
Include small utilities (non-essential but handy):

### JSONL Writer
`public struct LogEventJSONLWriter`
- init with `FileHandle` or file URL
- `func write(_ event: LogEvent) throws`
- newline-delimited JSON, one event per line

### In-memory Ring Buffer
`public actor LogEventRingBuffer`
- fixed capacity
- `append(_:)`, `snapshot() -> [LogEvent]`

## Package Structure
- Package name: `LogTap`
- Targets:
  - `LogTap` (library)
  - `LogTapTests` (unit tests)

Suggested folders:
- `Sources/LogTap/LogTap.swift`
- `Sources/LogTap/LogTapConfig.swift`
- `Sources/LogTap/LogEvent.swift`
- `Sources/LogTap/Internal/OSLogStoreStreamer.swift`
- `Sources/LogTap/Utilities/JSONLWriter.swift` (optional)
- `Sources/LogTap/Utilities/RingBuffer.swift` (optional)

## Tests
Write unit tests that do not require accessing the real unified log store.

Approach:
- Abstract the “entry source” behind a protocol:
  - `LogEntrySource` with `getEntries(since: Date) -> [LogEvent]` (or similar)
- Provide:
  - `OSLogStoreEntrySource` (real)
  - `MockEntrySource` (tests)

Test cases:
- De-dupe works (same fingerprint repeated doesn’t emit twice)
- Cursor advances correctly
- Backpressure cap enforced
- Cancellation stops polling
- Build gating (Release path throws unless enabled flag true)
- JSONL writer produces valid JSON per line (if implemented)

## Example Usage (README snippet)
Provide a minimal example in the README or doc comment:

```swift
import LogTap

let config = LogTapConfig(
  subsystem: "com.yourco.yourapp",
  category: "FailQuiet",
  minimumLevel: .debug
)

let tap = try LogTap(config: config)

Task {
  for try await e in tap.events() {
    print("\(e.timestamp) [\(e.level)] \(e.message)")
  }
}
```

## Performance Notes
- Polling interval defaults to 250ms, but should clamp to >= 100ms.
- Avoid heavy string processing.
- Use predicates to narrow results early.
- Keep dedupe ring bounded.

## Deliverables
- Working Swift Package committed to repo.
- Clean public API and docs/comments.
- Tests passing.
- No private API usage.
