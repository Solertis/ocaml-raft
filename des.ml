open Core.Std
open Common
open Clock
open Env
open EventList
open Event


module DEventSim = 
  functor (Id:ID) -> 
  functor (MonoTime: TIME) ->
  functor (Index: INDEX) ->
  functor (Entry: ENTRY) ->
  functor (L:LOG) ->
  functor (P:PARAMETERS) -> struct

module State = PureState(Id)(MonoTime)(Index)(Entry)(L)

debug_active := P.debug_mode

let () = Random.self_init ()
(* TODO: check it one timeout should be used for other electons and followers*)
let timeout (m:role) = MonoTime.span_of_int (P.timeout m)

let unicast (dist:Id.t) (t:MonoTime.t) e = 
  (*TODO: modify these to allow the user to specify some deley
   * distribution/bound *)
  let delay = MonoTime.span_of_int (P.pkt_delay()) in
  let arriv = MonoTime.add t delay in
  E (arriv ,dist ,e ) 

let broadcast (dests:Id.t list) (t:MonoTime.t) e  = 
  List.map dests ~f:(fun dst -> unicast dst t e) 

let checkElection (s:State.t) = 
  (* TODO: check exactly def of majority, maybe off by one error here *)
  (List.length s.votesGranted) > ((List.length s.allNodes)+1)/2

type checker = Follower_Timeout of Index.t 
             | Candidate_Timeout of Index.t
             | Leader_Timeout of Index.t
             (*what event triggered a check of electron outcome *)

let rec incrTime s = (State.tick IncrementTime s, [])

and startCand (s:State.t) = debug "Entering Candidate Mode / Restarting Electon";
  let snew =  State.tick StartCandidate s in
  let reqs = broadcast snew.allNodes s.time 
    (requestVoteRq snew.term snew.id snew.lastlogIndex
    snew.lastlogTerm) in
  let t = MonoTime.add snew.time (timeout Candidate) in
  (snew, E (t, s.id, checkTimer (Candidate_Timeout snew.term) )::reqs )

and checkTimer c (s:State.t)  = debug "Checking timer"; 
  let next_timer c_new (s:State.t) = 
    let t =  MonoTime.add s.time (timeout Follower) in
    (State.tick Reset s, [ E (t, s.id, checkTimer c_new )]) in
  (* TODO: this about the case where the nodes has gone to candidate and back to
   * follower, how do we check for this case *)
  match c,s.mode with
  | Follower_Timeout term, Follower when term = s.term -> 
    (* if heartbeat is true, we have rec a packet in the last election timeout*)
    if s.timer then next_timer (Follower_Timeout s.term) s  
    (* we have timedout so become candidate *)
    else (startCand s)
  | Candidate_Timeout term, Candidate when term = s.term -> (startCand s)
  | Leader_Timeout term, Leader when term = s.term -> (dispatchHeartbeat s)
  | _ -> debug "Timer no longer valid"; (s,[])

and dispatchHeartbeat (s:State.t) =
  let reqs = broadcast s.allNodes s.time 
    (heartbeatRq s.term s.id) in
  let t = MonoTime.add s.time (timeout Leader) in
  (s, E (t, s.id, checkTimer (Leader_Timeout s.term) )::reqs )


and startFollow term (s:State.t)  = debug "Entering Follower mode";
  (* used for setdown too so need to reset follower state *)
  let t = MonoTime.add s.time (timeout Follower) in
  let s = State.tick (StepDown term) s in 
  (s,[ E (t, s.id,checkTimer (Follower_Timeout s.term) )])

and startLeader (s:State.t) = debug "Election Won - Becoming Leader";
  dispatchHeartbeat (State.tick StartLeader s)

and stepDown term (s:State.t) = 
  if (term > s.term) 
  then match s.mode with | Leader | Candidate -> startFollow term s
                         | Follower -> ((State.tick (SetTerm term) s),[])
  
  else (s,[])
  (* TODO check if this case it handled correctly *)
  (* else if (term=s.term) && (s.mode=Leader) then startFollower term s *) 

  (* TODO ask anil why s needs to explicitly annotated to access its field *)
