open Coursework_stm

let mkdir_p path =
  let rec ensure current =
    if current = "" || current = "." || Sys.file_exists current then ()
    else (
      ensure (Filename.dirname current);
      Unix.mkdir current 0o755)
  in
  ensure path

let json_escape value =
  let buffer = Buffer.create (String.length value + 8) in
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | c when Char.code c < 0x20 ->
          Buffer.add_string buffer (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char buffer c)
    value;
  Buffer.contents buffer

let write_result path passed details =
  mkdir_p path;
  let file = Filename.concat path "verification.json" in
  let temporary = file ^ ".tmp" in
  if Sys.file_exists file || Sys.file_exists temporary then
    failwith "evidence already exists; choose a new run id";
  let channel = open_out_gen [ Open_wronly; Open_creat; Open_excl; Open_binary ] 0o644 temporary in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () ->
      Printf.fprintf channel
        "{\"passed\":%b,\"cleanup_complete\":true,\"ocaml_version\":\"%s\",\"details\":\"%s\"}\n"
        passed (json_escape Sys.ocaml_version) (json_escape details));
  Sys.rename temporary file

let join_all workers =
  let failures = ref [] in
  Array.iter
    (fun worker ->
      try Domain.join worker with exn -> failures := exn :: !failures)
    workers;
  match !failures with [] -> () | exn :: _ -> raise exn

let spawn_all count work =
  let spawned = ref [] in
  try
    for worker = 0 to count - 1 do
      let domain = Domain.spawn (fun () -> work worker) in
      spawned := domain :: !spawned
    done;
    Array.of_list (List.rev !spawned)
  with exn ->
    List.iter (fun domain -> try ignore (Domain.join domain) with _ -> ()) !spawned;
    raise exn

let transfer_round backend domains =
  let transfers = 250 in
  let starting_balance = domains * 1000 in
  let accounts = Array.make domains starting_balance in
  let bank = Bank.create backend accounts in
  let workers =
    spawn_all domains (fun worker ->
        for _ = 1 to transfers do
          let source = worker mod domains in
          let destination = (source + 1) mod domains in
          if not (Bank.transfer bank source destination 1) then
            failwith "funded transfer was rejected"
        done)
  in
  join_all workers;
  let final = Bank.snapshot bank in
  if Bank.total bank <> domains * starting_balance then
    failwith "bank conservation failed";
  if Array.length final <> domains then failwith "account count changed";
  domains * transfers

let run_checks () =
  if not (String.starts_with ~prefix:"5." Sys.ocaml_version) then
    failwith ("native OCaml 5 required, found " ^ Sys.ocaml_version);
  let work =
    List.concat_map
      (fun domains ->
        List.map
          (fun backend -> transfer_round backend domains)
          [ Bank.Kcas_backend; Bank.Tl2_backend; Bank.Mutex_backend ])
      [ 1; 2; 4 ]
  in
  List.fold_left ( + ) 0 work

let () =
  let doctor = ref false in
  let inject_failure = ref false in
  let evidence = ref None in
  let usage = "stm_verify.exe --doctor | --evidence .agents/runs/<id>" in
  Arg.parse
    [ ("--doctor", Arg.Set doctor, "check the native executable")
    ; ("--inject-failure", Arg.Set inject_failure, "write a failed verdict for the cleanup check")
    ; ("--evidence", Arg.String (fun path -> evidence := Some path), "write run evidence") ]
    (fun argument -> raise (Arg.Bad ("unexpected argument: " ^ argument))) usage;
  if !doctor then (
    if not (String.starts_with ~prefix:"5." Sys.ocaml_version) then
      failwith ("native OCaml 5 required, found " ^ Sys.ocaml_version);
    if not (Filename.basename Sys.executable_name |> String.starts_with ~prefix:"stm_verify") then
      failwith "unexpected verification executable";
    Printf.printf "{\"doctor\":\"ready\",\"ocaml_version\":\"%s\",\"executable\":\"%s\"}\n"
      Sys.ocaml_version (json_escape Sys.executable_name))
  else
    match !evidence with
    | None -> raise (Arg.Bad "--evidence is required unless --doctor is used")
    | Some path ->
        if Filename.is_relative path = false || String.contains path '\\'
           || List.mem ".." (String.split_on_char '/' path)
           || not (String.starts_with ~prefix:".agents/runs/" path)
        then raise (Arg.Bad "evidence path must stay under .agents/runs/<id>");
        let result =
          try
            let operations = run_checks () in
            if !inject_failure then failwith "deliberate verification failure";
            ( true,
              Printf.sprintf
                "completed %d successful transfers across 1, 2, and 4 domains with Kcas, TL2, and Mutex"
                operations )
          with exn -> (false, Printexc.to_string exn)
        in
        write_result path (fst result) (snd result);
        Printf.printf
          "{\"passed\":%b,\"cleanup_complete\":true,\"tl2_retries\":%d,\"details\":\"%s\"}\n"
          (fst result) (Tl2.retries ()) (json_escape (snd result));
        if not (fst result) then exit 1
