//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Logging API open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Logging API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Logging API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import Logging

/// A wrapper that adds sensitivity-aware logging capabilities to any `LogHandler`.
///
/// This wrapper intercepts log events, merges handler and provider metadata, applies redaction
/// based on the configured `sensitivityBehavior`, then forwards the processed event to the
/// wrapped handler.
///
/// ## Example Usage
///
/// ```swift
/// let streamHandler = StreamLogHandler.standardOutput(label: "my-app")
/// var handler = SensitivityAwareLogHandlerWrapper(
///     wrapping: streamHandler,
///     sensitivityBehavior: .redact
/// )
///
/// let logger = Logger(label: "my-app") { _ in handler }
///
/// logger.log(level: .info, "User action", metadata: [
///     "user.id": "\(userId, sensitivity: .sensitive)",
///     "action": "\(action, sensitivity: .public)"
/// ])
/// ```
public struct SensitivityAwareLogHandlerWrapper: LogHandler {
    /// The redaction marker used for redacted values.
    public static let redactionMarker = "<redacted>"

    /// Defines how sensitive metadata should be handled.
    public enum SensitivityBehavior: Sendable {
        /// Log all metadata including values marked as sensitive.
        case log

        /// Redact metadata values marked with `.sensitive`.
        case redact
    }

    private var wrappedHandler: any LogHandler

    /// The sensitivity behavior for this handler.
    public var sensitivityBehavior: SensitivityBehavior

    /// The metadata provider.
    ///
    /// Stored on the wrapper, not forwarded to the wrapped handler. The wrapper merges
    /// provider metadata in its own `log(event:)` before forwarding the fully-merged event
    /// to the wrapped handler, avoiding double-merge.
    public var metadataProvider: Logger.MetadataProvider?

    public var logLevel: Logger.Level {
        get { self.wrappedHandler.logLevel }
        set { self.wrappedHandler.logLevel = newValue }
    }

    public var metadata: Logger.Metadata = [:]

    /// Creates a sensitivity-aware wrapper around an existing log handler.
    ///
    /// - Parameters:
    ///   - wrappedHandler: The log handler to wrap.
    ///   - sensitivityBehavior: How sensitive metadata should be handled. Defaults to `.redact`.
    public init(wrapping wrappedHandler: any LogHandler, sensitivityBehavior: SensitivityBehavior = .redact) {
        var handler = wrappedHandler
        self.metadataProvider = handler.metadataProvider
        handler.metadataProvider = nil
        self.wrappedHandler = handler
        self.sensitivityBehavior = sensitivityBehavior
    }

    public func log(event: LogEvent) {
        var merged = self.metadata

        if let provider = self.metadataProvider {
            let provided = provider.get()
            merged.merge(provided, uniquingKeysWith: { _, rhs in rhs })
        }

        if let eventMetadata = event.metadata {
            merged.merge(eventMetadata, uniquingKeysWith: { _, rhs in rhs })
        }

        guard !merged.isEmpty else {
            self.wrappedHandler.log(event: event)
            return
        }

        if self.sensitivityBehavior == .log {
            var mutatedEvent = event
            mutatedEvent.metadata = merged
            self.wrappedHandler.log(event: mutatedEvent)
            return
        }

        var processed = Logger.Metadata()
        for (key, value) in merged {
            if value.attributes.sensitivity == .sensitive {
                processed[key] = .string(Self.redactionMarker)
            } else {
                processed[key] = value
            }
        }

        var mutatedEvent = event
        mutatedEvent.metadata = processed
        self.wrappedHandler.log(event: mutatedEvent)
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { self.metadata[metadataKey] }
        set { self.metadata[metadataKey] = newValue }
    }
}
