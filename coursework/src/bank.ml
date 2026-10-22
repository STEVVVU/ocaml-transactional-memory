type backend_state =
  | Kcas of int Kcas.Loc.t array
  | Tl2 of Tl2.cell array
  | Mutex of int array * Mutex.t

type t = backend_state
type backend = Kcas_backend | Tl2_backend | Mutex_backend

let create backend initial =
  if Array.exists (fun balance -> balance < 0) initial then
    invalid_arg "Bank.create: balances must be non-negative";
  ignore
    (Array.fold_left
       (fun total balance ->
         if balance > max_int - total then
           invalid_arg "Bank.create: total balance exceeds max_int";
         total + balance)
       0 initial);
  match backend with
  | Kcas_backend -> Kcas (Array.map Kcas.Loc.make initial)
  | Tl2_backend -> Tl2 (Array.map Tl2.create initial)
  | Mutex_backend -> Mutex (Array.copy initial, Mutex.create ())

let check_accounts length source destination amount =
  if source < 0 || source >= length || destination < 0 || destination >= length
  then invalid_arg "Bank.transfer: account index out of bounds";
  if amount < 0 then invalid_arg "Bank.transfer: amount must be non-negative"

let protect lock f =
  Mutex.lock lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock lock) f

let transfer bank source destination amount =
  let length =
    match bank with
    | Kcas cells -> Array.length cells
    | Tl2 cells -> Array.length cells
    | Mutex (cells, _) -> Array.length cells
  in
  check_accounts length source destination amount;
  match bank with
  | Kcas cells ->
      Kcas.Xt.commit
        {
          tx =
            (fun ~xt ->
              if source = destination then true
              else
                let source_balance = Kcas.Xt.get ~xt cells.(source) in
                if source_balance < amount then false
                else
                  let destination_balance = Kcas.Xt.get ~xt cells.(destination) in
                  if destination_balance > max_int - amount then false
                  else (
                  Kcas.Xt.set ~xt cells.(source) (source_balance - amount);
                  Kcas.Xt.set ~xt cells.(destination) (destination_balance + amount);
                  true));
        }
  | Tl2 cells ->
      Tl2.transact (fun tx ->
          if source = destination then true
          else
            let source_balance = Tl2.read tx cells.(source) in
            if source_balance < amount then false
            else (
              let destination_balance = Tl2.read tx cells.(destination) in
              if destination_balance > max_int - amount then false
              else (
                Tl2.write tx cells.(source) (source_balance - amount);
                Tl2.write tx cells.(destination) (destination_balance + amount);
                true)))
  | Mutex (cells, lock) ->
      protect lock (fun () ->
          if source = destination then true
          else if cells.(source) < amount then false
          else if cells.(destination) > max_int - amount then false
          else (
            cells.(source) <- cells.(source) - amount;
            cells.(destination) <- cells.(destination) + amount;
            true))

let snapshot bank =
  match bank with
  | Kcas cells ->
      Kcas.Xt.commit
        {
          tx = (fun ~xt -> Array.map (Kcas.Xt.get ~xt) cells);
        }
  | Tl2 cells ->
      Tl2.transact (fun tx -> Array.map (Tl2.read tx) cells)
  | Mutex (cells, lock) -> protect lock (fun () -> Array.copy cells)

let total bank = Array.fold_left ( + ) 0 (snapshot bank)
