#!/usr/bin/env bash
set -e

TOP=nrz_pipeline_tb

rm -rf obj_dir

verilator \
    --binary \
    --timing \
    -Wall \
    rtl/*.sv \
    tb/${TOP}.sv \
    --top-module ${TOP}

./obj_dir/V${TOP}