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
open TheoryUC

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
  | BadNumberOfArguments of Ident.ident * int * int 
  | ClashTheory of string
  | ClashNamespace of string
  | UnboundTheory of qualid
  | AlreadyTheory of string
  | UnboundNamespace of string
  | UnboundFile of string
  | UnboundDir of string
  | AmbiguousPath of string * string
  | NotInLoadpath of string
  | CyclicTypeDef
  | UnboundTypeVar of string
  | AnyMessage of string

exception Error of error

let error ?loc e = match loc with
  | None -> raise (Error e)
  | Some loc -> raise (Loc.Located (loc, Error e))

let errorm ?loc f =
  let buf = Buffer.create 512 in
  let fmt = Format.formatter_of_buffer buf in
  Format.kfprintf 
    (fun _ -> 
       Format.pp_print_flush fmt ();
       let s = Buffer.contents buf in
       Buffer.clear buf;
       error ?loc (AnyMessage s))
    fmt f

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
  | ClashTheory s ->
      fprintf fmt "clash with previous theory %s" s
  | ClashNamespace s ->
      fprintf fmt "clash with previous namespace %s" s
  | UnboundTheory q ->
      fprintf fmt "unbound theory %a" print_qualid q
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
  | AnyMessage s ->
      fprintf fmt "%s" s

(** Environments *)

module S = Set.Make(String)
module M = Map.Make(String)

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
  type_var_loc : loc option;
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

let term_expected_type ~loc ty1 ty2 =
  errorm ~loc
    "@[This term has type %a@ but is expected to have type@ %a@]"
    print_dty ty1 print_dty ty2

let create_ty_decl_var =
  let t = ref 0 in
  fun ?loc ~user tv -> 
    incr t; 
    { tag = !t; user = user; tvsymbol = tv; type_val = None;
      type_var_loc = loc }

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
    let v = create_ty_decl_var ~user:true v in
    Hashtbl.add env.utyvars x v;
    v
 
(* Specialize *)

module Htv = Hid

let find_type_var ~loc env tv =
  try
    Htv.find env tv
  with Not_found ->
    let v = create_ty_decl_var ~loc ~user:false tv in
    Htv.add env tv v;
    v
 
let rec specialize ~loc env t = match t.ty_node with
  | Ty.Tyvar tv -> 
      Tyvar (find_type_var ~loc env tv)
  | Ty.Tyapp (s, tl) ->
      Tyapp (s, List.map (specialize ~loc env) tl)

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

let find_local_tysymbol {id=x; id_loc=loc} ns = 
  try Mnm.find x ns.ns_ts
  with Not_found -> error ~loc (UnboundType x)

let find_tysymbol_ns p ns =
  find find_local_tysymbol p ns

let find_tysymbol p th = 
  find_tysymbol_ns p (get_namespace th)

let specialize_tysymbol ~loc x env =
  let s = find_tysymbol x env.th in
  let env = Htv.create 17 in
  s, List.map (find_type_var ~loc env) s.ts_args
	
let find_lsymbol {id=x; id_loc=loc} ns = 
  try Mnm.find x ns.ns_ls
  with Not_found -> error ~loc (UnboundSymbol x)

let find_lsymbol_ns p ns = 
  find find_lsymbol p ns

let find_lsymbol p th = 
  find_lsymbol_ns p (get_namespace th)

let find_prop {id=x; id_loc=loc} ns = 
  try Mnm.find x ns.ns_pr
  with Not_found -> errorm ~loc "unbound formula %s" x

let find_prop_ns p ns =
  find find_prop p ns

let find_prop p th =
  find_prop_ns p (get_namespace th)

let specialize_lsymbol ~loc s =
  let tl = s.ls_args in
  let t = s.ls_value in
  let env = Htv.create 17 in
  s, List.map (specialize ~loc env) tl, option_map (specialize ~loc env) t

let specialize_fsymbol ~loc s = 
  let s, tl, ty = specialize_lsymbol ~loc s in
  match ty with
    | None -> error ~loc TermExpected
    | Some ty -> s, tl, ty

