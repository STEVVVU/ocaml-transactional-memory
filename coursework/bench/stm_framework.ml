open Coursework_stm
open Multicore_bench

let run_read_only ~backend ~domains ~budgetf =
  let accounts = 8192 in
  let operations = 100 in
  let expected = accounts * 1_000_000 in
  let bank = Bank.create backend (Array.make accounts 1_000_000) in
  let init _ = () in
  let work _ () =
    for _ = 1 to operations do
      if Bank.total bank <> expected then failwith "read-only total mismatch"
    done
  in
  Times.record ~budgetf ~n_domains:domains ~n_warmups:3 ~n_runs_min:5
    ~n_runs_max:5 ~init ~work ()
  |> Times.to_thruput_metrics ~n:(operations * domains) ~singular:"snapshot"
       ~config:(Printf.sprintf "%d accounts, %d domains" accounts domains)

let () =
  let backends =
    [ ("kcas", Bank.Kcas_backend); ("tl2", Bank.Tl2_backend);
      ("mutex", Bank.Mutex_backend) ]
  in
  let benchmarks =
    List.concat_map
      (fun (name, backend) ->
        List.filter_map
          (fun domains ->
            if domains > Domain.recommended_domain_count () then None
            else
              Some
                (Printf.sprintf "%s readonly %d domains" name domains,
                 run_read_only ~backend ~domains))
          [ 1; 2; 4 ])
      backends
  in
  Cmd.run ~benchmarks ~budgetf:1. ()
