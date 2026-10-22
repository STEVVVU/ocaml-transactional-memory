open Coursework_stm

type workload = Disjoint | Contended | Read_heavy

let name_workload = function
  | Disjoint -> "disjoint"
  | Contended -> "contended"
  | Read_heavy -> "read-heavy"

let backends = [ Bank.Kcas_backend; Bank.Tl2_backend; Bank.Mutex_backend ]

let name_backend = function
  | Bank.Kcas_backend -> "kcas"
  | Bank.Tl2_backend -> "tl2"
  | Bank.Mutex_backend -> "mutex"

let start_gate parties =
  let lock = Mutex.create () in
  let condition = Condition.create () in
  let count = ref 0 in
  let released = ref false in
  let cancelled = ref false in
  let wait () =
    Mutex.lock lock;
    if not !released then (
      incr count;
      if !count = parties then (
        released := true;
        Condition.broadcast condition)
      else while not !released do Condition.wait condition lock done);
    let should_start = not !cancelled in
    Mutex.unlock lock;
    should_start
  in
  let cancel () =
    Mutex.lock lock;
    cancelled := true;
    released := true;
    Condition.broadcast condition;
    Mutex.unlock lock
  in
  (wait, cancel)

let spawn_all count on_failure work =
  let spawned = ref [] in
  try
    for worker = 0 to count - 1 do
      let domain = Domain.spawn (fun () -> work worker) in
      spawned := domain :: !spawned
    done;
    Array.of_list (List.rev !spawned)
  with exn ->
    on_failure ();
    List.iter (fun domain -> try ignore (Domain.join domain) with _ -> ()) !spawned;
    raise exn

let join_all workers =
  let failures = ref [] in
  Array.iter
    (fun worker ->
      try Domain.join worker with exn -> failures := exn :: !failures)
    workers;
  match !failures with [] -> () | exn :: _ -> raise exn

let percentile sorted p =
  let index = min (Array.length sorted - 1) (int_of_float (ceil (p *. float (Array.length sorted))) - 1) in
  sorted.(max 0 index)

let quote_csv value =
  "\"" ^ String.concat "\"\"" (String.split_on_char '"' value) ^ "\""

let run channel backend workload domains trial operations pairs warmup stride =
  let accounts =
    match workload with
    | Disjoint -> Array.make (2 * pairs * domains) 1_000_000
    | Contended | Read_heavy -> Array.make (2 * pairs) 1_000_000
  in
  let bank = Bank.create backend accounts in
  let source_for worker index =
    let pair = (index * 17 + worker * 31) mod pairs in
    2 * (pair + (if workload = Disjoint then worker * pairs else 0)) + index mod 2
  in
  let destination_for source = if source mod 2 = 0 then source + 1 else source - 1 in
  for worker = 0 to domains - 1 do
    for index = 0 to warmup - 1 do
      if workload = Read_heavy && index mod 10 <> 0 then ignore (Bank.total bank)
      else
      let source = source_for worker index in
      ignore
        (Bank.transfer bank source
           (destination_for source)
           1)
    done
  done;
  let samples = Array.make (domains * operations) 0. in
  let errors = Array.make (domains * operations) None in
  let ready, cancel_start = start_gate (domains + 1) in
  let workers =
    spawn_all domains cancel_start (fun worker ->
        if ready () then
          for index = 0 to operations - 1 do
            let started = Mtime_clock.elapsed_ns () in
            (try
               if workload = Read_heavy && index mod 10 <> 0 then
                 ignore (Bank.total bank)
               else
                 let source = source_for worker index in
                 let destination = destination_for source in
                 if not (Bank.transfer bank source destination 1) then
                   errors.(worker * operations + index) <- Some "operation was rejected"
             with exn ->
               errors.(worker * operations + index) <- Some (Printexc.to_string exn));
            let finished = Mtime_clock.elapsed_ns () in
            samples.(worker * operations + index) <-
              Int64.to_float (Int64.sub finished started) /. 1_000_000_000.
          done)
  in
  let retries_before = Tl2.retries () in
  let cpu_before = Sys.time () in
  let gc_before = Gc.quick_stat () in
  let started = Mtime_clock.elapsed_ns () in
  if not (ready ()) then failwith "benchmark start gate was cancelled";
  join_all workers;
  let finished = Mtime_clock.elapsed_ns () in
  let cpu_s = Sys.time () -. cpu_before in
  let gc_after = Gc.quick_stat () in
  let elapsed = Int64.to_float (Int64.sub finished started) /. 1_000_000_000. in
  let retries = Tl2.retries () - retries_before in
  let final = Bank.total bank in
  if final <> Array.fold_left ( + ) 0 accounts then
    errors.(0) <- Some "bank total was not conserved";
  let sorted = Array.copy samples in
  Array.sort Float.compare sorted;
  let error_count =
    Array.fold_left
      (fun count error -> count + (if Option.is_some error then 1 else 0))
      0 errors
  in
  let successes = Array.length samples - error_count in
  if successes <= 0 then failwith "benchmark run had no successful operations";
  let summary =
    Printf.sprintf "summary,%s,%s,%d,%d,%d,%d,%.6f,%.3f,%.3f,%.3f,%.3f,%d,%d,,%d,%.6f,%.0f,%d,%d,%d"
      (name_backend backend) (name_workload workload) domains trial
      (Array.length samples) successes elapsed
      (float successes /. elapsed)
      (percentile sorted 0.50 *. 1_000_000.)
      (percentile sorted 0.95 *. 1_000_000.)
      (percentile sorted 0.99 *. 1_000_000.) retries error_count
      (Array.length accounts) cpu_s
      (gc_after.minor_words +. gc_after.major_words -. gc_after.promoted_words
       -. gc_before.minor_words -. gc_before.major_words +. gc_before.promoted_words)
      (gc_after.minor_collections - gc_before.minor_collections)
      (gc_after.major_collections - gc_before.major_collections) stride
  in
  output_string channel (summary ^ "\n");
  Array.iteri
         (fun index sample ->
           if index mod stride = 0 then Printf.fprintf channel "latency,%s,%s,%d,%d,,,,,,,,,,%.3f,%d,,,,,%d\n"
             (name_backend backend) (name_workload workload) domains trial
             (sample *. 1_000_000.) (Array.length accounts) stride)
         samples;
  Array.iteri
         (fun index -> function
           | None -> ()
           | Some message ->
                 Printf.fprintf channel "error,%s,%s,%d,%d,,,,,,,,,,%s,%d,,,,,%d\n"
                    (name_backend backend) (name_workload workload) domains trial
                    (quote_csv (Printf.sprintf "operation %d: %s" index message))
                    (Array.length accounts) stride)
         errors;
  flush channel;
  error_count

