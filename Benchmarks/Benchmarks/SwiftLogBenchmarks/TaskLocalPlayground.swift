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
import Foundation
import Logging

// MARK: - Benchmarks logger init

func makeBenchmarksLogger() -> Logger {
    var logger = Logger(label: "TaskLocalPlaygroundLogger_explicit")
    #if !BenchmarkTaskLocalWithConsoleLogger
    logger.handler = NoOpLogHandler(label: "NoOpLogHandler_explicit")
    #endif
    return logger
}

let benchmarksLogger = makeBenchmarksLogger()

// MARK: - Payload functions

/// Benchmark function using explicit logger parameter passing.
///
/// This function demonstrates the traditional approach of explicitly passing
/// logger instances through the call stack. Each recursive call receives a logger
/// with accumulated metadata.
@inline(never)
func explicitLogger(logger: Logger, iterations: Int = 100, moreMetadata: Bool = true) {
    if iterations == 0 {
        return
    }
    let additionalMetadata: Logger.Metadata =
        if moreMetadata {
            [
                "iteration-\(iterations)-key1": "iteration-\(iterations)-value1",
                "iteration-\(iterations)-key2": "iteration-\(iterations)-value2",
                "iteration-\(iterations)-key3": "iteration-\(iterations)-value3",
            ]
        } else {
            [
                "iteration-\(iterations)-key1": "iteration-\(iterations)-value1"
            ]
        }
    let newLogger = logger.with(additionalMetadata: additionalMetadata)
    newLogger.info("I am a recursive function")
    explicitLogger(
        logger: newLogger,
        iterations: iterations - 1,
        moreMetadata: moreMetadata
    )
    newLogger.info("I am done")
}

/// Benchmark function using implicit task-local logger propagation.
///
/// This function demonstrates the task-local logger approach where loggers are
/// propagated implicitly through task-local storage. Each recursive call adds
/// metadata using Logger.with() without explicit parameter passing.
@inline(never)
func implicitLogger(iterations: Int = 100, moreMetadata: Bool = true) {
    if iterations == 0 {
        return
    }
    let additionalMetadata: Logger.Metadata =
        if moreMetadata {
            [
                "iteration-\(iterations)-key1": "iteration-\(iterations)-value1",
                "iteration-\(iterations)-key2": "iteration-\(iterations)-value2",
                "iteration-\(iterations)-key3": "iteration-\(iterations)-value3",
            ]
        } else {
            [
                "iteration-\(iterations)-key1": "iteration-\(iterations)-value1"
            ]
        }
    Logger.with(additionalMetadata: additionalMetadata) { logger in
        logger.info("I am a recursive function using task local logger")
        implicitLogger(iterations: iterations - 1, moreMetadata: moreMetadata)
        logger.info("I am done")
    }
}

/// MARK: - benchmarking functions

func benchmarkLoggerPropagation() {
    let iterations = 1_000_000_000
    let taskLocalBenchmarksMetrics: [BenchmarkMetric] = [.instructions, .objectAllocCount, .wallClock]

    #if BenchmarkTaskLocalLogger
    benchmarkImplicitTaskLocalLoggerPropagation(iterations, taskLocalBenchmarksMetrics)
    #endif

    #if BenchmarkExplicitLogger
    benchmarkExplicitLoggerPropagation(iterations, taskLocalBenchmarksMetrics)
    #endif
}

func benchmarkExplicitLoggerPropagation(_ iterations: Int, _ metrics: [BenchmarkMetric]) {
    Benchmark(
        "TaskLocalPlaygroundBenchmark",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        explicitLogger(logger: benchmarksLogger)
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_singleMetadataValue",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        explicitLogger(logger: benchmarksLogger, moreMetadata: false)
    }
}

func benchmarkImplicitTaskLocalLoggerPropagation(_ iterations: Int, _ metrics: [BenchmarkMetric]) {
    Benchmark(
        "TaskLocalPlaygroundBenchmark",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        Logger.with(handler: benchmarksLogger.handler) { _ in
            benchmark.startMeasurement()
            implicitLogger()
            benchmark.stopMeasurement()
        }
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_singleMetadataValue",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        Logger.with(handler: benchmarksLogger.handler) { _ in
            benchmark.startMeasurement()
            implicitLogger(moreMetadata: false)
            benchmark.stopMeasurement()
        }
    }
}
