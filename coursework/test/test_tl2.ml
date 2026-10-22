open Coursework_stm

let check condition message = if not condition then failwith message

let with_barrier parties f =
  let mutex = Mutex.create () in
  let condition = Condition.create () in
  let arrived = ref 0 in
  fun () ->
    Mutex.lock mutex;
    incr arrived;
    if !arrived = parties then Condition.broadcast condition
    else while !arrived < parties do Condition.wait condition mutex done;
    Mutex.unlock mutex;
    f ()

let test_snapshot_validation () =
  let x = Tl2.create 0 and y = Tl2.create 0 in
  let rendezvous = with_barrier 2 Fun.id in
  let attempt cell other =
    Tl2.attempt (fun tx ->
        let own = Tl2.read tx cell in
        let other_value = Tl2.read tx other in
        rendezvous ();
        if own = 0 && other_value = 0 then Tl2.write tx cell 1;
        ())
  in
  let first = Domain.spawn (fun () -> attempt x y) in
  let second = Domain.spawn (fun () -> attempt y x) in
  let results = (Domain.join first, Domain.join second) in
  let committed = function Some () -> 1 | None -> 0 in
  let committed_count = committed (fst results) + committed (snd results) in
  check (committed_count <= 1)
    "snapshot validation must reject at least one write-skew transaction";
  check (Tl2.transact (fun tx -> Tl2.read tx x + Tl2.read tx y) = committed_count)
    "only committed attempts may publish values";
  if committed_count = 0 then
    Tl2.transact (fun tx ->
        if Tl2.read tx x = 0 && Tl2.read tx y = 0 then Tl2.write tx x 1);
  check (Tl2.transact (fun tx -> Tl2.read tx x + Tl2.read tx y) = 1)
    "the committed snapshot must preserve the invariant";
  let expected_x = Tl2.transact (fun tx ->
            let value = Tl2.read tx x in
            Tl2.write tx x (value + 4);
            Tl2.read tx x) in
  check (expected_x = Tl2.transact (fun tx -> Tl2.read tx x))
        "read-your-writes must observe staged values";
  (try
     Tl2.transact (fun tx ->
         Tl2.write tx x 99;
         raise Exit)
   with Exit -> ());
  check (Tl2.transact (fun tx -> Tl2.read tx x) = expected_x)
    "an exception must not publish staged writes";
  Tl2.transact (fun tx -> Tl2.write tx y 2);
  check (Tl2.transact (fun tx -> Tl2.read tx y) = 2)
    "a later owner must make progress after an aborted transaction"

let test_parallel_increments domains =
  let cell = Tl2.create 0 in
  let increments = 500 in
  let workers =
    Array.init domains (fun _ ->
        Domain.spawn (fun () ->
            for _ = 1 to increments do
              Tl2.transact (fun tx -> Tl2.write tx cell (Tl2.read tx cell + 1))
            done))
  in
  Array.iter Domain.join workers;
  check (Tl2.transact (fun tx -> Tl2.read tx cell) = domains * increments)
    "concurrent same-cell increments must not be lost"

let test_retry_exhaustion () =
  let cell = Tl2.create 0 in
  let lock = Mutex.create () in
  let condition = Condition.create () in
  let ready = ref false in
  let resume = ref false in
  let publish_and_wait () =
    Mutex.lock lock;
    ready := true;
    Condition.broadcast condition;
    while not !resume do Condition.wait condition lock done;
    Mutex.unlock lock
  in
  let wait_for_ready () =
    Mutex.lock lock;
    while not !ready do Condition.wait condition lock done;
    Mutex.unlock lock
  in
  let resume_worker () =
    Mutex.lock lock;
    resume := true;
    Condition.broadcast condition;
    Mutex.unlock lock
  in
  let worker =
    Domain.spawn (fun () ->
        try
          Tl2.transact ~max_retries:1 (fun tx ->
              let value = Tl2.read tx cell in
              publish_and_wait ();
              Tl2.write tx cell (value + 1));
          false
        with Tl2.Retry_limit 1 -> true)
  in
  wait_for_ready ();
  Tl2.transact (fun tx -> Tl2.write tx cell (Tl2.read tx cell + 1));
  resume_worker ();
  check (Domain.join worker) "retry exhaustion must be reported explicitly";
  check (Tl2.transact (fun tx -> Tl2.read tx cell) = 1)
    "an exhausted transaction must not publish its staged write"

