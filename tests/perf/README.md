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
| `evaluate_long` | 11056 | 2009.7 |
| `evaluate_non_strict` | 703 | 74.2 |
| `evaluate_string` | 362 | 34.9 |
| `evaluate_two_strings` | 750 | 81.3 |
| `evaluate_version` | 1975 | 432.7 |
| `tokenize_long` | 4870 | 424.0 |
| `tokenize_no_whitespace` | 563 | 49.6 |
| `tokenize_version` | 305 | 27.5 |
| `version_is_compatible` | 64 | 8.6 |
| `version_is_eq_prefix` | 10 | 2.5 |
| `version_is_ge` | 54 | 6.2 |
| `version_is_lt` | 48 | 6.3 |
| `version_key` | 26 | 2.7 |
| `version_normalize` | 950 | 218.5 |
| `version_parse_all_segments` | 1514 | 335.6 |
| `version_parse_invalid` | 628 | 137.6 |
| `version_parse_pre_release` | 1016 | 239.6 |
| `version_parse_prefix` | 784 | 178.4 |
| `version_parse_release` | 881 | 201.1 |
