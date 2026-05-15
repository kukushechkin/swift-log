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

// MARK: - SLG-0007: Scoped logger factory
//
// This file provides:
// - `Logger.taskLocalFactory` storage (consulted by `LoggingSystem.factory`),
// - `withLoggerFactory(_:_:)` sync and async free functions.
//
// `LoggingSystem.factory` (in LoggingSystem.swift) reads `Logger.taskLocalFactory` and
// returns the bound value if any, falling back to the bootstrapped factory.

extension Logger {
    /// Task-local storage for the handler factory consulted by ``LoggingSystem/factory``
    /// within the current scope. Bound by ``withLoggerFactory(_:_:)``; falls back to the
    /// bootstrapped factory when nil. Task-local values propagate through structured
    /// concurrency (`async let`, `withTaskGroup`, child `Task { }`) but are **not**
    /// inherited by `Task.detached`.
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    internal static let taskLocalFactory: TaskLocal<(@Sendable (String, Logger.MetadataProvider?) -> any LogHandler)?> =
        TaskLocal(wrappedValue: nil)
}

/// Bind `factory` as the handler factory for the current task-local scope.
///
/// Code within `operation` that constructs a logger via ``Logger/init(label:)`` receives a
/// handler built by `factory`. Nested ``withLoggerFactory(_:_:)`` scopes replace the outer
/// factory for the duration of the inner scope.
///
/// ```swift
/// try await withLoggerFactory(StreamLogHandler.standardError) {
///     // Logger(label:) calls inside this scope use StreamLogHandler.standardError.
///     try await handleRequests()
/// }
/// ```
///
/// - Parameters:
///   - factory: Builds a ``LogHandler`` given a label and a metadata provider.
///   - operation: The closure to run with `factory` bound.
/// - Returns: The value returned by `operation`.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public func withLoggerFactory<Result>(
    _ factory: @escaping @Sendable (String, Logger.MetadataProvider?) -> any LogHandler,
    _ operation: () throws -> Result
) rethrows -> Result {
    try Logger.taskLocalFactory.withValue(factory) {
        try operation()
    }
}

/// Async variant of ``withLoggerFactory(_:_:)``. See that function for semantics.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public func withLoggerFactory<Result>(
    _ factory: @escaping @Sendable (String, Logger.MetadataProvider?) -> any LogHandler,
    _ operation: nonisolated(nonsending) () async throws -> Result
) async rethrows -> Result {
    try await Logger.taskLocalFactory.withValue(factory) {
        try await operation()
    }
}
