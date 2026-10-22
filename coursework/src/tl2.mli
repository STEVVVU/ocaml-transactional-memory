type cell
type transaction

exception Retry_limit of int
exception Version_overflow
exception Identity_overflow

(** Raised if an identity allocation is too contended to finish in its bounded
    compare-and-set loop. Transactions retry this condition automatically. *)
exception Identity_contention

val create : int -> cell
val read : transaction -> cell -> int
val write : transaction -> cell -> int -> unit
val attempt : (transaction -> 'a) -> 'a option
module Testing : sig
  (** [after_lock] runs after each write lock is acquired. *)
  val attempt_with_lock_hook :
    after_lock:(int -> unit) -> (transaction -> 'a) -> 'a option

  (** [after_version] runs after the commit version is reserved and before
      read-set validation. *)
  val attempt_with_version_hook :
    after_version:(int -> unit) -> (transaction -> 'a) -> 'a option

  (** [before_publish] runs after replacement states are allocated and before
      any shared cell is updated. *)
  val attempt_with_publish_hook :
    before_publish:(unit -> unit) -> (transaction -> 'a) -> 'a option
end
val transact : ?max_retries:int -> (transaction -> 'a) -> 'a
val retries : unit -> int
