# Successful separate Callgrind diagnostic

[Run 39733272376](https://github.com/STEVVVU/ocaml-transactional-memory/actions/runs/39733272376)
used source `6ecf556be3102730b6eef054c09c2a02aa279809`, OCaml 5.3.0 and
Valgrind 3.22.0 on Ubuntu 24.04. Binary SHA-256:
`67ec084a8e684d7a48895fe1318776384ba25c8293b099715f192c9ef87f365d`.

The maintained helper command was:

```sh
bash coursework/scripts/verify.sh --profile metrics-39733272376
```

It builds Release and runs the existing stm_bench with 10 operations, 4096
pairs (8192 accounts), one domain, zero warmup and five backend rotations for
every existing workload. Callgrind uses fair scheduling, a 300-second timeout
and periodic billion-basic-block dumps. All 45 diagnostic summaries completed:
450 successes, zero errors and zero TL2 retries. The dedicated receipt records
passed=true and exit_code=0. Instrumented timings are excluded from benchmark
comparisons. The earlier failed 100-operation profile and its false receipt
remain retained; they were not replaced by this result.

Raw exclusive instruction costs sum exactly to the header's 2100262264.
`exclusive-costs.csv` retains every symbol's exclusive count. Calls' inclusive
cost rows were excluded from that sum. The generated inclusive annotation has
huge recursive OCaml call-graph overcounts and cannot support percentages.

List sorting/merging accounts for 190911428 instructions (9.090%); the TL2
cell-ID comparator at tl2.ml:77 accounts for 74833798 (3.563%), totaling
12.653%. There are 5756446 comparator calls. The profile also records substantial
GC, hashing and allocation work. It combines all backends and includes bank
creation and final untimed Bank.total correctness checks, so these proportions
are not native wall-time shares or per-snapshot measurements.

Source inspection connects the comparator to TL2.entries sorting every read
set before commit checks whether any writes exist. Read-only transactions need
the same immutable state-identity validation, but no write-lock order. This
supports a narrowly reviewed read-only branch, not a claim that removing it
eliminates the entire native gap. The original write-bearing lock/version/
publish/retry protocol must remain unchanged. Matched native framework results
and concurrency regression checks are required before accepting improvement.

All original output, dedicated receipt, environment, functional/negative
verification and raw profiles are covered by `raw-sha256.txt`.
