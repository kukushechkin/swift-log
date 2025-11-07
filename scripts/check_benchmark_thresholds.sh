#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftLog open source project
##
## Copyright (c) 2025 Apple Inc. and the SwiftLog project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftLog project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -uo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

# Parameter environment variables
if [ -z "$XCODE_VERSION" ]; then
  fatal "XCODE_VERSION must be specified."
fi

benchmark_package_path="${BENCHMARK_PACKAGE_PATH:-"."}"
xcode_version="${XCODE_VERSION:-""}"

# Build swift package command with optional arguments
# This avoids the "unbound variable" error when $@ is empty with set -u
if [ $# -eq 0 ]; then
  swift_package_cmd="swift package --package-path $benchmark_package_path"
else
  swift_package_cmd="swift package --package-path $benchmark_package_path $*"
fi

# Check thresholds
eval "$swift_package_cmd" benchmark thresholds check --format metricP90AbsoluteThresholds --path "${benchmark_package_path}/Thresholds/Xcode_${xcode_version}/"
rc="$?"

# Benchmarks are unchanged, nothing to recalculate
if [[ "$rc" == 0 ]]; then
  exit 0
fi

log "Recalculating thresholds..."

eval "$swift_package_cmd" benchmark thresholds update --format metricP90AbsoluteThresholds --path "${benchmark_package_path}/Thresholds/Xcode_${xcode_version}/" --allow-writing-to-package-directory
echo "=== BEGIN DIFF ==="  # use echo, not log for clean output to be scraped
git diff --exit-code HEAD
