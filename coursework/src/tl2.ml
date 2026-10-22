type state = Unlocked of int * int | Locked of int

type cell = { id : int; state : state Atomic.t }

type observation = { cell : cell; state : state; value : int }

type transaction = {
  owner : int;
  start_version : int;
  reads : (int, observation) Hashtbl.t;
  writes : (int, int) Hashtbl.t;
}

exception Conflict
exception Retry_limit of int
exception Version_overflow
exception Identity_overflow
exception Identity_contention

let clock = Atomic.make 0
let next_id = Atomic.make 0
let retry_count = Atomic.make 0

let fresh_id () =
  let rec allocate attempts =
    if attempts = 0 then raise Identity_contention;
    let id = Atomic.get next_id in
    if id = max_int then raise Identity_overflow;
    if Atomic.compare_and_set next_id id (id + 1) then id
    else allocate (attempts - 1)
  in
  allocate 64

let create value = { id = fresh_id (); state = Atomic.make (Unlocked (value, 0)) }

let observe tx cell =
  match Hashtbl.find_opt tx.reads cell.id with
  | Some entry -> entry
  | None ->
      let rec load attempts =
        if attempts = 0 then raise Conflict;
        let before = Atomic.get cell.state in
        match before with
        | Locked _ -> raise Conflict
        | Unlocked (value, version) ->
            if version > tx.start_version then raise Conflict;
            let after = Atomic.get cell.state in
            if before != after then load (attempts - 1)
            else
              let entry = { cell; state = before; value } in
              Hashtbl.add tx.reads cell.id entry;
              entry
      in
      load 8

let read tx cell =
  match Hashtbl.find_opt tx.writes cell.id with
  | Some value -> value
  | None -> (observe tx cell).value

let write tx cell value =
  ignore (observe tx cell);
  Hashtbl.replace tx.writes cell.id value

let next_version () =
  let rec advance attempts =
    if attempts = 0 then raise Conflict;
    let version = Atomic.get clock in
    if version = max_int then raise Version_overflow;
    if Atomic.compare_and_set clock version (version + 1) then version + 1
    else advance (attempts - 1)
  in
  advance 64

let entries tx =
  Hashtbl.fold (fun _ entry acc -> entry :: acc) tx.reads []
  |> List.sort (fun left right -> Int.compare left.cell.id right.cell.id)

let unlock owner entry =
  match Atomic.get entry.cell.state with
  | Locked held_by when held_by = owner ->
      Atomic.set entry.cell.state entry.state
  | _ -> failwith "TL2 lost ownership of a write lock"

let validate tx entries =
  List.iter
    (fun entry ->
      match Hashtbl.mem tx.writes entry.cell.id with
      | false ->
          if Atomic.get entry.cell.state != entry.state then raise Conflict
      | true -> (
          match Atomic.get entry.cell.state with
          | Locked owner when owner = tx.owner -> ()
          | _ -> raise Conflict))
    entries

let commit ?(after_lock = fun _ -> ()) ?(after_version = fun _ -> ())
    ?(before_publish = fun () -> ()) tx result =
  if Hashtbl.length tx.writes = 0 then (
    (* Read-only validation needs no lock ordering or temporary sorted list. *)
    Hashtbl.iter
      (fun _ entry ->
        if Atomic.get entry.cell.state != entry.state then raise Conflict)
      tx.reads;
    result)
  else
  let entries = entries tx in
  let write_entries =
    List.filter (fun entry -> Hashtbl.mem tx.writes entry.cell.id) entries
    |> Array.of_list
  in
  if Array.length write_entries = 0 then (
    validate tx entries;
    result)
  else
    let acquired = ref 0 in
    let release () =
      for index = 0 to !acquired - 1 do
        unlock tx.owner write_entries.(index)
      done
    in
    try
      for index = 0 to Array.length write_entries - 1 do
        let entry = write_entries.(index) in
        if Atomic.compare_and_set entry.cell.state entry.state (Locked tx.owner) then (
          incr acquired;
          after_lock !acquired)
        else raise Conflict
      done;
      let version = next_version () in
      after_version version;
      validate tx entries;
      let publications =
        Array.map
          (fun entry ->
            let value = Hashtbl.find tx.writes entry.cell.id in
            (entry, Unlocked (value, version)))
          write_entries
      in
      before_publish ();
      for index = 0 to Array.length publications - 1 do
        let entry, replacement = publications.(index) in
        Atomic.set entry.cell.state replacement
      done;
      result
    with exn ->
      release ();
      raise exn

let attempt_with_hooks ?(after_lock = fun _ -> ())
    ?(after_version = fun _ -> ()) ?(before_publish = fun () -> ()) f =
  try
    let tx =
      {
        owner = fresh_id ();
        start_version = Atomic.get clock;
        reads = Hashtbl.create 8;
        writes = Hashtbl.create 8;
      }
    in
    Some
      (commit ~after_lock ~after_version ~before_publish tx (f tx))
  with Conflict | Identity_contention -> None

module Testing = struct
  let attempt_with_lock_hook ~after_lock f =
    attempt_with_hooks ~after_lock f

  let attempt_with_version_hook ~after_version f =
    attempt_with_hooks ~after_version f

  let attempt_with_publish_hook ~before_publish f =
    attempt_with_hooks ~before_publish f
end

let attempt f = attempt_with_hooks f

let transact ?(max_retries = 100) f =
  if max_retries < 1 then invalid_arg "TL2.transact: max_retries must be positive";
  let rec retry remaining backoff =
    match attempt f with
    | Some result -> result
    | None ->
        Atomic.fetch_and_add retry_count 1 |> ignore;
        if remaining = 1 then raise (Retry_limit max_retries);
        retry (remaining - 1) (Backoff.once backoff)
  in
  retry max_retries Backoff.default

let retries () = Atomic.get retry_count
