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

extension Logger {
    /// Create a new logger with additional metadata merged into the existing metadata.
    ///
    /// This method merges the provided metadata with the logger's current metadata,
    /// returning a new logger instance. The original logger is not modified.
    /// This method is more efficient than setting metadata items individually in a loop,
    /// as it triggers copy-on-write only once.
    ///
    /// - Parameter additionalMetadata: The metadata dictionary to merge. Values in `additionalMetadata`
    ///   will override existing values for the same keys.
    /// - Returns: A new `Logger` instance with the merged metadata.
    @inlinable
    public func with(additionalMetadata: Logger.Metadata) -> Logger {
        var newLogger = self
        if additionalMetadata.count == 1 {
            newLogger.handler.metadata[additionalMetadata.first!.key] = additionalMetadata.first!.value
        } else {
            newLogger.handler.metadata.merge(additionalMetadata) { _, new in new }
        }
        return newLogger
    }

    /// Create a new logger with a different log level.
    ///
    /// This method returns a new logger instance with the specified log level.
    /// The original logger is not modified.
    ///
    /// - Parameter logLevel: The log level to set on the new logger.
    /// - Returns: A new `Logger` instance with the specified log level.
    @inlinable
    public func with(logLevel: Logger.Level) -> Logger {
        var newLogger = self
        newLogger.logLevel = logLevel
        return newLogger
    }

    /// Create a new logger with a different log handler.
    ///
    /// This method returns a new logger instance with the specified log handler.
    /// The original logger is not modified.
    ///
    /// - Parameter handler: The log handler to use for the new logger.
    /// - Returns: A new `Logger` instance with the specified handler.
    @inlinable
    public func with(handler: any LogHandler) -> Logger {
        var newLogger = self
        newLogger.handler = handler
        return newLogger
    }

    /// Create a new logger with additional metadata and a different log level.
    ///
    /// This method efficiently applies both modifications in a single copy-on-write operation.
    /// The original logger is not modified.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - logLevel: The log level to set on the new logger.
    /// - Returns: A new `Logger` instance with the specified modifications.
    @inlinable
    public func with(additionalMetadata: Logger.Metadata, logLevel: Logger.Level) -> Logger {
        var newLogger = self
        if additionalMetadata.count == 1 {
            newLogger.handler.metadata[additionalMetadata.first!.key] = additionalMetadata.first!.value
        } else {
            newLogger.handler.metadata.merge(additionalMetadata) { _, new in new }
        }
        newLogger.logLevel = logLevel
        return newLogger
    }

    /// Create a new logger with additional metadata and a different log handler.
    ///
    /// This method efficiently applies both modifications in a single copy-on-write operation.
    /// The original logger is not modified.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - handler: The log handler to use for the new logger.
    /// - Returns: A new `Logger` instance with the specified modifications.
    @inlinable
    public func with(additionalMetadata: Logger.Metadata, handler: any LogHandler) -> Logger {
        var newLogger = self
        var newHandler = handler
        if additionalMetadata.count == 1 {
            newHandler.metadata[additionalMetadata.first!.key] = additionalMetadata.first!.value
        } else {
            newHandler.metadata.merge(additionalMetadata) { _, new in new }
        }
        newLogger.handler = newHandler
        return newLogger
    }

    /// Create a new logger with a different log level and log handler.
    ///
    /// This method efficiently applies both modifications in a single copy-on-write operation.
    /// The original logger is not modified.
    ///
    /// - Parameters:
    ///   - logLevel: The log level to set on the new logger.
    ///   - handler: The log handler to use for the new logger.
    /// - Returns: A new `Logger` instance with the specified modifications.
    @inlinable
    public func with(logLevel: Logger.Level, handler: any LogHandler) -> Logger {
        var newLogger = self
        var newHandler = handler
        newHandler.logLevel = logLevel
        newLogger.handler = newHandler
        return newLogger
    }

    /// Create a new logger with additional metadata, a different log level, and a different log handler.
    ///
    /// This method efficiently applies all three modifications in a single copy-on-write operation.
    /// The original logger is not modified.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - logLevel: The log level to set on the new logger.
    ///   - handler: The log handler to use for the new logger.
    /// - Returns: A new `Logger` instance with the specified modifications.
    @inlinable
    public func with(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        handler: any LogHandler
    ) -> Logger {
        var newLogger = self
        var newHandler = handler
        if additionalMetadata.count == 1 {
            newHandler.metadata[additionalMetadata.first!.key] = additionalMetadata.first!.value
        } else {
            newHandler.metadata.merge(additionalMetadata) { _, new in new }
        }
        newHandler.logLevel = logLevel
        newLogger.handler = newHandler
        return newLogger
    }
}

