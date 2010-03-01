(**************************************************************************)
(*                                                                        *)
(*  Copyright (C) 2010-                                                   *)
(*    Francois Bobot                                                      *)
(*    Jean-Christophe Filliatre                                           *)
(*    Johannes Kanig                                                      *)
(*    Andrei Paskevich                                                    *)
(*                                                                        *)
(*  This software is free software; you can redistribute it and/or        *)
(*  modify it under the terms of the GNU Library General Public           *)
(*  License version 2.1, with the special exception on linking            *)
(*  described in file LICENSE.                                            *)
(*                                                                        *)
(*  This software is distributed in the hope that it will be useful,      *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                  *)
(*                                                                        *)
(**************************************************************************)

open Util
open Format
open Pp
open Ident
open Ty
open Term
open Ptree
open Theory

(** errors *)

type error = 
  | Message of string
  | ClashType of string
  | DuplicateTypeVar of string
  | UnboundType of string
  | TypeArity of qualid * int * int
  | Clash of string
  | PredicateExpected
  | TermExpected
  | UnboundSymbol of string
  | TermExpectedType of (formatter -> unit) * (formatter -> unit) 
      (* actual / expected *)
  | BadNumberOfArguments of Ident.ident * int * int 
  | ClashTheory of string
  | ClashNamespace of string
  | UnboundTheory of string
  | AlreadyTheory of string
  | UnboundNamespace of string
  | UnboundFile of string
  | UnboundDir of string
  | AmbiguousPath of string * string
  | NotInLoadpath of string
  | CyclicTypeDef
  | UnboundTypeVar of string

exception Error of error

let error ?loc e = match loc with
  | None -> raise (Error e)
  | Some loc -> raise (Loc.Located (loc, Error e))

let rec print_qualid fmt = function
  | Qident s -> fprintf fmt "%s" s.id
  | Qdot (m, s) -> fprintf fmt "%a.%s" print_qualid m s.id

let report fmt = function
  | Message s ->
      fprintf fmt "%s" s
  | ClashType s ->
      fprintf fmt "clash with previous type %s" s
  | DuplicateTypeVar s ->
      fprintf fmt "duplicate type parameter %s" s
  | UnboundType s ->
       fprintf fmt "Unbound type '%s'" s
  | TypeArity (id, a, n) ->
      fprintf fmt "@[The type %a expects %d argument(s),@ " print_qualid id a;
      fprintf fmt "but is applied to %d argument(s)@]" n
  | Clash id ->
      fprintf fmt "Clash with previous symbol %s" id
  | PredicateExpected ->
      fprintf fmt "syntax error: predicate expected"
  | TermExpected ->
      fprintf fmt "syntax error: term expected"
  | UnboundSymbol s ->
       fprintf fmt "Unbound symbol '%s'" s
  | BadNumberOfArguments (s, n, m) ->
      fprintf fmt "@[Symbol `%s' is applied to %d terms,@ " s.id_short n;
      fprintf fmt "but is expecting %d arguments@]" m
  | TermExpectedType (ty1, ty2) ->
      fprintf fmt "@[This term has type "; ty1 fmt; 
      fprintf fmt "@ but is expected to have type@ "; ty2 fmt; fprintf fmt "@]"
  | ClashTheory s ->
      fprintf fmt "clash with previous theory %s" s
  | ClashNamespace s ->
      fprintf fmt "clash with previous namespace %s" s
  | UnboundTheory s ->
      fprintf fmt "unbound theory %s" s
  | AlreadyTheory s ->
      fprintf fmt "already using a theory with name %s" s
  | UnboundNamespace s ->
      fprintf fmt "unbound namespace %s" s
  | UnboundFile s ->
      fprintf fmt "no such file %s" s
  | UnboundDir s ->
      fprintf fmt "no such directory %s" s
  | AmbiguousPath (f1, f2) ->
      fprintf fmt "@[ambiguous path:@ both `%s'@ and `%s'@ match@]" f1 f2
  | NotInLoadpath f ->
      fprintf fmt "cannot find `%s' in loadpath" f
  | CyclicTypeDef ->
      fprintf fmt "cyclic type definition"
  | UnboundTypeVar s ->
      fprintf fmt "unbound type variable '%s" s


