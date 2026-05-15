//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Logging API open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift Logging API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Logging API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// MARK: - SLG-0006: Task-local Logger extensions
//
// This file is self-contained and depends only on `Logger`. It can ship without
// SLG-0007 (`withLoggerFactory`) or SLG-0008 (`Logger.current`).
//
// The forwarders are `@inlinable` and pass `@autoclosure` parameters by expression
// (`message()`, `metadata()`, …) so Logger's internal log-level check can defer
// evaluation past the filter. Only the most feature-rich overload (with the `error:`
// parameter) is forwarded per emit level; call sites without `error:` resolve to it
// via the defaulted argument.

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension TaskLocal where Value == Logger {
    /// Push `metadata` onto the bound logger for the duration of `operation`. Inside the
    /// closure, the task-local resolves to a copy of the outer logger with the given
    /// metadata merged in. Nested scopes accumulate; inner keys override outer.
    public func withMetadata<Result>(
        merging metadata: Logger.Metadata,
        _ operation: () throws -> Result
    ) rethrows -> Result {
        try self.withValue(self.wrappedValue.withMetadata(merging: metadata)) {
            try operation()
        }
    }

    /// Async variant of ``withMetadata(merging:_:)-(_:_:)``. See that function for semantics.
    public func withMetadata<Result>(
        merging metadata: Logger.Metadata,
        _ operation: nonisolated(nonsending) () async throws -> Result
    ) async rethrows -> Result {
        try await self.withValue(self.wrappedValue.withMetadata(merging: metadata)) {
            try await operation()
        }
    }

    // MARK: - log

    @inlinable
    public func log(
        level: Logger.Level,
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.wrappedValue.log(
            level: level,
            message(),
            error: error(),
            metadata: metadata(),
            source: source(),
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - trace

    @inlinable
    public func trace(
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.wrappedValue.trace(
            message(),
            error: error(),
            metadata: metadata(),
            source: source(),
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - debug

    @inlinable
    public func debug(
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.wrappedValue.debug(
            message(),
            error: error(),
            metadata: metadata(),
            source: source(),
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - info

    @inlinable
    public func info(
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.wrappedValue.info(
            message(),
            error: error(),
            metadata: metadata(),
            source: source(),
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - notice

    @inlinable
    public func notice(
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.wrappedValue.notice(
            message(),
            error: error(),
            metadata: metadata(),
            source: source(),
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - warning

    @inlinable
    public func warning(
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.wrappedValue.warning(
            message(),
            error: error(),
            metadata: metadata(),
            source: source(),
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - error

    @inlinable
    public func error(
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.wrappedValue.error(
            message(),
            error: error(),
            metadata: metadata(),
            source: source(),
            file: file,
            function: function,
            line: line
        )
    }

    // MARK: - critical

    @inlinable
    public func critical(
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.wrappedValue.critical(
            message(),
            error: error(),
            metadata: metadata(),
            source: source(),
            file: file,
            function: function,
            line: line
        )
    }
}
