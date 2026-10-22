type t
type backend = Kcas_backend | Tl2_backend | Mutex_backend

val create : backend -> int array -> t
val transfer : t -> int -> int -> int -> bool
val snapshot : t -> int array
val total : t -> int