and requestVoteRq term cand_id lst_index last_term (s:State.t) =
  debug ("I've got a vote request from: "^ Id.to_string cand_id^ 
         " term number: "^Index.to_string term);
  (* TODO: this is a Simulated Response so allows granting vote
   * , need todo properly *)
  let s_new,e_new =  stepDown term s in
  let vote = (term = s_new.term) && (lst_index >= s.lastlogIndex ) 
    && (last_term >= s.lastlogTerm ) && (s.votedFor = None) in
  let s_new = 
   ( if vote then 
      (State.tick (Vote cand_id) s 
      |> State.tick Set )
    else 
      s_new )in
  (s_new, [unicast cand_id s_new.time (requestVoteRs s_new.term vote s_new.id )])
  
and requestVoteRs term voteGranted id (s:State.t) = 
  debug ("Receive vote request reply from "^ Id.to_string id );
  (* TODO: consider how term check may effect old votes in the network *)
  if (term > s.term)  then startFollow term s
  else if (voteGranted) 
    then begin 
      debug "Vote was granted";
      let s = State.tick (VoteFrom id) s in
      (if (checkElection s) then startLeader s else  (s, [])) end
    else (s, [])

and heartbeatRq term lead_id (s:State.t) =
  debug ("Recieve hearbeat from "^Id.to_string lead_id);
  let s_new,e_new = stepDown term s in
  if (term = s_new.term) then 
    let s_new = State.tick Set s |> State.tick (SetLeader lead_id) in
    (s_new,[unicast lead_id s_new.time (heartbeatRs s_new.term ) ])
  else 
    (s_new,[unicast lead_id s_new.time (heartbeatRs s_new.term)])

and heartbeatRs term (s:State.t) =
  let s_new,e_new = stepDown term s in
  (s_new,e_new)


(*and checkTimer c s =
  debug "Check Timer";
  match c with 
  | Follower_Timeout -> 
  | Candidate_TImeout -> 
*)
(*
let rec run ~term (s:State.t) (el: (MonoTime.t,State.t) EventList.t)  = 
  (* checking for termination conditions *)
  match el with 
  | []-> debug "terminating as no events remain" 
  | l -> ( 
    if ( match term with | Some tt -> (tt=s.time) | _ -> false )
      then debug "terminating as terminate time has been reached"
      else (
    match (EventList.find s.time l) with
    | Some (e,ls) -> 
        let s_new,e_new = e s in
        State.print s_new;
        run ~term s_new (EventList.add e_new ls)
    | None -> 
        debug "Incrementing Time"; State.print s;
        run ~term (State.tick IncrementTime s) el )) 
*)

let finished (sl: (Id.t,State.t) List.Assoc.t) =
  let leader,term= match (List.Assoc.find sl (Id.from_int 0)) with 
    Some s -> s.leader,s.term in
  let f (_,(state:State.t)) = 
    not ((state.leader = leader) || (state.term = term)) in 
  match (List.find sl ~f) with
  | Some x -> true | _ -> false

let printline =  "---------------------------------------------------\n"

let get_time (sl: (Id.t,State.t) List.Assoc.t) = 
  let state = match (List.Assoc.find sl (Id.from_int 0)) with Some x -> x in
  MonoTime.to_string state.time

let rec run_multi ~term
  (sl: (Id.t,State.t) List.Assoc.t) 
  (el:(MonoTime.t,Id.t,State.t) EventList.t)  =
  (* addition termination condition for tests *)
    if (finished sl) 
    then begin
     (*  debug "terminating as leader has been agreed";*)
       (* for graph gen. *) printf "%s \n" (get_time sl) end
    else
  match EventList.hd el with
  | None -> debug "terminating as no events remain"
  | Some (E (t,id,e),els) -> if (t>=term) 
    then debug "terminating as terminate time has been reached"
    else  match (List.Assoc.find sl id) with 
      | Some s -> 
        let s = State.tick (SetTime t) s in
        let s_new,el_new = e s in
        debug (State.print s_new); debug printline;
        run_multi ~term (List.Assoc.add sl id s_new) (EventList.add el_new els) 
      | None -> debug "node is unavaliable";
        run_multi ~term sl els
        
  (*  let f ((s,el):(State.t * (MonoTime.t,State.t) EventList.t)) = 
    run  ~term:(Some (MonoTime.succ s.time)) s el in
  (* run each node for one time unit *)
  let l_new =  List.map ~f l in 
  (* collect events across the nodes *)
  let all_ids = List.map ~f:(fun (s,_) ->  s.allNodes) l_new 
             |> Caml.List.flatten in
  let msgs n = List.map ~f:(fun node -> if (Id.to_int node = n) then Id.collect
              else []) |> Caml.List.flatten in
  List.map ~f:(fun n (s,el) -> (s,EventList.add el (msgs n))) l_new
  |> run_multi *)
 