let specialize_psymbol ~loc s = 
  let s, tl, ty = specialize_lsymbol ~loc s in
  match ty with
    | None -> s, tl
    | Some _ -> error ~loc PredicateExpected

(** Typing types *)

let rec qloc = function
  | Qident x -> x.id_loc
  | Qdot (m, x) -> Loc.join (qloc m) x.id_loc

let rec string_list_of_qualid acc = function
  | Qident id -> id.id :: acc
  | Qdot (p, id) -> string_list_of_qualid (id.id :: acc) p

let split_qualid = function
  | Qident id -> [], id.id
  | Qdot (p, id) -> string_list_of_qualid [] p, id.id

(* parsed types -> intermediate types *)

let rec type_inst s ty = match ty.ty_node with
  | Ty.Tyvar n -> Mid.find n s
  | Ty.Tyapp (ts, tyl) -> Tyapp (ts, List.map (type_inst s) tyl)

let rec dty env = function
  | PPTtyvar {id=x} -> 
      Tyvar (find_user_type_var x env)
  | PPTtyapp (p, x) ->
      let loc = qloc x in
      let ts, tv = specialize_tysymbol ~loc x env in
      let np = List.length p in
      let a = List.length tv in
      if np <> a then error ~loc (TypeArity (x, a, np));
      let tyl = List.map (dty env) p in
      match ts.ts_def with
	| None -> 
	    Tyapp (ts, tyl)
	| Some ty -> 
	    let add m v t = Mid.add v t m in
            let s = List.fold_left2 add Mid.empty ts.ts_args tyl in
	    type_inst s ty

(* intermediate types -> types *)
let rec ty_of_dty = function
  | Tyvar { type_val = Some t } ->
      ty_of_dty t
  | Tyvar { type_val = None; user = false; type_var_loc = loc } ->
      errorm ?loc "undefined type variable"
  | Tyvar { tvsymbol = tv } ->
      Ty.ty_var tv
  | Tyapp (s, tl) ->
      Ty.ty_app s (List.map ty_of_dty tl)

(** Typing terms and formulas *)

type dpattern = { dp_node : dpattern_node; dp_ty : dty }

and dpattern_node =
  | Pwild
  | Pvar of string
  | Papp of lsymbol * dpattern list
  | Pas of dpattern * string

type uquant = string list * dty

type dterm = { dt_node : dterm_node; dt_ty : dty }

and dterm_node =
  | Tvar of string
  | Tconst of constant
  | Tapp of lsymbol * dterm list
  | Tlet of dterm * string * dterm
  | Tmatch of dterm * (dpattern * dterm) list
  | Tnamed of string * dterm
  | Teps of string * dfmla

and dfmla = 
  | Fapp of lsymbol * dterm list
  | Fquant of quant * uquant list * dtrigger list list * dfmla
  | Fbinop of binop * dfmla * dfmla
  | Fnot of dfmla
  | Ftrue
  | Ffalse
  | Fif of dfmla * dfmla * dfmla
  | Flet of dterm * string * dfmla
  | Fmatch of dterm * (dpattern * dfmla) list
  | Fnamed of string * dfmla
  | Fvar of fmla

and dtrigger =
  | TRterm of dterm
  | TRfmla of dfmla

let binop = function
  | PPand -> Fand
  | PPor -> For
  | PPimplies -> Fimplies
  | PPiff -> Fiff

let check_pat_linearity pat =
  let s = ref S.empty in
  let add id =
    if S.mem id.id !s then errorm ~loc:id.id_loc "duplicate variable %s" id.id;
    s := S.add id.id !s
  in
  let rec check p = match p.pat_desc with
    | PPpwild -> ()
    | PPpvar id -> add id
    | PPpapp (_, pl) -> List.iter check pl
    | PPpas (p, id) -> check p; add id
  in
  check pat

let rec dpat env pat =
  let env, n, ty = dpat_node pat.pat_loc env pat.pat_desc in
  env, { dp_node = n; dp_ty = ty }

