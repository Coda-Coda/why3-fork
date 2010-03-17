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


(* Inline the definition not recursive *)

val t :
  isnotinlinedt:(Term.term -> bool) ->
  isnotinlinedf:(Term.fmla -> bool) -> 
  Task.task Trans.trans


(* Inline them all *)

val all : unit -> Task.task Trans.trans

(* Inline only the trivial definition :
   logic c : t = a
   logic f(x : t,...., ) : t = g(y : t2,...) *)
val trivial : unit -> Task.task Trans.trans


(* Function to use in other transformations if inlining is needed *)

type env

val empty_env : env

(*val add_decl : env -> Theory.decl -> env *)

val replacet : env -> Term.term -> Term.term 
val replacep : env -> Term.fmla -> Term.fmla
