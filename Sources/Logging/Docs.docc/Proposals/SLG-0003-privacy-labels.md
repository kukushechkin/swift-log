# SLG-0003: privacy labels for metadata

Add privacy labels to metadata to enable privacy-aware logging.

## Overview

- Proposal: SLG-0003
- Author(s): [Vladimir Kukushkin](https://github.com/vladimirkukushkin)
- Status: **Awaiting Review**
- Issue: TBD
- Implementation: TBD
- Related links:
    - [Lightweight proposals process description](https://github.com/apple/swift-log/blob/main/Sources/Logging/Docs.docc/Proposals/Proposals.md)

### Introduction

This proposal introduces privacy labels for metadata values, enabling developers to mark data as `.private()` or `.public()` with configurable privacy behavior.

### Motivation

SwiftLog lacks a mechanism to mark metadata as sensitive. Developers must manually redact sensitive data or avoid structured logging for sensitive operations.

Applications need privacy controls for:
- Compliance with privacy regulations.
- Backend integration with privacy-aware systems.
- Systematic control over what data appears in logs.

### Proposed solution

Add privacy labels (`.public()` and `.private()`) through an `AttributedMetadata` API, controlled via `Logger.privacyBehavior`:

```swift
var logger = Logger(label: "my-app")
logger.privacyBehavior = .redact  // Default

logger.info("User logged in", attributedMetadata: [
    "user.id": "12345".private(),
    "action": "login".public()
])
```

Key features:
- Explicit privacy per value
- Backward compatible (existing API unchanged)
- Flexible handler support
- Global metadata merges as public

### Detailed design

#### Public API

**Core types:**
```swift
extension Logger {
    public enum PrivacyLevel: String, Sendable, CaseIterable {
        case `private` = "private"
        case `public` = "public"
    }

    public struct MetadataValueProperties: Sendable {
        public var privacyLevel: PrivacyLevel
        public init(privacyLevel: PrivacyLevel = .private)
    }

    public struct AttributedMetadataValue: Sendable {
        public let value: MetadataValue
        public let properties: MetadataValueProperties

        public init(_ value: MetadataValue, properties: MetadataValueProperties)
        public init(_ value: MetadataValue, privacy: PrivacyLevel)
    }

    public typealias AttributedMetadata = [String: AttributedMetadataValue]

    public enum PrivacyBehavior: String, Sendable, Equatable, CaseIterable {
        case log = "log"        // Log all metadata including private values
        case redact = "redact"  // Redact private values
    }

    public var privacyBehavior: Logger.PrivacyBehavior { get set }  // Defaults to .redact
}

extension LogHandler {
    var privacyBehavior: Logger.PrivacyBehavior { get set }  // Defaults to .redact
}
```

**Convenience extensions:**
```swift
extension Logger.MetadataValue {
    public func `public`() -> Logger.AttributedMetadataValue
    public func `private`() -> Logger.AttributedMetadataValue
    public func attributed(privacy: Logger.PrivacyLevel) -> Logger.AttributedMetadataValue
}

extension String {
    public func `public`() -> Logger.AttributedMetadataValue
    public func `private`() -> Logger.AttributedMetadataValue
    public func attributed(privacy: Logger.PrivacyLevel) -> Logger.AttributedMetadataValue
}
```

**Logger methods:**
```swift
extension Logger {
    public func log(level: Level, _ message: @autoclosure () -> Message,
                   attributedMetadata: @autoclosure () -> AttributedMetadata?,
                   source: @autoclosure () -> String? = nil,
                   file: String = #fileID, function: String = #function, line: UInt = #line)

    public func log(level: Level, _ message: @autoclosure () -> Message,
                   attributedMetadata: @autoclosure () -> AttributedMetadata?,
                   file: String = #fileID, function: String = #function, line: UInt = #line)

    public func trace(_ message: @autoclosure () -> Message,
                     attributedMetadata: @autoclosure () -> AttributedMetadata?,
                     source: @autoclosure () -> String? = nil,
                     file: String = #fileID, function: String = #function, line: UInt = #line)
    public func trace(_ message: @autoclosure () -> Message,
                     attributedMetadata: @autoclosure () -> AttributedMetadata?,
                     file: String = #fileID, function: String = #function, line: UInt = #line)

    public func debug(_ message: @autoclosure () -> Message,
                     attributedMetadata: @autoclosure () -> AttributedMetadata?,
                     source: @autoclosure () -> String? = nil,
                     file: String = #fileID, function: String = #function, line: UInt = #line)
    public func debug(_ message: @autoclosure () -> Message,
                     attributedMetadata: @autoclosure () -> AttributedMetadata?,
                     file: String = #fileID, function: String = #function, line: UInt = #line)

    public func info(_ message: @autoclosure () -> Message,
                    attributedMetadata: @autoclosure () -> AttributedMetadata?,
                    source: @autoclosure () -> String? = nil,
                    file: String = #fileID, function: String = #function, line: UInt = #line)
    public func info(_ message: @autoclosure () -> Message,
                    attributedMetadata: @autoclosure () -> AttributedMetadata?,
                    file: String = #fileID, function: String = #function, line: UInt = #line)

    public func notice(_ message: @autoclosure () -> Message,
                      attributedMetadata: @autoclosure () -> AttributedMetadata?,
                      source: @autoclosure () -> String? = nil,
                      file: String = #fileID, function: String = #function, line: UInt = #line)
    public func notice(_ message: @autoclosure () -> Message,
                      attributedMetadata: @autoclosure () -> AttributedMetadata?,
                      file: String = #fileID, function: String = #function, line: UInt = #line)

    public func warning(_ message: @autoclosure () -> Message,
                       attributedMetadata: @autoclosure () -> AttributedMetadata?,
                       source: @autoclosure () -> String? = nil,
                       file: String = #fileID, function: String = #function, line: UInt = #line)
    public func warning(_ message: @autoclosure () -> Message,
                       attributedMetadata: @autoclosure () -> AttributedMetadata?,
                       file: String = #fileID, function: String = #function, line: UInt = #line)

    public func error(_ message: @autoclosure () -> Message,
                     attributedMetadata: @autoclosure () -> AttributedMetadata?,
                     source: @autoclosure () -> String? = nil,
                     file: String = #fileID, function: String = #function, line: UInt = #line)
    public func error(_ message: @autoclosure () -> Message,
                     attributedMetadata: @autoclosure () -> AttributedMetadata?,
                     file: String = #fileID, function: String = #function, line: UInt = #line)

    public func critical(_ message: @autoclosure () -> Message,
                        attributedMetadata: @autoclosure () -> AttributedMetadata?,
                        source: @autoclosure () -> String? = nil,
                        file: String = #fileID, function: String = #function, line: UInt = #line)
    public func critical(_ message: @autoclosure () -> Message,
                        attributedMetadata: @autoclosure () -> AttributedMetadata?,
                        file: String = #fileID, function: String = #function, line: UInt = #line)
}
```

**LogHandler protocol:**
```swift
extension LogHandler {
    // Optional method - handlers implement to support privacy-aware logging
    public func log(level: Logger.Level, message: Logger.Message,
                   attributedMetadata: Logger.AttributedMetadata?,
                   source: String, file: String, function: String, line: UInt)
}

// Default implementation merges and filters metadata for backward compatibility
extension LogHandler {
    public func log(level: Logger.Level, message: Logger.Message,
                   attributedMetadata: Logger.AttributedMetadata?,
                   source: String, file: String, function: String, line: UInt) {
        // Merges handler.metadata, metadataProvider, and explicit attributed metadata
        // Filters to only public metadata, calls existing log(level:message:metadata:...)
    }
}
```

#### Design decisions

**No default parameter on `attributedMetadata`:** The parameter requires explicit usage to prevent ambiguity with plain metadata methods and ensure intentional privacy-aware logging.

**No global attributed metadata:** `AttributedMetadataValue` only works in log statements, not attached to a `LogHandler`.

**Handler metadata merging:** LogHandlers are responsible for merging their own `metadata` property, `metadataProvider` output, and the explicit `attributedMetadata` parameter. This is consistent with how plain metadata works - handlers control merging. Handler metadata and provider values should be treated as `.public()`. Attributed metadata from the log call takes precedence.

**Backward compatibility:** Default `LogHandler` extension filters attributed metadata to only public values, then passes them to the plain metadata log method (which handles merging with handler metadata and provider as normal). Handlers without privacy support never receive private values.

**Privacy behavior configuration:** Configured via `Logger.privacyBehavior` property (similar to `logLevel`). Options are `.log` (all metadata) or `.redact`. Propagates from Logger to LogHandler through protocol, maintaining value semantics.

 **No nested privacy**: When marking a dictionary or array as private, all contained values are treated with the same privacy level.

### API stability

- All existing APIs unchanged.
- Plain and attributed metadata APIs coexist.
- No deprecation planned.
- Adoption is optional and incremental on both application and Log Handler sides.
- Default implementation ensures existing handlers work; logging private metadata is an application concern requiring a compatible `LogHandler`.

### Future directions

Extended properties (e.g., retention policy, etc) and potential future unification of plain and attributed metadata APIs.

### Alternatives considered

**Key-based redaction:** Configure which keys should be treated as private rather than marking each value:

```swift
logger.privateKeys = ["user.id", "password", "email"]
logger.info("User action", metadata: [
    "user.id": "12345",  // Automatically private
    "action": "login"     // Automatically public
])
```

Advantages:
- Simpler API (no new types).
- Centralized configuration.
- Safer at scale (new sensitive fields update all logs automatically).
- Easier migration.

**Not chosen because:**

1. **Privacy belongs to data, not identifiers:** The same private data might be logged under different keys ("email", "user.email", "contact"), and the same key might contain different data with different privacy requirements in different contexts. Key-based redaction creates a synchronization problem—developers must maintain a separate list of "private keys" that stays in sync with actual logging code across the codebase, with no compile-time or review-time verification.

2. **Code review visibility:** With value-based privacy, reviewers see privacy decisions at the call site: `"email": user.email.private()` makes it immediately clear that data is sensitive. With key-based redaction, reviewers must cross-reference a separate configuration file, making security review significantly harder.

3. **No synchronization needed:** Value-based privacy is self-contained—privacy travels with the data at the point of use. No separate configuration to maintain, no risk of configuration drift, no runtime surprises when a key is missing from the private keys list.

4. **Pattern complexity:** Supporting patterns/regex adds complexity and potential performance concerns.

The current design prioritizes **explicitness and data-centric privacy** over **configuration-based simplicity**. Privacy decisions are made where data is logged, making them visible during code review and keeping privacy attributes coupled to the data they protect.

**Other alternatives rejected:**

- **Global default privacy level:** Makes privacy implicit rather than explicit, increasing risk of accidental exposure.
- **Pass all metadata to non-privacy-aware handlers:** Security risk; current design filters private data by default.
- **Message-level privacy:** Less granular than metadata-level privacy and requires message handling changes.
