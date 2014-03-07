open Core.Std
open Common

  (*highest element is always at head *)
  type 'a t = (Index.t * Index.t * 'a) list with sexp
  let init () = []
  let append new_ele lst = new_ele :: lst
  let appends elements lst = elements @ lst

  let last_index_term = function 
  | [] -> ( Index.init(),Index.init() )
  | (i,t,_)::_ -> (i,t)

  let consistency_check log prev_index prev_term =
    match log with 
    | [] -> `Consistent
    | _::_ -> 
      match List.find log ~f:(fun (index,_,_) -> (index=prev_index)) with
    | Some (_,term,_) when term=prev_term -> `Consistent
    | _ -> `Inconsistent

  let to_string ~cmd_to_string = 
    List.to_string 
      ~f:( fun (i,t,c) -> "Index: "^(Index.to_string i)^
                         " Term: "^(Index.to_string t)^
                         " Cmd: "^(cmd_to_string c)^"\n")

  let to_commit old_index new_index log = 
    (*Log stores most recent at head but need to reply in rev order *)
    List.filter log ~f:( fun (x,_,_) -> (x > old_index) && (x <= new_index ) ) 
    |> List.sort ~cmp:(fun (x,_,_) (y,_,_) -> Index.compare x y) 
    |> List.map ~f:(fun (_,_,cmd) -> cmd)
  let cut_entries new_last_index log =
    List.filter log ~f:(fun (i,_,_) -> i <= new_last_index)



