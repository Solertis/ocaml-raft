(* This file has been auto-generated by the SPL compiler *)
exception Bad_statecall

type s = [
  |`RestartElection
  |`StartElection
  |`Startup
  |`StepDown_from_Candidate
  |`StepDown_from_Leader
  |`WinElection
  |`Recover
]

type t
val init : unit -> t
val pagefn : out_channel -> unit
val set_cfn : t -> (unit -> (out_channel * in_channel)) -> unit
val tick : t -> [> s] -> t
