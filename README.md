# DoomLogTrace

Debug-focused, non-realtime instrumentation that streams Apple Unified Logging entries
from the current process as an `AsyncThrowingStream`.

## Features

- Unified Logging reader via `OSLogStore` (current process only)
- Polling-based async stream with filtering and dedupe
- Debug-only by default (opt-in for release)
- Backpressure handling with cursor advancement

## Usage

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
```

## Build

```bash
swift build
```

## Test

```bash
swift test
```