and dpat_node loc env = function
  | PPpwild -> 
      let tv = create_tvsymbol (id_user "a" loc) in
      let ty = Tyvar (create_ty_decl_var ~loc ~user:false tv) in
      env, Pwild, ty
  | PPpvar {id=x} ->
      let tv = create_tvsymbol (id_user "a" loc) in
      let ty = Tyvar (create_ty_decl_var ~loc ~user:false tv) in
      let env = { env with dvars = M.add x ty env.dvars } in
      env, Pvar x, ty
  | PPpapp (x, pl) ->
      let s = find_lsymbol x env.th in
      let s, tyl, ty = specialize_fsymbol ~loc s in
      let env, pl = dpat_args s.ls_name loc env tyl pl in
      env, Papp (s, pl), ty
  | PPpas (p, {id=x}) ->
      let env, p = dpat env p in
      let env = { env with dvars = M.add x p.dp_ty env.dvars } in
      env, Pas (p,x), p.dp_ty

and dpat_args s loc env el pl = 
  let n = List.length el and m = List.length pl in
  if n <> m then error ~loc (BadNumberOfArguments (s, m, n));
  let rec check_arg env = function
    | [], [] -> 
	env, []
    | a :: al, p :: pl ->
	let loc = p.pat_loc in
	let env, p = dpat env p in
	if not (unify a p.dp_ty) then term_expected_type ~loc p.dp_ty a;
	let env, pl = check_arg env (al, pl) in
	env, p :: pl
    | _ ->
	assert false
  in
  check_arg env (el, pl)

let rec trigger_not_a_term_exn = function
  | Error TermExpected -> true
  | Loc.Located (_, exn) -> trigger_not_a_term_exn exn
  | _ -> false

