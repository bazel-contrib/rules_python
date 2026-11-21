# Performance of the Starlark code

The version and the environment marker handling is executed many times when
`pip.parse` is evaluated: for every requirement, for every target platform and
for every Python version. This directory has the tools to ensure that this code
stays fast.

The measured workloads are in `workloads.bzl`.

## Counting the steps

Bazel cannot count how many steps the Starlark interpreter executes. However,
the `.bzl` files that only have pure functions are almost valid Python, so
`starlark_shim.py` executes them with CPython and counts the executed lines of
the `.bzl` files, which we call _steps_.

The number of steps does not depend on the machine and it changes when the
amount of work that the code does changes. It only slightly depends on the
Python version, hence the test below has a tolerance of 5%.

The shim is not a Starlark interpreter, it only supports what the measured
files need. If you start using something that is not supported, extend the
shim.

Print the number of steps that the workloads take:

```shell
bazel run //tests/perf:benchmark
```

Only run the workloads that have `version` in the name:

```shell
bazel run //tests/perf:benchmark -- version
```

`//tests/perf:steps_test` runs as part of the regular tests and it fails if
the number of steps of a workload changes by more than that. If the code got slower, then either
fix the code or, if the extra work is necessary, update the numbers in
`steps_test.py`. If the code got faster, then update the numbers, so that it
stays that way. In both cases update the results below.

## Measuring with Bazel

The steps are a proxy, so there is also a benchmark that measures the
workloads with Bazel itself:

```shell
bazel run //tests/perf:bazel_benchmark
```

It builds `//tests/perf:bazel_benchmark_analysis`, which executes the workload
that is selected with `--//tests/perf:workload` for
`--//tests/perf:iterations` times during the analysis. Starlark does not have
a clock, so the time of a single iteration is the difference of the wall time
of 2 builds divided by the difference of the iterations. This takes a long
time and the results depend on the machine, hence it is not a test.

If you run Bazel with startup options, pass the same ones to the benchmark,
otherwise the Bazel server restarts for every build:

```shell
bazel --host_jvm_args=-Xmx2g run //tests/perf:bazel_benchmark -- \
    --bazel="bazel --host_jvm_args=-Xmx2g"
```

The same target can be used to profile the code with `--starlark_cpu_profile`,
see https://bazel.build/rules/performance#performance-profiling:

```shell
bazel build //tests/perf:bazel_benchmark_analysis \
    --//tests/perf:workload=evaluate_long \
    --//tests/perf:iterations=10000 \
    --starlark_cpu_profile=/tmp/profile.gz
```

## Results

The time is of Bazel 9.1.1 on a laptop, only the ratios are meaningful.

| Workload | Steps | Bazel, µs |
|---|---:|---:|
| `evaluate_long` | 1926 | 383.6 |
| `evaluate_long_parsed` | 657 | 114.1 |
| `evaluate_non_strict` | 280 | 58.4 |
| `evaluate_string` | 119 | 24.5 |
| `evaluate_two_strings` | 223 | 43.0 |
| `evaluate_version` | 280 | 56.4 |
| `evaluate_version_parsed` | 130 | 21.3 |
| `parse_long` | 1272 | 231.5 |
| `tokenize_long` | 514 | 112.9 |
| `tokenize_no_whitespace` | 84 | 23.0 |
| `tokenize_version` | 48 | 10.8 |
| `version_is_compatible` | 64 | 8.6 |
| `version_is_eq_prefix` | 10 | 2.5 |
| `version_is_ge` | 54 | 6.2 |
| `version_is_lt` | 48 | 6.3 |
| `version_key` | 26 | 2.7 |
| `version_normalize` | 24 | 4.8 |
| `version_parse_all_segments` | 1518 | 329.1 |
| `version_parse_invalid` | 632 | 136.1 |
| `version_parse_pre_release` | 1020 | 238.3 |
| `version_parse_prefix` | 52 | 9.6 |
| `version_parse_release` | 53 | 9.5 |

## History

The notable changes of the results, the numbers are the steps.

| Change | Workload | Before | After |
|---|---|---:|---:|
| Parse the release-only versions without the parser | `version_parse_release` | 881 | 53 |
|  | `evaluate_version` | 1975 | 525 |
|  | `evaluate_long` | 11056 | 6376 |
| Rewrite the marker evaluation | `tokenize_long` | 4870 | 514 |
|  | `evaluate_string` | 362 | 122 |
|  | `evaluate_version` | 525 | 283 |
|  | `evaluate_long` | 6376 | 1974 |
| Evaluate the markers that are parsed with `parse` | `evaluate_version_parsed` | 283 | 132 |
|  | `evaluate_long_parsed` | 1974 | 693 |
