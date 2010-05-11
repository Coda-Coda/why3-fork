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

open Format
open Why
open Util
open Ident
open Ty
open Term
open Theory
open Denv
open Ptree
open Pgm_ttree

type error =
  | Message of string

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
       error ?loc (Message s))
    fmt f

let report fmt = function
  | Message s ->
      fprintf fmt "%s" s

let id_result = "result"

(* parsing LOGIC strings using functions from src/parser/
   requires proper relocation *)

let reloc loc lb =
  lb.Lexing.lex_curr_p <- loc;
  lb.Lexing.lex_abs_pos <- loc.Lexing.pos_cnum
    
let parse_string f loc s =
  let lb = Lexing.from_string s in
  reloc loc lb;
  f lb
    
let logic_list0_decl (loc, s) = parse_string Lexer.parse_list0_decl loc s
  
let lexpr (loc, s) = parse_string Lexer.parse_lexpr loc s

(* environments *)

let ts_unit uc = ns_find_ts (get_namespace uc) ["unit"]
let ts_ref uc = ns_find_ts (get_namespace uc) ["ref"]
let ts_arrow uc = ns_find_ts (get_namespace uc) ["arrow"]
let ts_exn uc = ns_find_ts (get_namespace uc) ["exn"]

let ls_Unit uc = ns_find_ls (get_namespace uc) ["Unit"]

let dty_bool uc = Tyapp (ns_find_ts (get_namespace uc) ["bool"], [])
let dty_unit uc = Tyapp (ts_unit uc, [])
let dty_label uc = Tyapp (ns_find_ts (get_namespace uc) ["label"], [])

type denv = {
  uc   : theory_uc;
  denv : Typing.denv;
}

let create_denv uc = 
  { uc   = uc;
    denv = Typing.create_denv uc;
  }

let create_type_var loc =
  let tv = Ty.create_tvsymbol (id_user "a" loc) in
  Tyvar (create_ty_decl_var ~loc ~user:false tv)

let dcurrying uc tyl ty =
  let make_arrow_type ty1 ty2 = Tyapp (ts_arrow uc, [ty1; ty2]) in
  List.fold_right make_arrow_type tyl ty

let uncurrying uc ty =
  let rec uncurry acc ty = match ty.ty_node with
    | Ty.Tyapp (ts, [t1; t2]) when ts == ts_arrow uc -> uncurry (t1 :: acc) t2
    | _ -> List.rev acc, ty
  in
  uncurry [] ty

let expected_type e ty =
  if not (Denv.unify e.dexpr_type ty) then
    errorm ~loc:e.dexpr_loc 
      "this expression has type %a, but is expected to have type %a"
      print_dty e.dexpr_type print_dty ty

(* phase 1: typing programs (using destructive type inference) *)

let pure_type env = Typing.dty env.denv

let rec dpurify env = function
  | DTpure ty -> 
      ty
  | DTarrow (bl, c) -> 
      dcurrying env.uc (List.map (fun (_,ty) -> dpurify env ty) bl)
	(dpurify env c.dc_result_type)

let check_reference_type uc loc ty =
  let ty_ref =Tyapp (ts_ref uc, [create_type_var loc]) in
  if not (Denv.unify ty ty_ref) then
    errorm ~loc "this expression has type %a, but is expected to be a reference"
      print_dty ty
  
let dreference env id =
  if Typing.mem_var id.id env.denv then
    (* local variable *)
    let ty = Typing.find_var id.id env.denv in
    check_reference_type env.uc id.id_loc ty;
    DRlocal id.id
  else 
    let p = Qident id in
    let s, _, ty = Typing.specialize_fsymbol p env.uc in
    check_reference_type env.uc id.id_loc ty;
    DRglobal s

let dexception env id =
  let p = Qident id in
  let _, _, ty as r = Typing.specialize_fsymbol p env.uc in
  let ty_exn = Tyapp (ts_exn env.uc, []) in
  if not (Denv.unify ty ty_exn) then
    errorm ~loc:id.id_loc
      "this expression has type %a, but is expected to be an exception"
      print_dty ty;
  r

