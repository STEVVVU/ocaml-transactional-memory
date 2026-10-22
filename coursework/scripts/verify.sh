#!/usr/bin/env bash
set -euo pipefail

mode=verify
if [[ ${1:-} == --metrics ]]; then mode=metrics; shift; fi
if [[ ${1:-} == --profile ]]; then mode=profile; shift; fi

if [[ $# -ne 1 || "$1" == *..* || "$1" == *\\* ]]; then
  echo "usage: bash coursework/scripts/verify.sh <run-id>" >&2
  exit 2
fi

run_dir=".agents/runs/$1"
mkdir -p "$run_dir"
write_metrics_receipt() {
  python3 - "$run_dir/metrics-result.json" "$mode" "$1" <<'PY'
import json
import pathlib
import sys

path, mode, status = sys.argv[1:]
temporary = pathlib.Path(path + '.tmp')
temporary.write_text(json.dumps(dict(mode=mode, passed=int(status) == 0,
    exit_code=int(status), functional_receipt_is_not_metrics=True), indent=2) + '\n')
temporary.replace(path)
PY
}
if [[ $mode != verify ]]; then
  write_metrics_receipt 1
  trap 'terminal_status=$?; write_metrics_receipt "$terminal_status"' EXIT
fi
opam exec -- dune build coursework/bin/stm_verify.exe
opam exec -- dune exec coursework/bin/stm_verify.exe -- --doctor 2>&1 | tee "$run_dir/doctor.log"
set +e
opam exec -- dune exec coursework/bin/stm_verify.exe -- --evidence "$run_dir" 2>&1 | tee "$run_dir/drive.log"
status=${PIPESTATUS[0]}
set -e
if [[ $status -eq 0 && $mode != verify ]]; then
  test "$(df -Pk . | awk 'NR==2 {print $4}')" -ge 10485760
  { git rev-parse HEAD; uname -a; lscpu; free -b; df -B1 .; uptime; opam exec -- ocamlc -version; opam list --installed; } > "$run_dir/environment.txt"
  opam exec -- dune build --profile release coursework/bench/stm_bench.exe
  if [[ $mode == profile ]]; then
    { valgrind --version; sha256sum _build/default/coursework/bench/stm_bench.exe; } > "$run_dir/profile-identity.txt"
    timeout 300 valgrind --tool=callgrind --callgrind-out-file="$run_dir/callgrind.out" \
      --log-file="$run_dir/callgrind.log" _build/default/coursework/bench/stm_bench.exe \
      --output "$run_dir/profile-only.csv" --operations 100 --pairs 4096 \
      --domains 1 --warmup 0 --latency-stride 100 \
      2>&1 | tee "$run_dir/profile-only.log"
    callgrind_annotate --inclusive=yes --auto=yes "$run_dir/callgrind.out" > "$run_dir/callgrind-annotation.txt"
    exit 0
  fi
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