(** Environments *)

module S = Set.Make(String)
module M = Map.Make(String)

type env = {
  loadpath : string list;
  theories : theory M.t; (* local theories *)
}

let create lp = {
  loadpath = lp;
  theories = M.empty;
}

(** typing using destructive type variables 

    parsed trees        intermediate trees       typed trees
      (Ptree)               (D below)               (Term)
   -----------------------------------------------------------
     ppure_type  ---dty--->   dty       ---ty--->    ty
      lexpr      --dterm-->   dterm     --term-->    term
      lexpr      --dfmla-->   dfmla     --fmla-->    fmla

*)

(** types with destructive type variables *)

type dty =
  | Tyvar of type_var
  | Tyapp of tysymbol * dty list
      
and type_var = { 
  tag : int; 
  user : bool;
  tvsymbol : tvsymbol;
  mutable type_val : dty option;
}

let rec print_dty fmt = function
  | Tyvar { type_val = Some t } ->
      print_dty fmt t
  | Tyvar { type_val = None; tvsymbol = v } ->
      fprintf fmt "'%s" v.id_short
  | Tyapp (s, []) ->
      fprintf fmt "%s" s.ts_name.id_short
  | Tyapp (s, [t]) -> 
      fprintf fmt "%a %s" print_dty t s.ts_name.id_short
  | Tyapp (s, l) -> 
      fprintf fmt "(%a) %s" 
	(print_list comma print_dty) l s.ts_name.id_short

let create_type_var =
  let t = ref 0 in
  fun ~user tv -> 
    incr t; 
    { tag = !t; user = user; tvsymbol = tv; type_val = None }

let rec occurs v = function
  | Tyvar { type_val = Some t } -> occurs v t
  | Tyvar { tag = t; type_val = None } -> v.tag = t
  | Tyapp (_, l) -> List.exists (occurs v) l

(* destructive type unification *)
let rec unify t1 t2 = match t1, t2 with
  | Tyvar { type_val = Some t1 }, _ ->
      unify t1 t2
  | _, Tyvar { type_val = Some t2 } ->
      unify t1 t2
  | Tyvar v1, Tyvar v2 when v1.tag = v2.tag ->
      true
	(* instantiable variables *)
  | Tyvar ({user=false} as v), t
  | t, Tyvar ({user=false} as v) ->
      not (occurs v t) && (v.type_val <- Some t; true)
	(* recursive types *)
  | Tyapp (s1, l1), Tyapp (s2, l2) ->
      s1 == s2 && List.length l1 = List.length l2 &&
	  List.for_all2 unify l1 l2
  | Tyapp _, _ | _, Tyapp _ ->
      false
	(* other cases *)
  | Tyvar {user=true; tag=t1}, Tyvar {user=true; tag=t2} -> 
      t1 = t2

(** Destructive typing environment, that is
    environment + local variables.
    It is only local to this module and created with [create_denv] below. *)

type denv = { 
  th : theory_uc; (* the theory under construction *)
  utyvars : (string, type_var) Hashtbl.t; (* user type variables *)
  dvars : dty M.t; (* local variables, to be bound later *)
}

let create_denv th = { 
  th = th; 
  utyvars = Hashtbl.create 17; 
  dvars = M.empty;
}