let deffect env e =
  { de_reads  = List.map (dreference env) e.Pgm_ptree.pe_reads;
    de_writes = List.map (dreference env) e.Pgm_ptree.pe_writes;
    de_raises = 
      List.map (fun id -> let ls,_,_ = dexception env id in ls) 
	e.Pgm_ptree.pe_raises; }

let dpost env ty (q, ql) =
  let dexn (id, l) =
    let s, tyl, _ = dexception env id in
    let denv = match tyl with
      | [] -> env.denv
      | [ty] -> Typing.add_var id_result ty env.denv
      | _ -> assert false
    in
    s, (denv, lexpr l)
  in
  let denv = Typing.add_var id_result ty env.denv in
  (denv, lexpr q), List.map dexn ql

let rec dtype_v env = function
  | Pgm_ptree.Tpure pt -> 
      DTpure (pure_type env pt)
  | Pgm_ptree.Tarrow (bl, c) -> 
      let env, bl = map_fold_left dbinder env bl in
      let c = dtype_c env c in
      DTarrow (bl, c) 

and dtype_c env c = 
  let ty = dtype_v env c.Pgm_ptree.pc_result_type in
  { dc_result_name = c.Pgm_ptree.pc_result_name.id;
    dc_result_type = ty;
    dc_effect      = deffect env c.Pgm_ptree.pc_effect;
    dc_pre         = env.denv, lexpr c.Pgm_ptree.pc_pre;
    dc_post        = dpost env (dpurify env ty) c.Pgm_ptree.pc_post;
  }

and dbinder env ({id=x; id_loc=loc}, v) =
  let v = match v with
    | Some v -> dtype_v env v 
    | None -> DTpure (create_type_var loc)
  in
  let ty = dpurify env v in
  let env = { env with denv = Typing.add_var x ty env.denv } in
  env, (x, v)

let dvariant uc (l, p) =
  let l = lexpr l in
  let s, _ = Typing.specialize_psymbol p uc in
  let loc = Typing.qloc p in
  begin match s.ls_args with
    | [t1; t2] when Ty.ty_equal t1 t2 -> 
	()
    | _ -> 
	errorm ~loc "predicate %s should be a binary relation" 
	  s.ls_name.id_string
  end;
  l, s

let dloop_annotation uc a =
  { dloop_invariant = option_map lexpr a.Pgm_ptree.loop_invariant;
    dloop_variant   = option_map (dvariant uc) a.Pgm_ptree.loop_variant; }

let rec dexpr env e = 
  let d, ty = dexpr_desc env e.Pgm_ptree.expr_loc e.Pgm_ptree.expr_desc in
  { dexpr_desc = d; dexpr_loc = e.Pgm_ptree.expr_loc;
    dexpr_denv = env.denv; dexpr_type = ty;  }

