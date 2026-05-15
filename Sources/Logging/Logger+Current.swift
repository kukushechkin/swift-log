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

// MARK: - SLG-0008: Default Logger.current
//
// This file ships a single default `TaskLocal<Logger>` named `Logger.current`. All
// metadata-scope and emit operations on it come from SLG-0006's extension on
// `TaskLocal where Value == Logger`.
//
// The default value `Logger(label: "")` is initialised lazily on first access. When
// SLG-0007's `withLoggerFactory(_:_:)` is in effect at first access, the default Logger
// captures the scoped factory and persists with it for the life of the process — the
// `swift_once` trap. Callers who care about scoped factory behaviour for `Logger.current`
// should rebind explicitly inside their `withLoggerFactory` scope:
//
//     withLoggerFactory(myFactory) {
//         Logger.current.withValue(Logger(label: "")) { ... }
//     }

extension Logger {
    /// A default global ``TaskLocal`` logger.
    ///
    /// Use directly with the SLG-0006 extension surface for ergonomic scoped logging
    /// without declaring a per-module task-local:
    ///
    /// ```swift
    /// try await Logger.current.withMetadata(merging: ["request.id": "r1"]) {
    ///     Logger.current.info("handling")    // emits with request.id=r1
    /// }
    /// ```
    ///
    /// Initialised lazily on first access with an empty-labelled ``Logger`` whose handler
    /// is built from ``LoggingSystem/factory`` at that moment. To pin a specific factory
    /// for ``current`` inside a SLG-0007 ``withLoggerFactory(_:_:)`` scope, rebind
    /// explicitly:
    ///
    /// ```swift
    /// try await withLoggerFactory(myFactory) {
    ///     try await Logger.current.withValue(Logger(label: "")) {
    ///         try await runWork()
    ///     }
    /// }
    /// ```
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public static let current: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: ""))
}
