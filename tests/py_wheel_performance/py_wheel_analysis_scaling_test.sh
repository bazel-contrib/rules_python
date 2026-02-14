#!/usr/bin/env bash
# Test that py_wheel analysis time scales linearly with dep count.
#
# The old implementation called inputs_to_package.to_list() during analysis
# and built a string via concatenation, giving O(n^2) scaling. The fix uses
# Args.add_all(map_each=...) which defers to execution time, giving O(n).
#
# This test builds two py_wheel targets (5k and 10k deps) in analysis-only
# mode and checks that the ratio of analysis times is closer to 2x (linear)
# than 4x (quadratic).
#
# Uses --nokeep_state_after_build to discard the analysis cache after each
# build, forcing a full re-analysis on the next invocation while keeping
# the Bazel server warm (avoiding startup time noise).

set -euo pipefail

SMALL_TARGET="//tests/py_wheel_performance:small_wheel"
LARGE_TARGET="//tests/py_wheel_performance:large_wheel"
# Threshold ratio: linear=2.0, quadratic=4.0. We use 3.0 as the boundary.
MAX_RATIO="3.0"
ITERATIONS=3

# Invalidate the analysis cache so the next build must re-analyze.
invalidate_analysis_cache() {
    bazel build --nobuild --nokeep_state_after_build "$@" 2>/dev/null
}

# Extract the "interleaved loading-and-analysis" phase time (in ms) from
# a Bazel profile, falling back to wall-clock time if parsing fails.
extract_analysis_ms() {
    local profile="$1"
    local ms
    ms=$(bazel analyze-profile "${profile}" 2>&1 \
        | grep "loading-and-analysis" \
        | grep -oP '[\d.]+(?= s)' \
        | head -1 \
        | awk '{printf "%d", $1 * 1000}')
    echo "${ms:-0}"
}

measure_analysis_time() {
    local target="$1"
    local best_ms=999999999

    for i in $(seq 1 "${ITERATIONS}"); do
        # Discard analysis cache from any prior build.
        invalidate_analysis_cache "${target}"

        # Measure a fresh analysis pass.
        local profile
        profile=$(mktemp /tmp/py_wheel_perf_XXXXXX.profile)
        bazel build --nobuild --profile="${profile}" "${target}" 2>/dev/null

        local analysis_ms
        analysis_ms=$(extract_analysis_ms "${profile}")
        rm -f "${profile}"

        # Fall back to wall time if profile parsing returned 0.
        if [[ "${analysis_ms}" == "0" ]]; then
            invalidate_analysis_cache "${target}"
            local start end
            start=$(date +%s%N)
            bazel build --nobuild "${target}" 2>/dev/null
            end=$(date +%s%N)
            analysis_ms=$(( (end - start) / 1000000 ))
        fi

        echo "    iteration ${i}: ${analysis_ms} ms" >&2

        if (( analysis_ms < best_ms )); then
            best_ms=${analysis_ms}
        fi
    done

    echo "${best_ms}"
}

echo "=== py_wheel analysis scaling test ==="
echo ""

# Warm up: ensure Bazel server is running and external deps are fetched.
echo "Warming up..."
bazel build --nobuild "${SMALL_TARGET}" 2>/dev/null || true
bazel build --nobuild "${LARGE_TARGET}" 2>/dev/null || true
echo ""

echo "Measuring small wheel (5k deps), best of ${ITERATIONS}..."
small_ms=$(measure_analysis_time "${SMALL_TARGET}")
echo "  Result: ${small_ms} ms"

echo "Measuring large wheel (10k deps), best of ${ITERATIONS}..."
large_ms=$(measure_analysis_time "${LARGE_TARGET}")
echo "  Result: ${large_ms} ms"

# Compute ratio using awk for floating point
ratio=$(awk "BEGIN { printf \"%.2f\", ${large_ms} / ${small_ms} }")

echo ""
echo "=== Results ==="
echo "  Small (5k deps):  ${small_ms} ms"
echo "  Large (10k deps): ${large_ms} ms"
echo "  Ratio (10k/5k):   ${ratio}x"
echo "  Max allowed:       ${MAX_RATIO}x"
echo ""

# Check that ratio is below threshold
passed=$(awk "BEGIN { print (${ratio} <= ${MAX_RATIO}) ? 1 : 0 }")

if [[ "${passed}" == "1" ]]; then
    echo "PASSED: Scaling ratio ${ratio}x is within linear bound (<= ${MAX_RATIO}x)"
    exit 0
else
    echo "FAILED: Scaling ratio ${ratio}x exceeds ${MAX_RATIO}x, suggesting quadratic behavior"
    echo "  Expected linear scaling (~2.0x) from Args.add_all(map_each=...)"
    echo "  Got ${ratio}x which is closer to quadratic (4.0x)"
    exit 1
fi
