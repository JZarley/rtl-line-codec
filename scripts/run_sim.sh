#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TESTS=(nrz_pipeline framer deframer sync_fifo framed_nrz_pipeline)
SELECTION="${1:-nrz_pipeline}"

if [[ "$#" -gt 1 ]]; then
    echo "Usage: $0 [nrz_pipeline|framer|deframer|sync_fifo|framed_nrz_pipeline|all]" >&2
    exit 2
fi

if [[ "$SELECTION" == "all" ]]; then
    RUN_TESTS=("${TESTS[@]}")
else
    FOUND=0
    for test in "${TESTS[@]}"; do
        if [[ "$SELECTION" == "$test" ]]; then
            FOUND=1
            break
        fi
    done
    if [[ "$FOUND" -ne 1 ]]; then
        echo "Unknown test: $SELECTION" >&2
        exit 2
    fi
    RUN_TESTS=("$SELECTION")
fi

for top in "${RUN_TESTS[@]}"; do
    echo "== Building ${top}_tb =="
    verilator --binary --timing --assert \
        --Mdir "obj_dir/$top" \
        rtl/*.sv "tb/${top}_tb.sv" \
        --top-module "${top}_tb"

    echo "== Running ${top}_tb =="
    "obj_dir/$top/V${top}_tb"
    echo "PASS: ${top}_tb"
done

echo "PASS: ${#RUN_TESTS[@]} testbench(es)"