and dexpr_desc env loc = function
  | Pgm_ptree.Econstant (ConstInt _ as c) ->
      DEconstant c, Tyapp (Ty.ts_int, [])
  | Pgm_ptree.Econstant (ConstReal _ as c) ->
      DEconstant c, Tyapp (Ty.ts_real, [])
  | Pgm_ptree.Eident (Qident {id=x}) when Typing.mem_var x env.denv ->
      (* local variable *)
      let ty = Typing.find_var x env.denv in
      DElocal x, ty
  | Pgm_ptree.Eident p ->
      let s, tyl, ty = Typing.specialize_fsymbol p env.uc in
      DEglobal s, dcurrying env.uc tyl ty
  | Pgm_ptree.Eapply (e1, e2) ->
      let e1 = dexpr env e1 in
      let e2 = dexpr env e2 in
      let ty2 = create_type_var loc and ty = create_type_var loc in
      if not (Denv.unify e1.dexpr_type (Tyapp (ts_arrow env.uc, [ty2; ty]))) 
      then
	errorm ~loc:e1.dexpr_loc "this expression is not a function";
      expected_type e2 ty2;
      DEapply (e1, e2), ty
  | Pgm_ptree.Efun (bl, t) ->
      let env, bl = map_fold_left dbinder env bl in
      let (_,e,_) as t = dtriple env t in
      let tyl = List.map (fun (x,_) -> Typing.find_var x env.denv) bl in
      let ty = dcurrying env.uc tyl e.dexpr_type in
      DEfun (bl, t), ty
  | Pgm_ptree.Elet ({id=x}, e1, e2) ->
      let e1 = dexpr env e1 in
      let ty1 = e1.dexpr_type in
      let env = { env with denv = Typing.add_var x ty1 env.denv } in
      let e2 = dexpr env e2 in
      DElet (x, e1, e2), e2.dexpr_type
  | Pgm_ptree.Eletrec (dl, e1) ->
      let env, dl = dletrec env dl in
      let e1 = dexpr env e1 in
      DEletrec (dl, e1), e1.dexpr_type

  | Pgm_ptree.Esequence (e1, e2) ->
      let e1 = dexpr env e1 in
      expected_type e1 (dty_unit env.uc);
      let e2 = dexpr env e2 in
      DEsequence (e1, e2), e2.dexpr_type
  | Pgm_ptree.Eif (e1, e2, e3) ->
      let e1 = dexpr env e1 in
      expected_type e1 (dty_bool env.uc);
      let e2 = dexpr env e2 in
      let e3 = dexpr env e3 in
      expected_type e3 e2.dexpr_type;
      DEif (e1, e2, e3), e2.dexpr_type
  | Pgm_ptree.Ewhile (e1, a, e2) ->
      let e1 = dexpr env e1 in
      expected_type e1 (dty_bool env.uc);
      let e2 = dexpr env e2 in
      expected_type e2 (dty_unit env.uc);
      DEwhile (e1, dloop_annotation env.uc a, e2), (dty_unit env.uc)
  | Pgm_ptree.Elazy (op, e1, e2) ->
      let e1 = dexpr env e1 in
      expected_type e1 (dty_bool env.uc);
      let e2 = dexpr env e2 in
      expected_type e2 (dty_bool env.uc);
      DElazy (op, e1, e2), (dty_bool env.uc)
  | Pgm_ptree.Ematch (el, bl) ->
      let el = List.map (dexpr env) el in
      let tyl = List.map (fun e -> e.dexpr_type) el in
      let ty = create_type_var loc in (* the type of all branches *)
      let branch (pl, e) =
	let denv, pl = Typing.dpat_list env.denv tyl pl in
	let env = { env with denv = denv } in
	let e = dexpr env e in
	expected_type e ty;
	pl, e
      in
      let bl = List.map branch bl in
      DEmatch (el, bl), ty
  | Pgm_ptree.Eskip ->
      DEskip, (dty_unit env.uc)
  | Pgm_ptree.Eabsurd ->
      DEabsurd, create_type_var loc
  | Pgm_ptree.Eraise (id, e) ->
      let ls, tyl, _ = dexception env id in
      let e = match e, tyl with
	| None, [] ->  
	    None
	| Some _, [] ->
	    errorm ~loc "expection %s has no argument" id.id
	| None, [ty] ->
	    errorm ~loc "exception %s is expecting an argument of type %a"
	      id.id print_dty ty;
	| Some e, [ty] -> 
	    let e = dexpr env e in
	    expected_type e ty;
	    Some e
	| _ -> 
	    assert false
      in
      DEraise (ls, e), create_type_var loc
  | Pgm_ptree.Etry (e1, hl) ->
      let e1 = dexpr env e1 in
      let handler (id, x, h) =
	let ls, tyl, _ = dexception env id in
	let x, env = match x, tyl with
	  | Some _, [] -> 
	      errorm ~loc "expection %s has no argument" id.id
	  | None, [] -> 
	      None, env
	  | None, [ty] ->
	      errorm ~loc "exception %s is expecting an argument of type %a"
		id.id print_dty ty;
	  | Some x, [ty] -> 
	      Some x.id, { env with denv = Typing.add_var x.id ty env.denv } 
	  | _ ->
	      assert false
	in
	let h = dexpr env h in
	expected_type h e1.dexpr_type;
	(ls, x, h)
      in
      DEtry (e1, List.map handler hl), e1.dexpr_type

  | Pgm_ptree.Eassert (k, le) ->
      DEassert (k, lexpr le), (dty_unit env.uc) 
  | Pgm_ptree.Eghost e1 ->
      let e1 = dexpr env e1 in
      DEghost e1, e1.dexpr_type
  | Pgm_ptree.Elabel ({id=l}, e1) ->
      let ty = dty_label env.uc in
      let env = { env with denv = Typing.add_var l ty env.denv } in
      let e1 = dexpr env e1 in
      DElabel (l, e1), e1.dexpr_type
  | Pgm_ptree.Ecast (e1, ty) ->
      let e1 = dexpr env e1 in
      let ty = pure_type env ty in
      expected_type e1 ty;
      e1.dexpr_desc, ty
  | Pgm_ptree.Eany c ->
      let c = dtype_c env c in
      DEany c, dpurify env c.dc_result_type