let test_partial_lock_release () =
  let low = Tl2.create 0 and high = Tl2.create 0 in
  let lock = Mutex.create () in
  let condition = Condition.create () in
  let first_lock_acquired = ref false in
  let allow_commit_to_continue = ref false in
  let wait_for_lock () =
    Mutex.lock lock;
    first_lock_acquired := true;
    Condition.broadcast condition;
    while not !allow_commit_to_continue do Condition.wait condition lock done;
    Mutex.unlock lock
  in
  let wait_until_locked () =
    Mutex.lock lock;
    while not !first_lock_acquired do Condition.wait condition lock done;
    Mutex.unlock lock
  in
  let resume_commit () =
    Mutex.lock lock;
    allow_commit_to_continue := true;
    Condition.broadcast condition;
    Mutex.unlock lock
  in
  let worker =
    Domain.spawn (fun () ->
        Tl2.Testing.attempt_with_lock_hook
          ~after_lock:(function 1 -> wait_for_lock () | _ -> ())
          (fun tx ->
            let low_value = Tl2.read tx low in
            let high_value = Tl2.read tx high in
            Tl2.write tx low (low_value + 1);
            Tl2.write tx high (high_value + 1)))
  in
  wait_until_locked ();
  Tl2.transact (fun tx -> Tl2.write tx high (Tl2.read tx high + 1));
  resume_commit ();
  check (Domain.join worker = None)
    "the transaction must fail after a later write lock changes";
  check (Tl2.transact (fun tx -> Tl2.read tx low) = 0)
    "partial lock acquisition must release the earlier cell"

let test_validation_after_version_reservation () =
  let read_cell = Tl2.create 0 and write_cell = Tl2.create 0 in
  let lock = Mutex.create () in
  let condition = Condition.create () in
  let version_reserved = ref false in
  let resume_commit = ref false in
  let pause_after_version () =
    Mutex.lock lock;
    version_reserved := true;
    Condition.broadcast condition;
    while not !resume_commit do Condition.wait condition lock done;
    Mutex.unlock lock
  in
  let wait_for_version () =
    Mutex.lock lock;
    while not !version_reserved do Condition.wait condition lock done;
    Mutex.unlock lock
  in
  let continue_commit () =
    Mutex.lock lock;
    resume_commit := true;
    Condition.broadcast condition;
    Mutex.unlock lock
  in
  let writer =
    Domain.spawn (fun () ->
        Tl2.Testing.attempt_with_version_hook
          ~after_version:(fun _ -> pause_after_version ())
          (fun tx ->
            let value = Tl2.read tx read_cell in
            Tl2.write tx write_cell (value + 1)))
  in
  wait_for_version ();
  Tl2.transact (fun tx ->
      Tl2.write tx read_cell (Tl2.read tx read_cell + 1));
  continue_commit ();
  check (Domain.join writer = None)
    "a read changed after version reservation must fail validation";
  check (Tl2.transact (fun tx -> Tl2.read tx write_cell) = 0)
    "failed post-reservation validation must not publish writes"

let test_prepublication_failure_is_atomic () =
  let low = Tl2.create 0 and high = Tl2.create 0 in
  let failed =
    try
      Tl2.Testing.attempt_with_publish_hook
        ~before_publish:(fun () -> raise Exit)
        (fun tx ->
          Tl2.write tx low 1;
          Tl2.write tx high 1);
      false
    with Exit -> true
  in
  check failed "the controlled prepublication failure must reach the caller";
  check
    (Tl2.transact (fun tx -> (Tl2.read tx low, Tl2.read tx high)) = (0, 0))
    "a prepublication failure must leave every cell unchanged";
  Tl2.transact (fun tx ->
      Tl2.write tx low 2;
      Tl2.write tx high 2);
  check
    (Tl2.transact (fun tx -> (Tl2.read tx low, Tl2.read tx high)) = (2, 2))
    "a prepublication failure must release every write lock"

