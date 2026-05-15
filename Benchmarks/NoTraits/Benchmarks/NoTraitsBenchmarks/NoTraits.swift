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

import Benchmark
import BenchmarksFactory
import Foundation
import Logging

public let benchmarks: @Sendable () -> Void = {
    makeBenchmark(loggerLevel: .error, logLevel: .error, "_generic") { logger in
        logger.log(level: .error, "hello, benchmarking world")
    }
    makeBenchmark(loggerLevel: .error, logLevel: .debug, "_generic") { logger in
        logger.log(level: .debug, "hello, benchmarking world")
    }

    // MARK: - Task-local logger benchmarks

    makeBenchmark(loggerLevel: .error, logLevel: .error, "_current_read") { _ in
        blackHole(Logger.current.wrappedValue)
    }

    makeBenchmark(loggerLevel: .error, logLevel: .error, "_current_read_inside_metadata_scope") { _ in
        Logger.current.withMetadata(merging: ["key": "value"]) {
            blackHole(Logger.current.wrappedValue)
        }
    }

    makeBenchmark(loggerLevel: .error, logLevel: .error, "_current_withMetadata_scope_entry") { _ in
        Logger.current.withMetadata(merging: ["key": "value"]) {}
    }

    makeBenchmark(loggerLevel: .error, logLevel: .error, "_withLoggerFactory_scope_entry") { logger in
        withLoggerFactory({ _, _ in logger.handler }) {}
    }
}
