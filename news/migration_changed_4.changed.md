(coverage) When `configure_coverage_tool = True` is set but the bundled
  `coverage.py` wheel set has no entry for the requested python version and
  platform, a warning is now printed instead of silently producing an empty
  coverage report.