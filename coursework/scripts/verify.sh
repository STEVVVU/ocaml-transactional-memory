#!/usr/bin/env bash
set -euo pipefail

mode=verify
if [[ ${1:-} == --metrics ]]; then mode=metrics; shift; fi

if [[ $# -ne 1 || "$1" == *..* || "$1" == *\\* ]]; then
  echo "usage: bash coursework/scripts/verify.sh <run-id>" >&2
  exit 2
fi

run_dir=".agents/runs/$1"
mkdir -p "$run_dir"
opam exec -- dune build coursework/bin/stm_verify.exe
opam exec -- dune exec coursework/bin/stm_verify.exe -- --doctor 2>&1 | tee "$run_dir/doctor.log"
set +e
opam exec -- dune exec coursework/bin/stm_verify.exe -- --evidence "$run_dir" 2>&1 | tee "$run_dir/drive.log"
status=${PIPESTATUS[0]}
set -e
if [[ $status -eq 0 && $mode == metrics ]]; then
  test "$(df -Pk . | awk 'NR==2 {print $4}')" -ge 10485760
  { git rev-parse HEAD; uname -a; lscpu; free -b; df -B1 .; uptime; opam exec -- ocamlc -version; opam list --installed; } > "$run_dir/environment.txt"
  opam exec -- dune build --profile release coursework/bench/stm_bench.exe
  domains=1
  for n in 2 4; do if (( n <= $(nproc) )); then domains="$domains,$n"; fi; done
  for pairs in 1 64 4096; do
    timeout 900 /usr/bin/time -v _build/default/coursework/bench/stm_bench.exe \
      --output "$run_dir/metrics-$pairs.csv" --operations 20000 --pairs "$pairs" \
      --domains "$domains" --warmup 1000 --latency-stride 100 \
      2>&1 | tee "$run_dir/metrics-$pairs.log"
  done
  python3 coursework/scripts/summarize_metrics.py "$run_dir"
  timeout 300 strace -f -c _build/default/coursework/bench/stm_bench.exe \
    --output "$run_dir/profile.csv" --operations 5000 --pairs 64 \
    --domains "$domains" --warmup 1000 --latency-stride 100 \
    2>&1 | tee "$run_dir/profile.log"
fi
exit "$status"
