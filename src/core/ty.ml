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
open Ident

(** Types *)

type tvsymbol = ident

(* type symbols and types *)

type tysymbol = {
  ts_name : ident;
  ts_args : tvsymbol list;
  ts_def  : ty option;
}

and ty = {
  ty_node : ty_node;
  ty_tag : int;
}

and ty_node =
  | Tyvar of tvsymbol
  | Tyapp of tysymbol * ty list

module Tsym = struct
  type t = tysymbol
  let equal = (==)
  let hash ts = ts.ts_name.id_tag
  let compare ts1 ts2 =
    Pervasives.compare ts1.ts_name.id_tag ts2.ts_name.id_tag
end
module Sts = Set.Make(Tsym)
module Mts = Map.Make(Tsym)
module Hts = Hashtbl.Make(Tsym)

let mk_ts name args def = {
  ts_name = name;
  ts_args = args;
  ts_def  = def;
}

let create_tvsymbol = id_register
let create_tysymbol name args def = mk_ts (id_register name) args def

module Ty = struct

  type t = ty

  let equal ty1 ty2 = match ty1.ty_node, ty2.ty_node with
    | Tyvar n1, Tyvar n2 -> n1 == n2
    | Tyapp (s1, l1), Tyapp (s2, l2) -> s1 == s2 && List.for_all2 (==) l1 l2
    | _ -> false

  let hash_ty ty = ty.ty_tag

  let hash ty = match ty.ty_node with
    | Tyvar v -> v.id_tag
    | Tyapp (s, tl) -> Hashcons.combine_list hash_ty s.ts_name.id_tag tl

  let tag n ty = { ty with ty_tag = n }

end
module Hty = Hashcons.Make(Ty)

let mk_ty n = { ty_node = n; ty_tag = -1 }
let ty_var n = Hty.hashcons (mk_ty (Tyvar n))
let ty_app s tl = Hty.hashcons (mk_ty (Tyapp (s, tl)))

(* generic traversal functions *)

let ty_map fn ty = match ty.ty_node with
  | Tyvar _ -> ty
  | Tyapp (f, tl) -> ty_app f (List.map fn tl)

let ty_fold fn acc ty = match ty.ty_node with
  | Tyvar _ -> acc
  | Tyapp (f, tl) -> List.fold_left fn acc tl

let ty_forall pr ty =
  try ty_fold (forall_fn pr) true ty with FoldSkip -> false

let ty_exists pr ty =
  try ty_fold (exists_fn pr) false ty with FoldSkip -> true

(* smart constructors *)

exception NonLinear
exception UnboundTypeVariable

let rec tv_known vs ty = match ty.ty_node with
  | Tyvar n -> Sid.mem n vs
  | _ -> ty_forall (tv_known vs) ty

let create_tysymbol name args def =
  let add s v =
    if Sid.mem v s then raise NonLinear;
    Sid.add v s
  in
  let s = List.fold_left add Sid.empty args in
  let _ = match def with
    | Some ty -> tv_known s ty || raise UnboundTypeVariable
    | _ -> true
  in
  create_tysymbol name args def

exception BadTypeArity

let rec tv_inst m ty = match ty.ty_node with
  | Tyvar n -> Mid.find n m
  | _ -> ty_map (tv_inst m) ty

let ty_app s tl =
  if List.length tl == List.length s.ts_args
  then match s.ts_def with
    | Some ty ->
        let add m v t = Mid.add v t m in
        tv_inst (List.fold_left2 add Mid.empty s.ts_args tl) ty
    | _ ->
        ty_app s tl
  else raise BadTypeArity

(* symbol-wise map/fold *)

let rec ty_s_map fn ty = match ty.ty_node with
  | Tyvar _ -> ty
  | Tyapp (f, tl) -> ty_app (fn f) (List.map (ty_s_map fn) tl)

let rec ty_s_fold fn acc ty = match ty.ty_node with
  | Tyvar _ -> acc
  | Tyapp (f, tl) -> List.fold_left (ty_s_fold fn) (fn acc f) tl

let ty_s_forall pr ty =
  try ty_s_fold (forall_fn pr) true ty with FoldSkip -> false

let ty_s_exists pr ty =
  try ty_s_fold (exists_fn pr) false ty with FoldSkip -> true

(* type matching *)

exception TypeMismatch

let rec matching s ty1 ty2 =
  if ty1 == ty2 then s
  else match ty1.ty_node, ty2.ty_node with
    | Tyvar n1, _ ->
        (try if Mid.find n1 s == ty2 then s else raise TypeMismatch
         with Not_found -> Mid.add n1 ty2 s)
    | Tyapp (f1, l1), Tyapp (f2, l2) when f1 == f2 ->
        List.fold_left2 matching s l1 l2
    | _ ->
        raise TypeMismatch

let ty_match ty1 ty2 s =
  try Some (matching s ty1 ty2) with TypeMismatch -> None