and dletrec env dl =
  (* add all functions into environment *)
  let add_one env (id, bl, var, t) = 
    let ty = create_type_var id.id_loc in
    let env = { env with denv = Typing.add_var id.id ty env.denv } in
    env, ((id, ty), bl, option_map (dvariant env.uc) var, t)
  in
  let env, dl = map_fold_left add_one env dl in
  (* then type-check all of them and unify *)
  let type_one ((id, tyres), bl, v, t) = 
    let env, bl = map_fold_left dbinder env bl in
    let (_,e,_) as t = dtriple env t in
    let tyl = List.map (fun (x,_) -> Typing.find_var x env.denv) bl in
    let ty = dcurrying env.uc tyl e.dexpr_type in
    if not (Denv.unify ty tyres) then 
      errorm ~loc:id.id_loc
	"this expression has type %a, but is expected to have type %a"
	print_dty ty print_dty tyres;
    ((id.id, tyres), bl, v, t)
  in
  env, List.map type_one dl

and dtriple env (p, e, q) =     
  let p = env.denv, lexpr p in
  let e = dexpr env e in
  let ty = e.dexpr_type in
  let q = dpost env ty q in
  (p, e, q)

(* phase 2: typing annotations *)

let currying uc tyl ty =
  let make_arrow_type ty1 ty2 = Ty.ty_app (ts_arrow uc) [ty1; ty2] in
  List.fold_right make_arrow_type tyl ty

let purify uc = function
  | Tpure ty -> 
      ty
  | Tarrow (bl, c) -> 
      currying uc (List.map (fun (v,_) -> v.vs_ty) bl) c.c_result_name.vs_ty

let reference _uc env = function
  | DRlocal x -> Rlocal (Mstr.find x env)
  | DRglobal ls -> Rglobal ls

let effect uc env e =
  { e_reads  = List.map (reference uc env) e.de_reads;
    e_writes = List.map (reference uc env) e.de_writes;
    e_raises = e.de_raises; }

let pre env (denv, l) = Typing.type_fmla denv env l

let post env ty (q, ql) =
  let exn (ls, (denv, l)) =
    let env = match ls.ls_args with
      | [] -> 
	  env
      | [ty] -> 
	  let v_result = create_vsymbol (id_fresh id_result) ty in
	  Mstr.add id_result v_result env
      | _ -> 
	  assert false
    in
    (ls, Typing.type_fmla denv env l)
  in
  let denv, l = q in 
  let v_result = create_vsymbol (id_fresh id_result) ty in
  let env = Mstr.add id_result v_result env in
  Typing.type_fmla denv env l, List.map exn ql

let variant denv env (t, ps) =
  let loc = t.pp_loc in
  let t = Typing.type_term denv env t in
  match ps.ls_args with
    | [t1; _] when Ty.ty_equal t1 t.t_ty -> 
	t, ps
    | [t1; _] -> 
	errorm ~loc "variant has type %a, but is expected to have type %a"
	  Pretty.print_ty t.t_ty Pretty.print_ty t1
    | _ -> 
	assert false

let rec type_v uc env = function
  | DTpure ty -> 
      Tpure (Denv.ty_of_dty ty)
  | DTarrow (bl, c) -> 
      let env, bl = map_fold_left (binder uc) env bl in
      Tarrow (bl, type_c uc env c)

