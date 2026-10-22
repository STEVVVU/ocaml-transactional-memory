#!/usr/bin/env bash
set -euo pipefail

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
exit "$status"
