# SwiftLog benchmarks

Benchmarks comparing task-local logger propagation versus explicit logger propagation.

## Benchmarks

2 benchmarks created:

- `SwiftLogBenchmarks:TaskLocalPlaygroundBenchmark` — pass down the stack a logger, adding 3 more metadata values on each iteration.
- `SwiftLogBenchmarks:TaskLocalPlaygroundBenchmark_singleMetadataValue` — pass down the stack a logger, adding 1 metadata value on each iteration.

2 implementations for each benchmark:

 - `benchmarkExplicitLoggerPropagation` — creating a new logger, updating metadata and passing it explicitly further down the call stack.
 - `benchmarkImplicitTaskLocalLoggerPropagation` — fetching a TaskLocal logger, creating a new logger, updating metadata, updating the TaskLocal logger and running task with the new logger context.

## Insights

- With NoOp logger the TaskLocal overhead is about +1% for instructions, -5–+5% wall clock time, and no difference for allocations.
- With Console logger the TaskLocal overhead is -1–+1% for instructions, -3–+3% wall clock time, and neglectable for allocations (0% displayed).

## Comparing task-local versus explicit logger

The `TaskLocalPlaygroundBenchmark` uses mutually exclusive traits to benchmark
two approaches:

- `BenchmarkTaskLocalLogger` - Uses task-local values for logger context.
- `BenchmarkExplicitLogger` - Passes logger instances through function parameters.

### Running the comparison

Benchmark explicit logger and save baseline:

```bash
swift package \
  --traits BenchmarkExplicitLogger \
  --package-path Benchmarks --allow-writing-to-package-directory \
  benchmark --filter "TaskLocalPlaygroundBenchmark.*" \
  thresholds update --path Benchmarks/Thresholds
```

Benchmark task-local logger and compare against baseline:

```bash
swift package \
  --traits BenchmarkTaskLocalLogger \
  --package-path Benchmarks --allow-writing-to-package-directory \
  benchmark --filter "TaskLocalPlaygroundBenchmark.*" \
  thresholds check --path Benchmarks/Thresholds
```

### Using console logger

Add `BenchmarkTaskLocalWithConsoleLogger` to the list of traits to use the console logger instead of `NoOpLogHandler`.