and type_c uc env c = 
  let tyv = type_v uc env c.dc_result_type in
  let ty = purify uc tyv in
  let v = create_vsymbol (id_fresh c.dc_result_name) ty in
  { c_result_name = v;
    c_result_type = tyv;
    c_effect      = effect uc env c.dc_effect;
    c_pre         = pre env c.dc_pre;
    c_post        = post env ty c.dc_post;
  }
    
and binder uc env (x, tyv) = 
  let tyv = type_v uc env tyv in
  let v = create_vsymbol (id_fresh x) (purify uc tyv) in
  let env = Mstr.add x v env in
  env, (v, tyv)

let rec expr uc env e =
  let d = expr_desc uc env e.dexpr_denv e.dexpr_desc in
  let ty = Denv.ty_of_dty e.dexpr_type in
  { expr_desc = d; expr_type = ty; expr_loc = e.dexpr_loc }

and expr_desc uc env denv = function
  | DEconstant c ->
      Econstant c
  | DElocal x ->
      Elocal (Mstr.find x env)
  | DEglobal ls ->
      Eglobal ls
  | DEapply (e1, e2) ->
      Eapply (expr uc env e1, expr uc env e2)
  | DEfun (bl, e1) ->
      let env, bl = map_fold_left (binder uc) env bl in
      Efun (bl, triple uc env e1)
  | DElet (x, e1, e2) ->
      let e1 = expr uc env e1 in
      let v = create_vsymbol (id_fresh x) e1.expr_type in
      let env = Mstr.add x v env in
      Elet (v, e1, expr uc env e2)
  | DEletrec (dl, e1) ->
      let env, dl = letrec uc env dl in
      let e1 = expr uc env e1 in
      Eletrec (dl, e1)

  | DEsequence (e1, e2) ->
      Esequence (expr uc env e1, expr uc env e2)
  | DEif (e1, e2, e3) ->
      Eif (expr uc env e1, expr uc env e2, expr uc env e3)
  | DEwhile (e1, la, e2) ->
      let la = 
	{ loop_invariant = 
	    option_map (Typing.type_fmla denv env) la.dloop_invariant;
	  loop_variant   = 
	    option_map (variant denv env) la.dloop_variant; }
      in
      Ewhile (expr uc env e1, la, expr uc env e2)
  | DElazy (op, e1, e2) ->
      Elazy (op, expr uc env e1, expr uc env e2)
  | DEmatch (el, bl) ->
      let el = List.map (expr uc env) el in
      let branch (pl, e) = 
        let env, pl = map_fold_left Typing.pattern env pl in
        (pl, expr uc env e)
      in
      let bl = List.map branch bl in
      Ematch (el, bl)
  | DEskip ->
      Eskip
  | DEabsurd ->
      Eabsurd
  | DEraise (ls, e) ->
      Eraise (ls, option_map (expr uc env) e)
  | DEtry (e, hl) ->
      let handler (ls, x, h) =
	let x, env = match x with
	  | Some x -> 
	      let ty = match ls.ls_args with [ty] -> ty | _ -> assert false in
	      let v = create_vsymbol (id_fresh x) ty in
	      Some v, Mstr.add x v env 
	  | None ->
	      None, env
	in
	(ls, x, expr uc env h)
      in
      Etry (expr uc env e, List.map handler hl)

  | DEassert (k, f) ->
      let f = Typing.type_fmla denv env f in
      Eassert (k, f)
  | DEghost e1 -> 
      Eghost (expr uc env e1)
  | DElabel (s, e1) ->
      let ty = Denv.ty_of_dty (Typing.find_var s e1.dexpr_denv) in
      let v = create_vsymbol (id_fresh s) ty in
      let env = Mstr.add s v env in 
      Elabel (s, expr uc env e1)
  | DEany c ->
      let c = type_c uc env c in
      Eany c