let find_user_type_var x env =
  try
    Hashtbl.find env.utyvars x
  with Not_found ->
    (* TODO: shouldn't we localize this ident? *)
    let v = create_tvsymbol (id_fresh x) in
    let v = create_type_var ~user:true v in
    Hashtbl.add env.utyvars x v;
    v
 
(* Specialize *)

module Htv = Hid

let find_type_var env tv =
  try
    Htv.find env tv
  with Not_found ->
    let v = create_type_var ~user:false tv in
    Htv.add env tv v;
    v
 
let rec specialize env t = match t.ty_node with
  | Ty.Tyvar tv -> 
      Tyvar (find_type_var env tv)
  | Ty.Tyapp (s, tl) ->
      Tyapp (s, List.map (specialize env) tl)

(** generic find function using a path *)

let find_local_namespace {id=x; id_loc=loc} ns = 
  try Mnm.find x ns.ns_ns
  with Not_found -> error ~loc (UnboundNamespace x)

let rec find_namespace q ns = match q with
  | Qident t -> find_local_namespace t ns
  | Qdot (q, t) -> let ns = find_namespace q ns in find_local_namespace t ns

let rec find f q ns = match q with
  | Qident x -> f x ns
  | Qdot (m, x) -> let ns = find_namespace m ns in f x ns

(** specific find functions using a path *)

let find_tysymbol {id=x; id_loc=loc} ns = 
  try Mnm.find x ns.ns_ts
  with Not_found -> error ~loc (UnboundType x)

let find_tysymbol p th = 
  find find_tysymbol p (get_namespace th)

let specialize_tysymbol x env =
  let s = find_tysymbol x env.th in
  let env = Htv.create 17 in
  s, List.map (find_type_var env) s.ts_args
	
let find_fsymbol {id=x; id_loc=loc} ns = 
  try Mnm.find x ns.ns_fs
  with Not_found -> error ~loc (UnboundSymbol x)

let find_fsymbol p th = 
  find find_fsymbol p (get_namespace th)

let specialize_fsymbol s =
  let tl, t = s.fs_scheme in
  let env = Htv.create 17 in
  s, List.map (specialize env) tl, specialize env t

let find_psymbol {id=x; id_loc=loc} ns = 
  try Mnm.find x ns.ns_ps
  with Not_found -> error ~loc (UnboundSymbol x)

let find_psymbol p th =
  find find_psymbol p (get_namespace th)

let specialize_psymbol s =
  let env = Htv.create 17 in
  s, List.map (specialize env) s.ps_scheme

(** Typing types *)

let rec qloc = function
  | Qident x -> x.id_loc
  | Qdot (m, x) -> Loc.join (qloc m) x.id_loc

(* parsed types -> intermediate types *)
let rec dty env = function
  | PPTtyvar {id=x} -> 
      Tyvar (find_user_type_var x env)
  | PPTtyapp (p, x) ->
      let loc = qloc x in
      let s, tv = specialize_tysymbol x env in
      let np = List.length p in
      let a = List.length tv in
      if np <> a then error ~loc (TypeArity (x, a, np));
      Tyapp (s, List.map (dty env) p)

(* intermediate types -> types *)
let rec ty = function
  | Tyvar { type_val = Some t } ->
      ty t
  | Tyvar { tvsymbol = tv } ->
      Ty.ty_var tv
  | Tyapp (s, tl) ->
      Ty.ty_app s (List.map ty tl)

(** Typing terms and formulas *)

type dterm = { dt_node : dterm_node; dt_ty : dty }

and dterm_node =
  | Tvar of string
  | Tconst of constant
  | Tapp of fsymbol * dterm list
  | Tlet of dterm * string * dterm
(*   | Tcase of dterm * tbranch list *)
  | Teps of string * dfmla

and dfmla = 
  | Fapp of psymbol * dterm list
  | Fquant of quant * string * dty * dfmla
  | Fbinop of binop * dfmla * dfmla
  | Fnot of dfmla
  | Ftrue
  | Ffalse
  | Fif of dfmla * dfmla * dfmla
(*   | Flet of dterm * string * dfmla *)
(*   | Fcase of dterm * (pattern * dfmla) list *)

let binop = function
  | PPand -> Fand
  | PPor -> For
  | PPimplies -> Fimplies
  | PPiff -> Fiff

let rec dterm env t = 
  let n, ty = dterm_node t.pp_loc env t.pp_desc in
  { dt_node = n; dt_ty = ty }

and dterm_node loc env = function
  | PPvar (Qident {id=x}) when M.mem x env.dvars ->
      (* local variable *)
      let ty = M.find x env.dvars in
      Tvar x, ty
  | PPvar x -> 
      (* 0-arity symbol (constant) *)
      let s = find_fsymbol x env.th in
      let s, tyl, ty = specialize_fsymbol s in
      let n = List.length tyl in
      if n > 0 then error ~loc (BadNumberOfArguments (s.fs_name, 0, n));
      Tapp (s, []), ty
  | PPapp (x, tl) ->
      let s = find_fsymbol x env.th in
      let s, tyl, ty = specialize_fsymbol s in
      let tl = dtype_args s.fs_name loc env tyl tl in
      Tapp (s, tl), ty
  | PPconst (ConstInt _ as c) ->
      Tconst c, Tyapp (Theory.t_int, [])
  | PPconst (ConstReal _ as c) ->
      Tconst c, Tyapp (Theory.t_real, [])
  | PPmatch _ ->
      assert false (* TODO *)
  | PPlet _ ->
      assert false (* TODO *)
  | PPnamed _ ->
      assert false (* TODO *)
  | PPexists _ | PPforall _ | PPif _ 
  | PPprefix _ | PPinfix _ | PPfalse | PPtrue ->
      error ~loc TermExpected

and dfmla env e = match e.pp_desc with
  | PPtrue ->
      Ftrue
  | PPfalse ->
      Ffalse
  | PPprefix (PPnot, a) ->
      Fnot (dfmla env a)
  | PPinfix (a, (PPand | PPor | PPimplies | PPiff as op), b) ->
      Fbinop (binop op, dfmla env a, dfmla env b)
  | PPif (a, b, c) ->
      Fif (dfmla env a, dfmla env b, dfmla env c)  
  | PPforall ({id=x}, ty, _, a) -> (* TODO: triggers *)
      let ty = dty env ty in
      let env = { env with dvars = M.add x ty env.dvars } in
      Fquant (Fforall, x, ty, dfmla env a)
  | PPexists ({id=x}, ty, a) -> (* TODO: triggers *)
      let ty = dty env ty in
      let env = { env with dvars = M.add x ty env.dvars } in
      Fquant (Fexists, x, ty, dfmla env a)
  | PPapp (x, tl) ->
      let s = find_psymbol x env.th in
      let s, tyl = specialize_psymbol s in
      let tl = dtype_args s.ps_name e.pp_loc env tyl tl in
      Fapp (s, tl)
  | PPmatch _ ->
      assert false (* TODO *)
  | PPlet _ ->
      assert false (* TODO *)
  | PPnamed _ ->
      assert false (* TODO *)
  | PPvar _ -> 
      assert false (* TODO *)
  | PPconst _ | PPprefix (PPneg, _) ->
      error ~loc:e.pp_loc PredicateExpected

and dtype_args s loc env el tl =
  let n = List.length el and m = List.length tl in
  if n <> m then error ~loc (BadNumberOfArguments (s, m, n));
  let rec check_arg = function
    | [], [] -> 
	[]
    | a :: al, t :: bl ->
	let loc = t.pp_loc in
	let t = dterm env t in
	if not (unify a t.dt_ty) then
	  error ~loc (TermExpectedType ((fun f -> print_dty f t.dt_ty),
					(fun f -> print_dty f a)));
	t :: check_arg (al, bl)
    | _ ->
	assert false
  in
  check_arg (el, tl)

let rec term env t = match t.dt_node with
  | Tvar x ->
      assert (M.mem x env);
      t_var (M.find x env)
  | Tconst c ->
      t_const c (ty t.dt_ty)
  | Tapp (s, tl) ->
      t_app s (List.map (term env) tl) (ty t.dt_ty)
  | _ ->
      assert false (* TODO *)

and fmla env = function
  | Ftrue ->
      f_true
  | Ffalse ->
      f_false 
  | Fnot f ->
      f_not (fmla env f)
  | Fbinop (op, f1, f2) ->
      f_binary op (fmla env f1) (fmla env f2)
  | Fif (f1, f2, f3) ->
      f_if (fmla env f1) (fmla env f2) (fmla env f3)
  | Fquant (q, x, t, f1) ->
      (* TODO: shouldn't we localize this ident? *)
      let v = create_vsymbol (id_fresh x) (ty t) in
      let env = M.add x v env in
      f_quant q [v] [] (fmla env f1)
  | Fapp (s, tl) ->
      f_app s (List.map (term env) tl)


(** Typing declarations, that is building environments. *)

open Ptree

let add_types loc dl th =
  let ns = get_namespace th in
  let def = 
    List.fold_left 
      (fun def d -> 
	 let id = d.td_ident in
	 if M.mem id.id def || Mnm.mem id.id ns.ns_ts then 
	   error ~loc:id.id_loc (ClashType id.id);
	 M.add id.id d def) 
      M.empty dl 
  in
  let tysymbols = Hashtbl.create 17 in
  let rec visit x = 
    try
      match Hashtbl.find tysymbols x with
	| None -> error CyclicTypeDef
	| Some ts -> ts
    with Not_found ->
      Hashtbl.add tysymbols x None;
      let d = M.find x def in
      let id = d.td_ident.id in
      let vars = Hashtbl.create 17 in
      let vl = 
	List.map 
	  (fun v -> 
	     if Hashtbl.mem vars v.id then 
	       error ~loc:v.id_loc (DuplicateTypeVar v.id);
	     let i = create_tvsymbol (id_user v.id v.id_loc) in
	     Hashtbl.add vars v.id i;
	     i)
	  d.td_params 
      in
      let id = id_user id d.td_ident.id_loc in
      let ts = match d.td_def with
	| TDalias ty -> 
	    let rec apply = function
	      | PPTtyvar v -> 
		  begin 
		    try ty_var (Hashtbl.find vars v.id)
		    with Not_found -> error ~loc:v.id_loc (UnboundTypeVar v.id)
		  end
	      | PPTtyapp (tyl, q) ->
		  let ts = match q with
		    | Qident x when M.mem x.id def ->
			visit x.id
		    | Qident _ | Qdot _ ->
			find_tysymbol q th
		  in
		  try
		    ty_app ts (List.map apply tyl)
		  with Ty.BadTypeArity ->
		    error ~loc:(qloc q) (TypeArity (q, List.length ts.ts_args,
						    List.length tyl))
	    in
	    create_tysymbol id vl (Some (apply ty))
	| TDabstract | TDalgebraic _ -> 
	    create_tysymbol id vl None
      in
      Hashtbl.add tysymbols x (Some ts);
      ts
  in
  M.iter (fun x _ -> ignore (visit x)) def;
  let decl d = 
    (match Hashtbl.find tysymbols d.td_ident.id with
       | None -> assert false
       | Some ts -> ts),
    (match d.td_def with
       | TDabstract | TDalias _ -> Tabstract
       | TDalgebraic _ -> assert false (*TODO*))
  in
  let dl = List.map decl dl in
  add_decl th (create_type dl)

let add_function loc pl t th {id=id} =
  let ns = get_namespace th in
  if Mnm.mem id ns.ns_fs then error ~loc (Clash id);
  let denv = create_denv th in
  let pl = List.map (dty denv) pl and t = dty denv t in
  let pl = List.map ty pl and t = ty t in
  (* TODO: add the theory name to the long name *)
  let v = id_user id loc in
  let s = create_fsymbol v (pl, t) false in
  add_decl th (create_logic [Lfunction (s, None)])

let add_predicate loc pl th {id=id} =
  let ns = get_namespace th in
  if Mnm.mem id ns.ns_ps then error ~loc (Clash id);
  let denv = create_denv th in
  let pl = List.map (dty denv) pl in
  let pl = List.map ty pl in
  (* TODO: add the theory name to the long name *)
  let v = id_user id loc in
  let s = create_psymbol v pl in
  add_decl th (create_logic [Lpredicate (s, None)])

let env_of_vsymbol_list vl =
  List.fold_left (fun env v -> M.add v.vs_name.id_short v env) M.empty vl

let add_logics loc dl th =
  let fsymbols = Hashtbl.create 17 in
  let psymbols = Hashtbl.create 17 in
  (* 1. create all symbols and make an environment with these symbols *)
  let create_symbol th d = 
    let id = d.ld_ident.id in
    let v = id_user id loc in
    let denv = create_denv th in
    let type_ty (_,t) = ty (dty denv t) in
    let pl = List.map type_ty d.ld_params in
    match d.ld_type with
      | None -> (* predicate *)
	  let ps = create_psymbol v pl in
	  Hashtbl.add psymbols id ps;
	  add_decl th (create_logic [Lpredicate (ps, None)])
      | Some t -> (* function *)
	  let t = type_ty (None, t) in
	  let fs = create_fsymbol v (pl, t) false in
	  Hashtbl.add fsymbols id fs;
	  add_decl th (create_logic [Lfunction (fs, None)])
  in
  let th' = List.fold_left create_symbol th dl in
  (* 2. then type-check all definitions *)
  let type_decl d = 
    let id = d.ld_ident.id in
    let dadd_var denv (x, ty) = match x with
      | None -> denv
      | Some id -> { denv with dvars = M.add id.id (dty denv ty) denv.dvars }
    in
    let denv = List.fold_left dadd_var (create_denv th') d.ld_params in
    let create_var (x, _) ty = 
      let id = match x with 
	| None -> id_fresh "%x"
	| Some id -> id_user id.id id.id_loc
      in
      create_vsymbol id ty
    in
    match d.ld_type with
    | None -> (* predicate *)
	let ps = Hashtbl.find psymbols id in
	let def = match d.ld_def with
	  | None -> 
	      None
	  | Some f -> 
	      let f = dfmla denv f in
	      let vl = List.map2 create_var d.ld_params ps.ps_scheme in
	      let env = env_of_vsymbol_list vl in
	      Some (vl, fmla env f)
	in
	Lpredicate (ps, def)
    | Some _ -> (* function *)
	let fs = Hashtbl.find fsymbols id in
	let def = match d.ld_def with
	  | None -> 
	      None
	  | Some t -> 
	      let t = dterm denv t in
	      let vl = List.map2 create_var d.ld_params (fst fs.fs_scheme) in
	      let env = env_of_vsymbol_list vl in
	      Some (vl, term env t)
	in
	Lfunction (fs, def)
  in
  let dl = List.map type_decl dl in
  add_decl th (create_logic dl)


let term env t =
  let denv = create_denv env in
  let t = dterm denv t in
  term M.empty t

let fmla env f =
  let denv = create_denv env in
  let f = dfmla denv f in
  fmla M.empty f

let add_prop k loc s f th =
  let f = fmla th f in
  try
    add_decl th (create_prop k (id_user s.id loc) f)
  with ClashSymbol _ ->
    error ~loc (Clash s.id)

let find_in_loadpath env f =
  let rec find c lp = match lp, c with
    | [], None -> 
	error ~loc:f.id_loc (NotInLoadpath f.id)
    | [], Some file ->
	file
    | dir :: lp, _ ->
	let file = Filename.concat dir f.id in
	if Sys.file_exists file then begin match c with
	  | None -> find (Some file) lp
	  | Some file' -> error ~loc:f.id_loc (AmbiguousPath (file, file'))
	end else
	  find c lp
  in
  find None env.loadpath

let locate_file env q = 
  let rec locate_dir = function
    | Qident d ->
	find_in_loadpath env d
    | Qdot (q, d) -> 
	let dir = locate_dir q in
	let dir = Filename.concat dir d.id in
	if not (Sys.file_exists dir) then error ~loc:d.id_loc (UnboundDir dir);
	dir
  in
  match q with
    | Qident f -> 
	find_in_loadpath env { f with id = f.id ^ ".why" }
    | Qdot (p, f) -> 
	let dir = locate_dir p in 
	let file = Filename.concat dir f.id ^ ".why" in
	if not (Sys.file_exists file) then 
	  error ~loc:(qloc q) (UnboundFile file);
	file

let loaded_theories = Hashtbl.create 17 (* file -> string -> Theory.t *)

(* parse file and store all theories into parsed_theories *)
let load_file file =
  let c = open_in file in
  let lb = Lexing.from_channel c in
  Loc.set_file file lb;
  let tl = Lexer.parse_logic_file lb in 
  close_in c;
  tl

let prop_kind = function
  | Kaxiom -> Paxiom
  | Kgoal -> Pgoal
  | Klemma -> Plemma

let rec find_theory env q = match q with
  | Qident id -> 
      (* local theory *)
      begin 
	try M.find id.id env.theories 
	with Not_found -> error ~loc:id.id_loc (UnboundTheory id.id) 
      end
  | Qdot (f, id) ->
      (* theory in file f *)
      let file = locate_file env f in
      if not (Hashtbl.mem loaded_theories file) then begin
	let tl = load_file file in
	let h = Hashtbl.create 17 in
	Hashtbl.add loaded_theories file h;
	let env = { env with theories = M.empty } in
	let add env pt =
	  let t, env = add_theory env pt in
	  Hashtbl.add h t.th_name.id_short t;
	  env
	in
	ignore (List.fold_left add env tl);
      end;
      let h = Hashtbl.find loaded_theories file in
      try Hashtbl.find h id.id
      with Not_found -> error ~loc:id.id_loc (UnboundTheory id.id)

and type_theory env id pt =
  (* TODO: use long name *)
  let n = id_user id.id id.id_loc in
  let th = create_theory n in
  let th = add_decls env th pt.pt_decl in
  close_theory th

and add_decls env th = List.fold_left (add_decl env) th

and add_decl env th = function
  | TypeDecl (loc, dl) ->
      add_types loc dl th
  | Logic (loc, dl) ->
      add_logics loc dl th
  | Prop (loc, k, s, f) ->
      add_prop (prop_kind k) loc s f th
  | Use (loc, use) ->
      let t = find_theory env use.use_theory in
      let n = match use.use_as with 
	| None -> t.th_name.id_short
	| Some x -> x.id
      in
      begin try match use.use_imp_exp with
	| Nothing ->
	    (* use T = namespace T use_export T end *)
	    let th = open_namespace th in
	    let th = use_export th t in
	    close_namespace th n ~import:false
	| Import ->
	    (* use import T = namespace T use_export T end import T *)
	    let th = open_namespace th in
	    let th = use_export th t in
	    close_namespace th n ~import:true
	| Export ->
	    use_export th t
      with Theory.ClashSymbol s ->
	error ~loc (Clash s)
      end
  | Namespace (_, {id=id; id_loc=loc}, dl) ->
      let ns = get_namespace th in
      if Mnm.mem id ns.ns_ns then error ~loc (ClashNamespace id);
      let th = open_namespace th in
      let th = add_decls env th dl in
      close_namespace th id ~import:false
  | Inductive_def _ ->
      assert false (*TODO*)

and add_theory env pt =
  let id = pt.pt_name in
  if M.mem id.id env.theories then error ~loc:pt.pt_loc (ClashTheory id.id);
  let t = type_theory env id pt in
  t, { env with theories = M.add id.id t env.theories }

let add_theories =
  List.fold_left
    (fun env pt -> let _, env = add_theory env pt in env) 

let list_theory env = 
  M.fold (fun _ v acc -> v::acc) env.theories []

(*
Local Variables: 
compile-command: "make -C ../.. test"
End: 
*)