type transfer = {
  invocation : int;
  response : int;
  source : int;
  destination : int;
  succeeded : bool;
}

let serial_history_exists initial history final =
  let rec search balances remaining =
    match remaining with
    | [] -> balances = final
    | _ ->
        List.exists
          (fun operation ->
            let preceded =
              List.exists
                (fun other -> other.response < operation.invocation)
                remaining
            in
            if preceded then false
            else
              let available = balances.(operation.source) >= 1 in
              if available <> operation.succeeded then false
              else
                let next = Array.copy balances in
                if available then (
                  next.(operation.source) <- next.(operation.source) - 1;
                  next.(operation.destination) <- next.(operation.destination) + 1);
                search next
                  (List.filter (fun candidate -> candidate != operation) remaining))
          remaining
  in
  search (Array.copy initial) history

let test_history_oracle () =
  let initial = [| 1; 1 |] in
  let clock = Atomic.make 0 in
  let bank = Bank.create Bank.Tl2_backend initial in
  let operations = Array.make 4 None in
  let worker worker_id =
    for step = 0 to 1 do
      let source = (worker_id + step) mod 2 in
      let invocation = Atomic.fetch_and_add clock 1 in
      let succeeded = Bank.transfer bank source (1 - source) 1 in
      let response = Atomic.fetch_and_add clock 1 in
      operations.(worker_id * 2 + step) <-
        Some { invocation; response; source; destination = 1 - source; succeeded }
    done
  in
  let left = Domain.spawn (fun () -> worker 0) in
  let right = Domain.spawn (fun () -> worker 1) in
  Domain.join left;
  Domain.join right;
  let history = Array.to_list operations |> List.filter_map Fun.id in
  check (serial_history_exists initial history (Bank.snapshot bank))
    "concurrent transfer history must match a real-time-respecting serial execution";
  let impossible =
    [
      { invocation = 0; response = 3; source = 0; destination = 1; succeeded = true };
      { invocation = 1; response = 2; source = 1; destination = 0; succeeded = false };
    ]
  in
  check (not (serial_history_exists initial impossible initial))
    "serial oracle must reject an impossible fractured history"

let test_other_backends () =
  List.iter
    (fun backend ->
      let bank = Bank.create backend [| 1000; 1000 |] in
      let workers =
        Array.init 4 (fun worker ->
            Domain.spawn (fun () ->
                for _ = 1 to 100 do
                  let source = worker mod 2 in
                  check (Bank.transfer bank source (1 - source) 1)
                    "funded transfer should succeed"
                done))
      in
      Array.iter Domain.join workers;
      check (Bank.total bank = 2000) "account total must be conserved")
    [ Bank.Kcas_backend; Bank.Tl2_backend; Bank.Mutex_backend ];
  List.iter
    (fun backend ->
      let overflow_rejected =
        try
          ignore (Bank.create backend [| max_int; 1 |]);
          false
        with Invalid_argument _ -> true
      in
      check overflow_rejected "initial total overflow must be rejected";
      let bank = Bank.create backend [| max_int; 0 |] in
      check (not (Bank.transfer bank 1 0 1)) "overflowing transfer must be rejected";
      check (Bank.snapshot bank = [| max_int; 0 |])
        "rejected transfer must leave balances unchanged")
    [ Bank.Kcas_backend; Bank.Tl2_backend; Bank.Mutex_backend ]

let () =
  test_snapshot_validation ();
  test_retry_exhaustion ();
  test_partial_lock_release ();
  test_validation_after_version_reservation ();
  test_prepublication_failure_is_atomic ();
  List.iter test_parallel_increments [ 1; 2; 4 ];
  test_history_oracle ();
  test_other_backends ();
  print_endline "TL2 and backend checks passed"