let check_quant_linearity uqu =
  let s = ref S.empty in
  let check id = 
    if S.mem id.id !s then errorm ~loc:id.id_loc "duplicate variable %s" id.id;
    s := S.add id.id !s
  in
  List.iter (fun (idl, _) -> List.iter check idl) uqu

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
      let s = find_lsymbol x env.th in
      let s, tyl, ty = specialize_fsymbol ~loc s in
      let n = List.length tyl in
      if n > 0 then error ~loc (BadNumberOfArguments (s.ls_name, 0, n));
      Tapp (s, []), ty
  | PPapp (x, tl) ->
      let s = find_lsymbol x env.th in
      let s, tyl, ty = specialize_fsymbol ~loc s in
      let tl = dtype_args s.ls_name loc env tyl tl in
      Tapp (s, tl), ty
  | PPconst (ConstInt _ as c) ->
      Tconst c, Tyapp (Ty.ts_int, [])
  | PPconst (ConstReal _ as c) ->
      Tconst c, Tyapp (Ty.ts_real, [])
  | PPlet ({id=x}, e1, e2) ->
      let e1 = dterm env e1 in
      let ty = e1.dt_ty in
      let env = { env with dvars = M.add x ty env.dvars } in
      let e2 = dterm env e2 in
      Tlet (e1, x, e2), e2.dt_ty
  | PPmatch (e1, bl) ->
      let e1 = dterm env e1 in
      let ty = e1.dt_ty in
      let tb = (* the type of all branches *)
	let tv = create_tvsymbol (id_user "a" loc) in
	Tyvar (create_ty_decl_var ~loc ~user:false tv) 
      in
      let branch (pat, e) =
	let loc = pat.pat_loc in
	check_pat_linearity pat;
        let env, pat = dpat env pat in
	if not (unify pat.dp_ty ty) then term_expected_type ~loc pat.dp_ty ty;
	let loc = e.pp_loc in
	let e = dterm env e in
	if not (unify e.dt_ty tb) then term_expected_type ~loc e.dt_ty tb;
        pat, e
      in
      let bl = List.map branch bl in
      let ty = (snd (List.hd bl)).dt_ty in
      Tmatch (e1, bl), ty
  | PPnamed (x, e1) ->
      let e1 = dterm env e1 in
      Tnamed (x, e1), e1.dt_ty
  | PPcast (e1, ty) ->
      let loc = e1.pp_loc in
      let e1 = dterm env e1 in
      let ty = dty env ty in
      if not (unify e1.dt_ty ty) then term_expected_type ~loc e1.dt_ty ty;
      e1.dt_node, ty
  | PPquant _ | PPif _ 
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
  | PPquant (q, uqu, trl, a) ->
      check_quant_linearity uqu;
      let uquant env (idl,ty) =
        let ty = dty env ty in
        let env, idl = 
          map_fold_left
            (fun env {id=x} -> { env with dvars = M.add x ty env.dvars }, x)
            env idl
        in
        env, (idl,ty)
      in
      let env, uqu = map_fold_left uquant env uqu in
      let trigger e =
	try 
	  TRterm (dterm env e) 
	with exn when trigger_not_a_term_exn exn ->
	  TRfmla (dfmla env e) 
      in
      let trl = List.map (List.map trigger) trl in
      let q = match q with 
        | PPforall -> Fforall 
        | PPexists -> Fexists
      in
      Fquant (q, uqu, trl, dfmla env a)
  | PPapp (x, tl) ->
      let s = find_lsymbol x env.th in
      let s, tyl = specialize_psymbol ~loc:e.pp_loc s in
      let tl = dtype_args s.ls_name e.pp_loc env tyl tl in
      Fapp (s, tl)
  | PPlet ({id=x}, e1, e2) ->
      let e1 = dterm env e1 in
      let ty = e1.dt_ty in
      let env = { env with dvars = M.add x ty env.dvars } in
      let e2 = dfmla env e2 in
      Flet (e1, x, e2)
  | PPmatch (e1, bl) ->
      let e1 = dterm env e1 in
      let ty = e1.dt_ty in
      let branch (pat, e) =
	let loc = pat.pat_loc in
	check_pat_linearity pat;
        let env, pat = dpat env pat in
	if not (unify pat.dp_ty ty) then term_expected_type ~loc pat.dp_ty ty;
        pat, dfmla env e
      in
      Fmatch (e1, List.map branch bl)
  | PPnamed (x, f1) ->
      let f1 = dfmla env f1 in
      Fnamed (x, f1)
  | PPvar x -> 
      Fvar (find_prop x env.th).pr_fmla 
  | PPconst _ | PPcast _ ->
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
	if not (unify a t.dt_ty) then term_expected_type ~loc t.dt_ty a;
	t :: check_arg (al, bl)
    | _ ->
	assert false
  in
  check_arg (el, tl)

let rec pattern env p = 
  let ty = ty_of_dty p.dp_ty in
  match p.dp_node with
  | Pwild -> env, pat_wild ty
  | Pvar x -> 
      if M.mem x env then assert false; (* FIXME? *)
      let v = create_vsymbol (id_fresh x) ty in
      M.add x v env, pat_var v
  | Papp (s, pl) -> 
      let env, pl = map_fold_left pattern env pl in
      env, pat_app s pl ty
  | Pas (p, x) ->
      if M.mem x env then assert false; (* FIXME? *)
      let v = create_vsymbol (id_fresh x) ty in
      let env, p = pattern (M.add x v env) p in
      env, pat_as p v

