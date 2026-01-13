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

// MARK: - Explicit logger passing functions

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

@inline(never)
func explicitLoggerNoExtraMetadataWithTaskGroup(logger: Logger, iterations: Int = 100) async {
    if iterations == 0 {
        return
    }
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            logger.info("I am a recursive function")
            await explicitLoggerNoExtraMetadataWithTaskGroup(
                logger: logger,
                iterations: iterations - 1
            )
            logger.info("I am done")
        }
    }
}

@inline(never)
func explicitLoggerNoExtraMetadata(logger: Logger, iterations: Int = 100) {
    if iterations == 0 {
        return
    }
    logger.info("I am a recursive function")
    explicitLoggerNoExtraMetadata(
        logger: logger,
        iterations: iterations - 1
    )
    logger.info("I am done")
}

@inline(never)
func explicitLoggerNoExtraMetadataManyLogs(logger: Logger, iterations: Int = 100) {
    if iterations == 0 {
        return
    }
    for _ in 0...1 {
        logger.info("I am a log function")
    }
    explicitLoggerNoExtraMetadataManyLogs(
        logger: logger,
        iterations: iterations - 1
    )
}

// MARK: - Implicit logger passing functions

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

@inline(never)
func implicitLoggerNoExtraMetadataWithTaskGroup(iterations: Int = 100) async {
    if iterations == 0 {
        return
    }
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            await Logger.withCurrent { logger in
                logger.info("I am a recursive function using task local logger")
                await implicitLoggerNoExtraMetadataWithTaskGroup(iterations: iterations - 1)
                logger.info("I am done")
            }
        }
    }
}

@inline(never)
func implicitLoggerNoExtraMetadata(iterations: Int = 100) {
    if iterations == 0 {
        return
    }
    Logger.withCurrent { logger in
        logger.info("I am a recursive function using task local logger")
        implicitLoggerNoExtraMetadata(iterations: iterations - 1)
        logger.info("I am done")
    }
}

@inline(never)
func implicitLoggerNoExtraMetadataManyLogsClosure(iterations: Int = 100) {
    if iterations == 0 {
        return
    }
    Logger.withCurrent { logger in
        for _ in 0...1 {
            logger.info("I am a log function")
        }
        implicitLoggerNoExtraMetadataManyLogsClosure(iterations: iterations - 1)
    }
}

@inline(never)
func implicitLoggerNoExtraMetadataManyLogsCurrent(iterations: Int = 100) {
    if iterations == 0 {
        return
    }
    for _ in 0...1 {
        Logger.current.info("I am a log function")
    }
    implicitLoggerNoExtraMetadataManyLogsCurrent(iterations: iterations - 1)
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
    Benchmark(
        "TaskLocalPlaygroundBenchmark_noExtraMetadataWithTaskGroup",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        await explicitLoggerNoExtraMetadataWithTaskGroup(logger: benchmarksLogger)
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_noExtraMetadata",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        explicitLoggerNoExtraMetadata(logger: benchmarksLogger)
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_noExtraMetadata_manyLogs",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        explicitLoggerNoExtraMetadataManyLogs(logger: benchmarksLogger)
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_noExtraMetadata_manyLogsCurrent",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        explicitLoggerNoExtraMetadataManyLogs(logger: benchmarksLogger)
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
    Benchmark(
        "TaskLocalPlaygroundBenchmark_noExtraMetadataWithTaskGroup",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        await Logger.with(handler: benchmarksLogger.handler) { _ in
            benchmark.startMeasurement()
            await implicitLoggerNoExtraMetadataWithTaskGroup()
            benchmark.stopMeasurement()
        }
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_noExtraMetadata",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        Logger.with(handler: benchmarksLogger.handler) { _ in
            benchmark.startMeasurement()
            implicitLoggerNoExtraMetadata()
            benchmark.stopMeasurement()
        }
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_noExtraMetadata_manyLogs",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        Logger.with(handler: benchmarksLogger.handler) { _ in
            benchmark.startMeasurement()
            implicitLoggerNoExtraMetadataManyLogsClosure()
            benchmark.stopMeasurement()
        }
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_noExtraMetadata_manyLogsCurrent",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        Logger.with(handler: benchmarksLogger.handler) { _ in
            benchmark.startMeasurement()
            implicitLoggerNoExtraMetadataManyLogsCurrent()
            benchmark.stopMeasurement()
        }
    }
}
