#!/bin/env bash

cd $(dirname $0)
bazel run '@submodule//:bin'