// MARK: - Static with() methods for task-local logger

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Logger {
    /// Modify the task-local logger with additional metadata and execute a closure that returns a value.
    ///
    /// This static method modifies the current task-local logger by merging the provided metadata,
    /// then executes the closure with the modified logger set as the task-local context.
    ///
    /// > Important: Task-local values are **not** inherited by detached tasks created with `Task.detached`.
    /// > If you need logger context in a detached task, capture the logger explicitly or use structured
    /// > concurrency (`async let`, `withTaskGroup`, etc.) instead.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with the current task-local logger's metadata.
    ///   - body: The closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        _ body: (Logger) throws -> R
    ) rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(additionalMetadata: additionalMetadata)
        return try Logger.withTaskLocalLogger(modifiedLogger) {
            try body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with additional metadata and execute an async closure that returns a value.
    ///
    /// This static method modifies the current task-local logger by merging the provided metadata,
    /// then executes the async closure with the modified logger set as the task-local context.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with the current task-local logger's metadata.
    ///   - body: The async closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(additionalMetadata: additionalMetadata)
        return try await Logger.withTaskLocalLogger(modifiedLogger) {
            try await body(modifiedLogger)
        }
    }

    /// Modify the task-local logger's log level and execute a closure that returns a value.
    ///
    /// This static method modifies the current task-local logger's log level, then executes the closure
    /// with the modified logger set as the task-local context.
    ///
    /// - Parameters:
    ///   - logLevel: The log level to set on the task-local logger.
    ///   - body: The closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        logLevel: Logger.Level,
        _ body: (Logger) throws -> R
    ) rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(logLevel: logLevel)
        return try Logger.withTaskLocalLogger(modifiedLogger) {
            try body(modifiedLogger)
        }
    }

    /// Modify the task-local logger's log level and execute an async closure that returns a value.
    ///
    /// This static method modifies the current task-local logger's log level, then executes the async closure
    /// with the modified logger set as the task-local context.
    ///
    /// - Parameters:
    ///   - logLevel: The log level to set on the task-local logger.
    ///   - body: The async closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        logLevel: Logger.Level,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(logLevel: logLevel)
        return try await Logger.withTaskLocalLogger(modifiedLogger) {
            try await body(modifiedLogger)
        }
    }

    /// Modify the task-local logger's handler and execute a closure that returns a value.
    ///
    /// This static method modifies the current task-local logger's handler, then executes the closure
    /// with the modified logger set as the task-local context.
    ///
    /// - Parameters:
    ///   - handler: The log handler to use for the task-local logger.
    ///   - body: The closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        handler: any LogHandler,
        _ body: (Logger) throws -> R
    ) rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(handler: handler)
        return try Logger.withTaskLocalLogger(modifiedLogger) {
            try body(modifiedLogger)
        }
    }

    /// Modify the task-local logger's handler and execute an async closure that returns a value.
    ///
    /// This static method modifies the current task-local logger's handler, then executes the async closure
    /// with the modified logger set as the task-local context.
    ///
    /// - Parameters:
    ///   - handler: The log handler to use for the task-local logger.
    ///   - body: The async closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        handler: any LogHandler,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(handler: handler)
        return try await Logger.withTaskLocalLogger(modifiedLogger) {
            try await body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with additional metadata and log level, and execute a closure that returns a value.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with the current task-local logger's metadata.
    ///   - logLevel: The log level to set on the task-local logger.
    ///   - body: The closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        _ body: (Logger) throws -> R
    ) rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(additionalMetadata: additionalMetadata, logLevel: logLevel)
        return try Logger.withTaskLocalLogger(modifiedLogger) {
            try body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with additional metadata and log level, and execute an async closure that returns a value.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with the current task-local logger's metadata.
    ///   - logLevel: The log level to set on the task-local logger.
    ///   - body: The async closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(additionalMetadata: additionalMetadata, logLevel: logLevel)
        return try await Logger.withTaskLocalLogger(modifiedLogger) {
            try await body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with additional metadata and handler, and execute a closure that returns a value.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with the current task-local logger's metadata.
    ///   - handler: The log handler to use for the task-local logger.
    ///   - body: The closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        handler: any LogHandler,
        _ body: (Logger) throws -> R
    ) rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(additionalMetadata: additionalMetadata, handler: handler)
        return try Logger.withTaskLocalLogger(modifiedLogger) {
            try body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with additional metadata and handler, and execute an async closure that returns a value.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with the current task-local logger's metadata.
    ///   - handler: The log handler to use for the task-local logger.
    ///   - body: The async closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        handler: any LogHandler,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(additionalMetadata: additionalMetadata, handler: handler)
        return try await Logger.withTaskLocalLogger(modifiedLogger) {
            try await body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with log level and handler, and execute a closure that returns a value.
    ///
    /// - Parameters:
    ///   - logLevel: The log level to set on the task-local logger.
    ///   - handler: The log handler to use for the task-local logger.
    ///   - body: The closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) throws -> R
    ) rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(logLevel: logLevel, handler: handler)
        return try Logger.withTaskLocalLogger(modifiedLogger) {
            try body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with log level and handler, and execute an async closure that returns a value.
    ///
    /// - Parameters:
    ///   - logLevel: The log level to set on the task-local logger.
    ///   - handler: The log handler to use for the task-local logger.
    ///   - body: The async closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(logLevel: logLevel, handler: handler)
        return try await Logger.withTaskLocalLogger(modifiedLogger) {
            try await body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with metadata, log level, and handler, and execute a closure that returns a value.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with the current task-local logger's metadata.
    ///   - logLevel: The log level to set on the task-local logger.
    ///   - handler: The log handler to use for the task-local logger.
    ///   - body: The closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) throws -> R
    ) rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(
            additionalMetadata: additionalMetadata,
            logLevel: logLevel,
            handler: handler
        )
        return try Logger.withTaskLocalLogger(modifiedLogger) {
            try body(modifiedLogger)
        }
    }

    /// Modify the task-local logger with metadata, log level, and handler, and execute an async closure that returns a value.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with the current task-local logger's metadata.
    ///   - logLevel: The log level to set on the task-local logger.
    ///   - handler: The log handler to use for the task-local logger.
    ///   - body: The async closure to execute with the modified task-local logger.
    /// - Returns: The value returned by the closure.
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R {
        let modifiedLogger = Logger.taskLocalLogger.with(
            additionalMetadata: additionalMetadata,
            logLevel: logLevel,
            handler: handler
        )
        return try await Logger.withTaskLocalLogger(modifiedLogger) {
            try await body(modifiedLogger)
        }
    }
}
