(********************************************************************)
(*                                                                  *)
(*  The Why3 Verification Platform   /   The Why3 Development Team  *)
(*  Copyright 2010-2016   --   INRIA - CNRS - Paris-Sud University  *)
(*                                                                  *)
(*  This software is distributed under the terms of the GNU Lesser  *)
(*  General Public License version 2.1, with the special exception  *)
(*  on linking described in file LICENSE.                           *)
(*                                                                  *)
(********************************************************************)

(** Printer for extracted OCaml code *)

open Compile
open Format
open Pmodule
open Theory
open Ident
open Pp

module Print = struct

  open ML

  let ocaml_keywords =
    ["and"; "as"; "assert"; "asr"; "begin";
     "class"; "constraint"; "do"; "done"; "downto"; "else"; "end";
     "exception"; "external"; "false"; "for"; "fun"; "function";
     "functor"; "if"; "in"; "include"; "inherit"; "initializer";
     "land"; "lazy"; "let"; "lor"; "lsl"; "lsr"; "lxor"; "match";
     "method"; "mod"; "module"; "mutable"; "new"; "object"; "of";
     "open"; "or"; "private"; "rec"; "sig"; "struct"; "then"; "to";
     "true"; "try"; "type"; "val"; "virtual"; "when"; "while"; "with";
     "raise";]

  let iprinter, aprinter =
    let isanitize = sanitizer char_to_alpha char_to_alnumus in
    let lsanitize = sanitizer char_to_lalpha char_to_alnumus in
    create_ident_printer ocaml_keywords ~sanitizer:isanitize,
    create_ident_printer ocaml_keywords ~sanitizer:lsanitize

  let print_ident fmt id =
    let s = id_unique iprinter id in
    fprintf fmt "%s" s

  (* let print_lident = print_qident ~sanitizer:Strings.uncapitalize *)
  (* let print_uident = print_qident ~sanitizer:Strings.capitalize *)

  let print_tv fmt tv =
    fprintf fmt "'%s" (id_unique aprinter tv)

  (** Types *)

  let protect_on b s =
    if b then "(" ^^ s ^^ ")" else s

  let star fmt () = fprintf fmt " *@ "

  let rec print_ty ?(paren=false) fmt = function
    | Tvar id ->
       print_tv fmt id
    | Ttuple [] ->
       fprintf fmt "unit"
    | Ttuple tl ->
       fprintf fmt (protect_on paren "%a") (print_list star (print_ty ~paren:false)) tl
    | Tapp (ts, []) ->
       print_ident fmt ts
    | Tapp (ts, [ty]) ->
       fprintf fmt (protect_on paren "%a@ %a")
               (print_ty ~paren:true) ty print_ident ts
    | Tapp (ts, tl) ->
       fprintf fmt (protect_on paren "(%a)@ %a")
               (print_list comma (print_ty ~paren:false)) tl
               print_ident ts

  let print_vsty fmt (v, ty) =
    fprintf fmt "%a:@ %a" print_ident v (print_ty ~paren:false) ty

  let print_tv_arg = print_tv
  let print_tv_args fmt = function
    | []   -> ()
    | [tv] -> fprintf fmt "%a@ " print_tv_arg tv
    | tvl  -> fprintf fmt "(%a)@ " (print_list comma print_tv_arg) tvl

  let print_vs_arg fmt vs =
    fprintf fmt "@[(%a)@]" print_vsty vs

  let print_path =
    print_list dot pp_print_string (* point-free *)

  let print_path_id fmt = function
    | [], id -> print_ident fmt id
    | p, id  -> fprintf fmt "%a.%a" print_path p print_ident id

  let print_theory_name fmt th =
    print_path_id fmt (th.th_path, th.th_name)

  let print_module_name fmt m =
    print_theory_name fmt m.mod_theory

  let rec print_enode fmt = function
    | Eident id ->
       print_ident fmt id
    | Elet (id, e1, e2) ->
       fprintf fmt "@[<hov 2>let @[%a@] =@ @[%a@]@] in@ %a"
               print_ident id
               print_expr e1
               print_expr e2
    | _ -> (* TODO *) assert false

  and print_expr fmt e =
    print_enode fmt e.e_node

  let print_type_decl fmt (id, args, tydef) =
    let print_constr fmt (id, constrs) =
      match constrs with
      | [] ->
         fprintf fmt "@[<hov 4>| %a@]"
                 print_ident id (* FIXME: first letter must be uppercase
                                       -> print_uident *)
      | l ->
         fprintf fmt "@[<hov 4>| %a of %a@]"
                 print_ident id (* FIXME: print_uident *)
                 (print_list star (print_ty ~paren:false)) l
    in
    let print_def fmt = function
      | Dabstract ->
         ()
      | Ddata csl ->
         fprintf fmt " =@\n%a" (print_list newline print_constr) csl
      | Dalias ty ->
         fprintf fmt " =@ %a" (print_ty ~paren:false) ty
      | _ -> (* TODO *) assert false
    in
    fprintf fmt "@[<hov 2>%s %a%a%a@]"
            (if true then "type" else "and") (* FIXME: mutual recursive types *)
            print_tv_args args
            print_ident id  (* FIXME: first letter must be lowercase
                                   -> print_lident *)
            print_def tydef

  let print_decl fmt = function
    | Dlet (isrec, [id, vl, e]) ->
       fprintf fmt "@[<hov 2>%s %a@ %a =@ %a@]"
               (if isrec then "let rec" else "let")
               print_ident id
               (print_list space print_vs_arg) vl
               print_expr e;
       fprintf fmt "@\n@\n"
    | Dtype dl ->
       print_list newline print_type_decl fmt dl;
       fprintf fmt "@\n@\n"
    | _ -> (* TODO *) assert false

end

let extract_module fmt m =
  fprintf fmt
    "(* This file has been generated from Why3 module %a *)@\n@\n"
    Print.print_module_name m;
  let mdecls = Translate.module_ m in
  print_list nothing Print.print_decl fmt mdecls;
  fprintf fmt "@."