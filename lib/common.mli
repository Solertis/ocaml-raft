open Core.Std

(** Common is the basic module at the foundation of OCaml-Raft, it uses no other
 * ocaml-raft modules and contains much of the basic functionality used throught
 * *)

(* [role] is the basic mode of operation of a node *)
type role = Follower | Candidate | Leader with sexp

(** [status] wraps around State.t to simulate node failures *)
type 'a status = Live of 'a | Down of 'a | Notfound

type termination = LeaderEst |   WorkloadEmpty 

(** [failures] hows the holds the two possible N actions *)
type failures = Wake | Kill

val string_of_role : role -> string
val string_of_option : ('a -> string) -> 'a option -> string

(** [NumberGen] holds the functionality used for generating random numbers for
 * the simulators, all parameters and results are float, even through there use
 * will often be discrite *)
module NumberGen :
  sig
   (** string_to_dist takes a string specifying parameters and return a random number generaters *)
    val string_to_dist : string -> (unit -> float)
  end

(** [PARAMETERS] defines the outcome the command line options are used the
 * simulator *)  
module type PARAMETERS =
  sig
    (* [timeout role] returns a float returning the timeout using the
     * distribution specified eariler *)
    val timeout : unit -> role -> float
    val nodes : int
    val pkt_delay : unit -> float
    val termination : int
    val debug_mode : bool
    val nxt_failure : (unit -> float) option
    val nxt_recover : (unit -> float) option
    val term_conditions : termination -> bool
    val workload_size: int
  end

(** [Index] is a single monotonically increasing discrete value *) 
module Index :
  sig
    type t with sexp, bin_io, compare
    val succ : t -> t
    val pred : t -> t
    val init : unit -> t
    val to_string : t -> string
  end

(** [IntID] is the identifier used for nodes, this could later be used to store
 * location information *)
module IntID : 
  sig
    type t with sexp, bin_io
    val from_int : int -> t
    val to_int : t -> int
    val equal : t -> t -> bool
    val to_string : t -> string
  end

(** [ListLog] is a cut down version of list used for the replication log to ensure
   * append only *) (*
module ListLog :
  sig
    type 'a t with sexp, bin_io
    val init : unit -> 'a t
    val cons : 'a -> 'a t -> 'a t
    val to_string : f:('a -> string) -> 'a t -> string

  end *)


module Event :
  sig
    type ('time, 'id, 'state,'client) t =
        RaftEvent of ('time * 'id * ('time, 'id, 'state,'client) event)
      | SimulationEvent of ('time * 'id * failures)
      | ClientEvent of ('time * ('time, 'id, 'state,'client) client)
    and ('time, 'id, 'state,'client) event = 'state -> 'state * ('time, 'id, 'state,'client) t list
    and ('time, 'id, 'state,'client) client = 'client -> 'client * ('time, 'id, 'state,'client) t list

    val compare : ('time, 'id, 'state, 'client') t -> ('time, 'id, 'state, 'client') t -> int
  end