and letrec uc env dl =
  (* add all functions into env, and compute local env *)
  let step1 env ((x, dty), bl, var, t) = 
    let ty = Denv.ty_of_dty dty in
    let v = create_vsymbol (id_fresh x) ty in
    let env = Mstr.add x v env in
    env, (v, bl, var, t)
  in
  let env, dl = map_fold_left step1 env dl in
  (* then translate variants and bodies *)
  let step2 (v, bl, var, (_,e,_ as t)) =
    let env, bl = map_fold_left (binder uc) env bl in
    let denv = e.dexpr_denv in
    let var = option_map (variant denv env) var in
    let t = triple uc env t in
    (v, bl, var, t)
  in
  let dl = List.map step2 dl in
  (* finally, check variants are all absent or all present and consistent *)
  let error e = 
    errorm ~loc:e.expr_loc "variants must be all present or all absent"
  in
  begin match dl with
    | [] -> 
	assert false
    | (_, _, None, _) :: r ->
	let check_no_variant (_,_,var,(_,e,_)) = if var <> None then error e in
	List.iter check_no_variant r
    | (_, _, Some (_, ps), _) :: r ->
	let check_variant (_,_,var,(_,e,_)) = match var with
	  | None -> error e
	  | Some (_, ps') -> if not (ls_equal ps ps') then 
	      errorm ~loc:e.expr_loc 
		"variants must share the same order relation"
	in
	List.iter check_variant r
  end;
  env, dl

and triple uc env ((denvp, p), e, q) =
  let p = Typing.type_fmla denvp env p in
  let e = expr uc env e in
  let q = post env e.expr_type q in
  (p, e, q)

let type_expr uc e =
  let denv = create_denv uc in
  let e = dexpr denv e in
  expr uc Mstr.empty e

let type_type uc ty =
  let denv = create_denv uc in
  let dty = Typing.dty denv.denv ty in
  Denv.ty_of_dty dty

let add_decl uc ls =
  try
    Theory.add_decl uc (Decl.create_logic_decl [ls, None])
  with Theory.ClashSymbol _ ->
    let loc = match ls.ls_name.id_origin with
      | User loc -> Some loc
      | _ -> None (* FIXME: loc for recursive functions *)
    in
    errorm ?loc "clash with previous symbol %s" ls.ls_name.id_string
    
let file env uc dl =
  let uc, dl =
    List.fold_left
      (fun (uc, acc) d -> match d with
	 | Pgm_ptree.Dlogic dl -> 
	     let dl = logic_list0_decl dl in
	     List.fold_left (Typing.add_decl env Mnm.empty) uc dl, acc
	 | Pgm_ptree.Dlet (id, e) -> 
	     let e = type_expr uc e in
	     let tyl, ty = uncurrying uc e.expr_type in
	     let ls = create_lsymbol (id_user id.id id.id_loc) tyl (Some ty) in
	     let uc = add_decl uc ls in
	     uc, Dlet (ls, e) :: acc
	 | Pgm_ptree.Dletrec dl -> 
	     let denv = create_denv uc in
	     let _, dl = dletrec denv dl in
	     let _, dl = letrec uc Mstr.empty dl in
	     let one uc (v,_,_,_ as r) =
	       let tyl, ty = uncurrying uc v.vs_ty in
	       let id = id_fresh v.vs_name.id_string in
	       let ls = create_lsymbol id tyl (Some ty) in
	       add_decl uc ls, (ls, r)
	     in
	     let uc, dl = map_fold_left one uc dl in
	     uc, Dletrec dl :: acc
	 | Pgm_ptree.Dparam (id, tyv) ->
	     let denv = create_denv uc in
	     let tyv = dtype_v denv tyv in
	     let tyv = type_v uc Mstr.empty tyv in
	     let tyl, ty = uncurrying uc (purify uc tyv) in
	     let ls = create_lsymbol (id_user id.id id.id_loc) tyl (Some ty) in
	     let uc = add_decl uc ls in
	     uc, Dparam (ls, tyv) :: acc
	 | Pgm_ptree.Dexn (id, ty) ->
	     let tyl = match ty with
	       | None -> []
	       | Some ty -> [type_type uc ty]
	     in
	     let exn = ty_app (ts_exn uc) [] in
	     let ls = create_lsymbol (id_user id.id id.id_loc) tyl (Some exn) in
	     let uc = add_decl uc ls in
	     uc, acc
      )
      (uc, []) dl
  in
  uc, List.rev dl

(*
Local Variables: 
compile-command: "unset LANG; make -C ../.. testl"
End: 
*)

(* 
TODO:
- tuples

- mutually recursive functions: allow only one order relation specified

- program symbol table outside of the theory

- ghost / effects
*)