let eventlist num  :(MonoTime.t,Id.t,State.t) Event.t list  =  
  let initial = List.init num ~f:(fun i ->
    E (MonoTime.init(), Id.from_int i, startFollow (Index.init()) ) ) in
  EventList.from_list initial

let statelist (num:int) = 
  let id_list = List.init num ~f:(Id.from_int) in
  let remove x xs = List.filter xs ~f:(fun y -> not (x = y)) in 
  List.map ~f:(fun node -> node, State.init node (remove node id_list)) id_list

let start () = 
  run_multi ~term:(MonoTime.t_of_int P.termination) 
  (statelist P.nodes)  
  (eventlist P.nodes)
end


(*let create_para ~nodes ~term ~time_min ~time_max ~delay_min ~delay_max ~debug = 
  let outcome = (module struct
    let () = Random.self_init ()
    let nodes = nodes
    let timeout () = ((Random.int (time_max-time_min)) + time_min)
    let pkt_delay () = ((Random.int (delay_max-delay_min)) + delay_min)
    let termination = term
    let debug_mode = debug
  end : PARAMETERS) in outcome*)

(*module Para = (val (create_para ~nodes:2): PARAMETERS)   
module DES =  DEventSim(IntID)(FakeTime)(Index)(LogEntry)(ListLog)(Para) *)

let run ~nodes ~term ~time_min ~time_max ~delay_min ~delay_max ~debug ~iter
  ~data =
  let module Par = (struct
    let () = Random.self_init ()
    let nodes = nodes
    let timeout = function
      | Leader -> 5
      | Follower | Candidate -> ((Random.int (time_max-time_min)) + time_min)
    let pkt_delay () = ((Random.int (delay_max-delay_min)) + delay_min)
    let termination = term
    let debug_mode = debug
    let write_data (v:string) = 
      match data with 
      | Some file -> () 
      | None -> ()
  end : PARAMETERS) in 
  let module DES =  DEventSim(IntID)(FakeTime)(Index)(LogEntry)(ListLog)(Par) in
  for i=0 to iter do DES.start() done
 (* DES.run_multi 
  ~term:(FakeTime.t_of_int 500)
  (DES.statelist 20)
  (DES.eventlist 20) *)

let command =
  Command.basic 
    ~summary:"Discrete Event Simulator for Raft's Leader Election"
    ~readme: (fun () -> "see www.cl.cam.ac.uk/~hh360 for more information ")
    Command.Spec.(
      empty
      +> flag "-nodes" (required int) 
        ~doc:"int Number of nodes to simulate"
      +> flag "-term" (optional_with_default 500 int)
        ~doc:"int The maxiumun number of terms before termination"
      +> flag "-time-min" (optional_with_default 10 int)
        ~doc:"int The minimum timeout used"
      +> flag "-time-max" (optional_with_default 15 int)
        ~doc:"int The max timeout used"
      +> flag "-delay-min" (optional_with_default 1 int)
        ~doc:"int The min packet delay"
      +> flag "-delay-max" (optional_with_default 5 int)
        ~doc:"int The max delay of packets"
      +> flag "-d" (optional_with_default true bool)
        ~doc:"bool Enable debug (disabled by default)"
      +> flag "-iter" (optional_with_default 1 int) 
        ~doc:"int Number of Simulations"
      +> flag "-data" (optional string) 
        ~doc:"filename File to output data to as .data"
    )
    (fun nodes term time_min time_max delay_min delay_max debug iter data () -> 
      run ~nodes ~term ~time_min ~time_max ~delay_min ~delay_max ~debug ~iter
      ~data )

let () =  Command.run command