let () =
  let output = ref None in
  let operations = ref 1000 and pairs = ref 1 and trials = ref 5 in
  let domains = ref [1; 2; 4] and warmup = ref 100 and stride = ref 1 in
  Arg.parse
    [ ("--output", Arg.String (fun path -> output := Some path), "CSV output path");
      ("--operations", Arg.Set_int operations, "operations per domain");
      ("--pairs", Arg.Set_int pairs, "account pairs per contention group");
      ("--trials", Arg.Set_int trials, "rotated backend repeats (at least five)");
      ("--domains", Arg.String (fun value -> domains := List.map int_of_string (String.split_on_char ',' value)), "comma-separated domain counts");
      ("--warmup", Arg.Set_int warmup, "serial warmup operations per domain");
      ("--latency-stride", Arg.Set_int stride, "retain every Nth latency; tails use all samples") ]
    (fun arg -> raise (Arg.Bad ("unexpected argument: " ^ arg)))
    "stm_bench.exe --output .agents/runs/<id>/bench.csv";
  let output = match !output with Some path -> path | None -> raise (Arg.Bad "--output is required") in
  if !operations < 1 || !operations > 2_000_000 || !pairs < 1 || !pairs > 4096
     || !trials < 5 || !trials > 100 || !warmup < 0 || !warmup > 10000 || !stride < 1
     || !domains = [] || List.exists (fun n -> n < 1 || n > 16 || n * !operations > 2_000_000) !domains
     || List.length !domains <> List.length (List.sort_uniq Int.compare !domains)
  then raise (Arg.Bad "benchmark configuration outside bounded limits");
  if Filename.is_relative output = false || String.contains output '\\'
     || List.mem ".." (String.split_on_char '/' output)
     || not (String.starts_with ~prefix:".agents/runs/" output)
  then raise (Arg.Bad "output path must stay under .agents/runs/");
  if Sys.file_exists output then raise (Arg.Bad "output already exists; choose a new run file");
  let channel = open_out output in
  let failed = ref 0 in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () ->
      output_string channel
        "record_type,backend,workload,domains,trial,operations,successes,elapsed_s,ops_per_s,p50_us,p95_us,p99_us,tl2_retries,errors,latency_us,accounts,cpu_s,allocated_words,minor_collections,major_collections,latency_stride\n";
      List.iter
        (fun workload ->
          List.iter
            (fun domains ->
              for trial = 0 to !trials - 1 do
                let rotated =
                  List.init 3 (fun offset -> List.nth backends ((offset + trial) mod 3))
                in
                List.iter
                  (fun backend ->
                    failed := !failed + run channel backend workload domains trial !operations !pairs !warmup !stride)
                  rotated
              done)
            !domains)
        [ Disjoint; Contended; Read_heavy ]);
  if !failed <> 0 then (Printf.eprintf "benchmark recorded %d failed operations\n" !failed; exit 1)