let rec term env t = match t.dt_node with
  | Tvar x ->
      assert (M.mem x env);
      t_var (M.find x env)
  | Tconst c ->
      t_const c (ty_of_dty t.dt_ty)
  | Tapp (s, tl) ->
      t_app s (List.map (term env) tl) (ty_of_dty t.dt_ty)
  | Tlet (e1, x, e2) ->
      let ty = ty_of_dty e1.dt_ty in
      let e1 = term env e1 in 
      let v = create_vsymbol (id_fresh x) ty in
      let env = M.add x v env in
      let e2 = term env e2 in
      t_let v e1 e2
  | Tmatch (e1, bl) ->
      let branch (pat,e) =
        let env, pat = pattern env pat in
        (pat, term env e)
      in
      let bl = List.map branch bl in
      let ty = (snd (List.hd bl)).t_ty in
      t_case (term env e1) bl ty
  | Tnamed (x, e1) ->
      let e1 = term env e1 in
      t_label_add x e1
  | Teps _ ->
      assert false (*TODO*)

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
  | Fquant (q, uqu, trl, f1) ->
      (* TODO: shouldn't we localize this ident? *)
      let uquant env (xl,ty) =
        let ty = ty_of_dty ty in
        map_fold_left
          (fun env x -> 
             let v = create_vsymbol (id_fresh x) ty in M.add x v env, v) 
          env xl 
      in
      let env, vl = map_fold_left uquant env uqu in
      let trigger = function
	| TRterm t -> TrTerm (term env t) 
	| TRfmla f -> TrFmla (fmla env f) 
      in
      let trl = List.map (List.map trigger) trl in
      f_quant q (List.concat vl) trl (fmla env f1)
  | Fapp (s, tl) ->
      f_app s (List.map (term env) tl)
  | Flet (e1, x, f2) ->
      let ty = ty_of_dty e1.dt_ty in
      let e1 = term env e1 in 
      let v = create_vsymbol (id_fresh x) ty in
      let env = M.add x v env in
      let f2 = fmla env f2 in
      f_let v e1 f2
  | Fmatch (e1, bl) ->
      let branch (pat,e) =
        let env, pat = pattern env pat in
        (pat, fmla env e)
      in
      f_case (term env e1) (List.map branch bl)
  | Fnamed (x, f1) ->
      let f1 = fmla env f1 in
      f_label_add x f1
  | Fvar f ->
      f

(** Typing declarations, that is building environments. *)

open Ptree

let add_types dl th =
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
  let th' = 
    let tsl = 
      M.fold (fun x _ tsl -> let ts = visit x in (ts, Tabstract) :: tsl) def []
    in
    add_decl th (create_ty_decl tsl)
  in
  let decl d = 
    let ts, th' = match Hashtbl.find tysymbols d.td_ident.id with
      | None -> 
	  assert false
      | Some ts -> 
	  let th' = create_denv th' in
	  let vars = th'.utyvars in
	  List.iter 
	    (fun v -> 
	       Hashtbl.add vars v.id_short (create_ty_decl_var ~user:true v)) 
	    ts.ts_args;
	  ts, th'
    in
    let d = match d.td_def with
      | TDabstract | TDalias _ -> 
	  Tabstract
      | TDalgebraic cl -> 
	  let ty = ty_app ts (List.map ty_var ts.ts_args) in
	  let constructor (loc, id, pl) = 
	    let param (_, t) = ty_of_dty (dty th' t) in
	    let tyl = List.map param pl in
	    create_fconstr (id_user id.id id.id_loc) tyl ty
	  in
	  Talgebraic (List.map constructor cl)
    in
    ts, d
  in
  let dl = List.map decl dl in
  List.fold_left add_decl th (create_ty_decls dl)

let env_of_vsymbol_list vl =
  List.fold_left (fun env v -> M.add v.vs_name.id_short v env) M.empty vl

let add_logics dl th =
  let ns = get_namespace th in
  let fsymbols = Hashtbl.create 17 in
  let psymbols = Hashtbl.create 17 in
  let denvs = Hashtbl.create 17 in
  (* 1. create all symbols and make an environment with these symbols *)
  let create_symbol th d = 
    let id = d.ld_ident.id in
    if Hashtbl.mem denvs id || Mnm.mem id ns.ns_ls 
      then error ~loc:d.ld_loc (Clash id);
    let v = id_user id d.ld_ident.id_loc in
    let denv = create_denv th in
    Hashtbl.add denvs id denv;
    let type_ty (_,t) = ty_of_dty (dty denv t) in
    let pl = List.map type_ty d.ld_params in
    match d.ld_type with
      | None -> (* predicate *)
	  let ps = create_psymbol v pl in
	  Hashtbl.add psymbols id ps;
	  add_decl th (create_logic_decl [Lpredicate (ps, None)])
      | Some t -> (* function *)
	  let t = type_ty (None, t) in
	  let fs = create_fsymbol v pl t in
	  Hashtbl.add fsymbols id fs;
	  add_decl th (create_logic_decl [Lfunction (fs, None)])
  in
  let th' = List.fold_left create_symbol th dl in
  (* 2. then type-check all definitions *)
  let type_decl d = 
    let id = d.ld_ident.id in
    let dadd_var denv (x, ty) = match x with
      | None -> denv
      | Some id -> { denv with dvars = M.add id.id (dty denv ty) denv.dvars }
    in
    let denv = Hashtbl.find denvs id in
    let denv = { denv with th = th' } in
    let denv = List.fold_left dadd_var denv d.ld_params in
    let create_var (x, _) ty = 
      let id = match x with 
	| None -> id_fresh "%x"
	| Some id -> id_user id.id id.id_loc
      in
      create_vsymbol id ty
    in
    let mk_vlist = List.map2 create_var d.ld_params in
    match d.ld_type with
    | None -> (* predicate *)
	let ps = Hashtbl.find psymbols id in
        let defn = match d.ld_def with
	  | None -> None
	  | Some f -> 
	      let f = dfmla denv f in
              let vl = match ps.ls_value with
                | None -> mk_vlist ps.ls_args
                | _ -> assert false
              in
	      let env = env_of_vsymbol_list vl in
              Some (make_ps_defn ps vl (fmla env f))
        in
        Lpredicate (ps, defn)
    | Some ty -> (* function *)
	let fs = Hashtbl.find fsymbols id in
        let defn = match d.ld_def with
	  | None -> None
	  | Some t -> 
	      let loc = t.pp_loc in
	      let t = dterm denv t in
              let vl = match fs.ls_value with
                | Some _ -> mk_vlist fs.ls_args
                | _ -> assert false
              in
	      let env = env_of_vsymbol_list vl in
              try Some (make_fs_defn fs vl (term env t))
	      with _ -> term_expected_type ~loc t.dt_ty (dty denv ty)
        in
        Lfunction (fs, defn)
  in
  let dl = List.map type_decl dl in
  List.fold_left add_decl th (create_logic_decls dl)


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
    add_decl th (create_prop_decl k (create_prop (id_user s.id loc) f))
  with ClashSymbol _ ->
    error ~loc (Clash s.id)

(** [check_clausal_form loc ps f] checks whether the formula [f] 
    has a valid clausal form 
      \forall x_1,.., x_k. P1 -> ... -> P_n -> P
    where P is headed by ps and ps has only positive occurrences in P1 .. Pn *)

let rec occurrences ps f = match f.f_node with
  | Term.Ftrue | Term.Ffalse -> 
      0, 0
  | Term.Fapp (ps', _) -> 
      (if ps'.ls_name == ps.ls_name then 1 else 0), 0
  | Term.Fbinop (Fimplies, f1, f2) -> 
      let pos1, neg1 = occurrences ps f1 in
      let pos2, neg2 = occurrences ps f2 in
      neg1+pos2, pos1+neg2
  | Term.Fbinop ((Fand | For), f1, f2) -> 
      let pos1, neg1 = occurrences ps f1 in
      let pos2, neg2 = occurrences ps f2 in
      pos1+pos2, neg1+neg2
  | Term.Fbinop (Fiff, f1, f2) -> 
      let pos1, neg1 = occurrences ps f1 in
      let pos2, neg2 = occurrences ps f2 in
      let n = pos1+pos2+neg1+neg2 in
      n, n
  | Term.Fnot p1 -> 
      let pos1, neg1 = occurrences ps p1 in neg1, pos1
  | Term.Fquant (_, qf) ->
      assert false (* TODO *)
      (* occurrences pi p *)
  | Term.Flet (t, bf) ->
      let _, f = f_open_bound bf in
      occurrences ps f
  | Term.Fif (f1, f2, f3) ->
      let pos1, neg1 = occurrences ps f1 in
      let pos2, neg2 = occurrences ps f2 in
      let pos3, neg3 = occurrences ps f3 in
      pos1+pos2+pos3, neg1+neg2+neg3
  | Term.Fcase (_, bl) ->
      List.fold_left
	(fun (pos, neg) br ->
	   let _, _, f1 = f_open_branch br in
	   let pos1, neg1 = occurrences ps f1 in
	   pos+pos1, neg+neg1)
	(0, 0) bl
      
let rec check_unquantified_clausal_form loc ps f = match f.f_node with
  | Term.Fbinop (Fimplies, f1, f2) -> 
      check_unquantified_clausal_form loc ps f2;
      let _, neg1 = occurrences ps f1 in
      if neg1 > 0 then 
	errorm ~loc 
	  "inductive predicate has a negative occurrence in this case"
  | Term.Fapp (ps', _) -> 
      (* TODO: v�rifier �galement que les arguments de ps' ont exactement
	 les m�mes types que ceux de la d�claration de ps (et non plus 
	 pr�cis) *)
      if ps'.ls_name != ps.ls_name then
	errorm ~loc "head of clause does not contain the inductive predicate"
  | _ -> 
      errorm ~loc "this case is not in clausal form"

let rec check_clausal_form loc ps f = match f.f_node with
  | Term.Fquant (Fforall, qf) ->
      let vl, _, f = f_open_quant qf in
      check_clausal_form loc ps f
  | _ -> 
      check_unquantified_clausal_form loc ps f

let add_inductives dl th =
  let ns = get_namespace th in
  let psymbols = Hashtbl.create 17 in
  (* 1. create all symbols and make an environment with these symbols *)
  let create_symbol th d = 
    let id = d.in_ident.id in
    if Hashtbl.mem psymbols id || Mnm.mem id ns.ns_ls 
      then error ~loc:d.in_loc (Clash id);
    let v = id_user id d.in_ident.id_loc in
    let denv = create_denv th in
    let type_ty t = ty_of_dty (dty denv t) in
    let pl = List.map type_ty d.in_params in
    let ps = create_psymbol v pl in
    Hashtbl.add psymbols id ps;
    add_decl th (create_logic_decl [Lpredicate (ps, None)])
  in
  let th' = List.fold_left create_symbol th dl in
  (* 2. then type-check all definitions *)
  let type_decl d = 
    let id = d.in_ident.id in
    let ps = Hashtbl.find psymbols id in
    let clause (id, f) = 
      let loc = f.pp_loc in
      let f' = fmla th' f in
      check_clausal_form loc ps f';
      create_prop (id_user id.id id.id_loc) f'
    in
    ps, List.map clause d.in_def
  in
  let dl = List.map type_decl dl in
  List.fold_left add_decl th (create_ind_decls dl)

(* parse file and store all theories into parsed_theories *)

let load_channel file c =
  let lb = Lexing.from_channel c in
  Loc.set_file file lb;
  Lexer.parse_logic_file lb

let load_file file =
  let c = open_in file in
  let tl = load_channel file c in
  close_in c;
  tl

let prop_kind = function
  | Kaxiom -> Paxiom
  | Kgoal -> Pgoal
  | Klemma -> Plemma

let find_theory env lenv q id = match q with
  | [] -> 
      (* local theory *)
      begin try Mnm.find id lenv 
      with Not_found -> Theory.find_theory env [] id end
  | _ :: _ ->
      (* theory in file f *)
      Theory.find_theory env q id

let rec type_theory env lenv id pt =
  let n = id_user id.id id.id_loc in
  let th = create_theory env n in
  let th = add_decls env lenv th pt.pt_decl in
  close_theory th

and add_decls env lenv th = List.fold_left (add_decl env lenv) th

and add_decl env lenv th = function
  | TypeDecl dl ->
      add_types dl th
  | LogicDecl dl ->
      add_logics dl th
  | IndDecl dl ->
      add_inductives dl th
  | PropDecl (loc, k, s, f) ->
      add_prop (prop_kind k) loc s f th
  | UseClone (loc, use, subst) ->
      let q, id = split_qualid use.use_theory in
      let t = 
	try
	  find_theory env lenv q id
	with 
	  | TheoryNotFound _ -> error ~loc (UnboundTheory use.use_theory)
	  | Error (AmbiguousPath _ as e) -> error ~loc e
      in
      let use_or_clone th = match subst with
	| None -> 
	    use_export th t
	| Some s -> 
            let add_inst s = function
              | CStsym (p,q) ->
                  let ts1 = find_tysymbol_ns p t.th_export in
                  let ts2 = find_tysymbol q th in
                  if Mts.mem ts1 s.inst_ts
                  then error ~loc (Clash ts1.ts_name.id_short);
                  { s with inst_ts = Mts.add ts1 ts2 s.inst_ts }
              | CSlsym (p,q) ->
                  let ls1 = find_lsymbol_ns p t.th_export in
                  let ls2 = find_lsymbol q th in
                  if Mls.mem ls1 s.inst_ls
                  then error ~loc (Clash ls1.ls_name.id_short);
                  { s with inst_ls = Mls.add ls1 ls2 s.inst_ls }
              | CSlemma p ->
                  let pr = find_prop_ns p t.th_export in
                  if Spr.mem pr s.inst_lemma || Spr.mem pr s.inst_goal
                  then error ~loc (Clash pr.pr_name.id_short);
                  { s with inst_lemma = Spr.add pr s.inst_lemma }
              | CSgoal p ->
                  let pr = find_prop_ns p t.th_export in
                  if Spr.mem pr s.inst_lemma || Spr.mem pr s.inst_goal
                  then error ~loc (Clash pr.pr_name.id_short);
                  { s with inst_goal = Spr.add pr s.inst_goal }
	    in
            let s = List.fold_left add_inst empty_inst s in
	    clone_export th t s
      in
      let n = match use.use_as with 
	| None -> Some t.th_name.id_short
	| Some (Some x) -> Some x.id
	| Some None -> None
      in
      begin try match use.use_imp_exp with
	| Nothing ->
	    (* use T = namespace T use_export T end *)
	    let th = open_namespace th in
	    let th = use_or_clone th in
	    close_namespace th false n
	| Import ->
	    (* use import T = namespace T use_export T end import T *)
	    let th = open_namespace th in
	    let th = use_or_clone th in
	    close_namespace th true n
	| Export ->
	    use_or_clone th 
      with ClashSymbol s ->
	error ~loc (Clash s)
      end
  | Namespace (_, import, name, dl) ->
      let ns = get_namespace th in
      let id = match name with
        | Some { id=id; id_loc=loc } ->
            if Mnm.mem id ns.ns_ns then error ~loc (ClashNamespace id);
            Some id
        | None ->
            None
      in
      let th = open_namespace th in
      let th = add_decls env lenv th dl in
      close_namespace th import id

and type_and_add_theory env lenv pt =
  let id = pt.pt_name in
  if Mnm.mem id.id lenv || id.id = builtin_name then error (ClashTheory id.id);
  let th = type_theory env lenv id pt in
  Mnm.add id.id th lenv
   
let type_theories env tl =
  List.fold_left (type_and_add_theory env) Mnm.empty tl

let read_file env file =
  let tl = load_file file in
  type_theories env tl

let read_channel env file ic =
  let tl = load_channel file ic in
  type_theories env tl

let locate_file lp sl =
  let f = List.fold_left Filename.concat "" sl ^ ".why" in
  let fl = List.map (fun dir -> Filename.concat  dir f) lp in
  match List.filter Sys.file_exists fl with
    | [] -> raise Not_found
    | [file] -> file
    | file1 :: file2 :: _ -> error (AmbiguousPath (file1, file2))

let retrieve lp env sl =
  let file = locate_file lp sl in
  read_file env file

(*
Local Variables: 
compile-command: "make -C ../.. test"
End: 
*)
