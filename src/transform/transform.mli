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

open Ident
open Theory

(* Tranformation on context with some memoisations *)

(** General functions *)

(* The type of transformation from list of 'a to list of 'b *)
type 'a t
type ctxt_t = context t

(* compose two transformations, the underlying datastructures for
   the memoisation are shared *)
val compose : context t -> 'a t -> 'a t

(* apply a transformation and memoise *)
val apply : 'a t -> context -> 'a

(** General constructors *)
(* create a transformation with only one memoisation *)
val register : (context -> 'a) -> 'a t

(* Fold from the first declaration to the last with a memoisation at
   each step *)
val fold : (context -> 'a -> 'a) -> 'a -> 'a t

val fold_env : (context -> 'a -> 'a) -> (env -> 'a) -> 'a t

val fold_map : (context -> 'a * context -> 'a * context) -> 'a -> context t

val map : (context -> context -> context) -> context t


val map_concat : (context -> decl list) -> context t


(* map the element of the list without an environnment.
   A memoisation is performed at each step, and for each elements *)
val elt : (decl -> decl list) -> context t


(** Utils *)
(*type odecl =
  | Otype of ty_decl
  | Ologic of logic_decl
  | Oprop of prop_decl
  | Ouse   of theory
  | Oclone of (ident * ident) list
*)
(*
val elt_of_oelt :
  ty:(ty_decl -> ty_decl) ->
  logic:(logic_decl -> logic_decl) ->
  ind:(ind_decl list -> decl list) ->
  prop:(prop_decl -> decl list) ->
  use:(theory -> decl list) ->
  clone:(theory -> (ident * ident) list -> decl list) ->
  (decl -> decl list)

val fold_context_of_decl:
  (context -> 'a -> decl -> 'a * decl list) ->
  context -> 'a -> context -> decl -> ('a * context)
*)

(* Utils *)

val split_goals : context list t

exception NotGoalContext
val goal_of_ctxt : context -> prop
(* goal_of_ctxt ctxts return the goal of a goal context
   the ctxt must end with a goal.*)

val identity : context t
