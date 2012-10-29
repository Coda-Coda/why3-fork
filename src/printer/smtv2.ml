(********************************************************************)
(*                                                                  *)
(*  The Why3 Verification Platform   /   The Why3 Development Team  *)
(*  Copyright 2010-2012   --   INRIA - CNRS - Paris-Sud University  *)
(*                                                                  *)
(*  This software is distributed under the terms of the GNU Lesser  *)
(*  General Public License version 2.1, with the special exception  *)
(*  on linking described in file LICENSE.                           *)
(*                                                                  *)
(********************************************************************)

(** SMT v1 printer with some extensions *)

open Format
open Pp
open Ident
open Ty
open Term
open Decl
open Theory
open Printer

let ident_printer =
  let bls = (*["and";" benchmark";" distinct";"exists";"false";"flet";"forall";
     "if then else";"iff";"implies";"ite";"let";"logic";"not";"or";
     "sat";"theory";"true";"unknown";"unsat";"xor";
     "assumption";"axioms";"defintion";"extensions";"formula";
     "funs";"extrafuns";"extrasorts";"extrapreds";"language";
     "notes";"preds";"sorts";"status";"theory";"Int";"Real";"Bool";
     "Array";"U";"select";"store"]*)
    (** smtlib2 V2 p71 *)
    [(** General: *)
      "!";"_"; "as"; "DECIMAL"; "exists"; "forall"; "let"; "NUMERAL";
      "par"; "STRING";
       (**Command names:*)
      "assert";"check-sat"; "declare-sort";"declare-fun";"define-sort";
      "define-fun";"exit";"get-assertions";"get-assignment"; "get-info";
      "get-option"; "get-proof"; "get-unsat-core"; "get-value"; "pop"; "push";
      "set-logic"; "set-info"; "set-option";
       (** for security *)
      "Bool";"unsat";"sat";"true";"false";"select";"store";
       (** arrays -- this really belongs to the driver! (esp. const) *)
      "Array";"select";"store";"const";
       (** div and mod are builtin *)
      "div";"mod";
      ]
  in
  let san = sanitizer char_to_alpha char_to_alnumus in
  create_ident_printer bls ~sanitizer:san

let print_ident fmt id =
  fprintf fmt "%s" (id_unique ident_printer id)

(** type *)
type info = {
  info_syn : syntax_map;
(*  complex_type : ty Hty.t; *)
}

let rec print_type info fmt ty = match ty.ty_node with
  | Tyvar _ -> unsupported "smt : you must encode the polymorphism"
  | Tyapp (ts, []) -> begin match query_syntax info.info_syn ts.ts_name with
      | Some s -> syntax_arguments s (print_type info) fmt []
      | None -> fprintf fmt "%a" print_ident ts.ts_name
  end
  | Tyapp (ts, l) ->
     begin match query_syntax info.info_syn ts.ts_name with
      | Some s -> syntax_arguments s (print_type info) fmt l
      | None -> fprintf fmt "(%a %a)" print_ident ts.ts_name
        (print_list space (print_type info)) l
     end

(*
let iter_complex_type info fmt () ty =
    match ty.ty_node with
      | Tyapp (_,_::_) when not (Hty.mem info.complex_type ty) ->
        let id = id_fresh (Pp.string_of_wnl Pretty.print_ty ty) in
        let ts = create_tysymbol id [] None in
        let cty = ty_app ts [] in
        fprintf fmt "(define-sorts ((%a %a)))@\n"
          print_ident ts.ts_name
          (print_type info) ty;
        Hty.add info.complex_type ty cty
      | _ -> ()

let find_complex_type info fmt f =
  t_ty_fold (iter_complex_type info fmt) () f

let print_type info fmt ty =
  print_type info fmt
    (try
       Hty.find info.complex_type ty
     with Not_found -> ty)
*)

(* and print_tyapp info fmt = function *)
(*   | [] -> () *)
(*   | [ty] -> fprintf fmt "%a " (print_type info) ty *)
(*   | tl -> fprintf fmt "(%a) " (print_list comma (print_type info)) tl *)

let print_type info fmt =
  catch_unsupportedType (print_type info fmt)

let print_type_value info fmt = function
  | None -> fprintf fmt "Bool"
  | Some ty -> print_type info fmt ty

(** var *)
let forget_var v = forget_id ident_printer v.vs_name

let print_var fmt {vs_name = id} =
  let n = id_unique ident_printer id in
  fprintf fmt "%s" n

let print_typed_var info fmt vs =
  fprintf fmt "(%a %a)" print_var vs
    (print_type info) vs.vs_ty

let print_var_list info fmt vsl =
  print_list space (print_typed_var info) fmt vsl

(** expr *)
let rec print_term info fmt t = match t.t_node with
  | Tconst c ->
      let number_format = {
          Print_number.long_int_support = true;
          Print_number.dec_int_support = Print_number.Number_default;
          Print_number.hex_int_support = Print_number.Number_unsupported;
          Print_number.oct_int_support = Print_number.Number_unsupported;
          Print_number.bin_int_support = Print_number.Number_unsupported;
          Print_number.def_int_support = Print_number.Number_unsupported;
          Print_number.dec_real_support = Print_number.Number_unsupported;
          Print_number.hex_real_support = Print_number.Number_unsupported;
          Print_number.frac_real_support = Print_number.Number_custom
            (Print_number.PrintFracReal ("%s.0", "(* %s.0 %s.0)", "(/ %s.0 %s.0)"));
          Print_number.def_real_support = Print_number.Number_unsupported;
        } in
      Print_number.print number_format fmt c
  | Tvar v -> print_var fmt v
  | Tapp (ls, tl) -> begin match query_syntax info.info_syn ls.ls_name with
      | Some s -> syntax_arguments_typed s (print_term info)
        (print_type info) t fmt tl
      | None -> begin match tl with (* for cvc3 wich doesn't accept (toto ) *)
          | [] -> fprintf fmt "@[%a@]" print_ident ls.ls_name
          | _ -> fprintf fmt "@[(%a@ %a)@]"
              print_ident ls.ls_name (print_list space (print_term info)) tl
        end end
  | Tlet (t1, tb) ->
      let v, t2 = t_open_bound tb in
      fprintf fmt "@[(let ((%a %a))@ %a)@]" print_var v
        (print_term info) t1 (print_term info) t2;
      forget_var v
  | Tif (f1,t1,t2) ->
      fprintf fmt "@[(ite %a@ %a@ %a)@]"
        (print_fmla info) f1 (print_term info) t1 (print_term info) t2
  | Tcase _ -> unsupportedTerm t
      "smtv2 : you must eliminate match"
  | Teps _ -> unsupportedTerm t
      "smtv2 : you must eliminate epsilon"
  | Tquant _ | Tbinop _ | Tnot _ | Ttrue | Tfalse -> raise (TermExpected t)

and print_fmla info fmt f = match f.t_node with
  | Tapp ({ ls_name = id }, []) ->
      print_ident fmt id
  | Tapp (ls, tl) -> begin match query_syntax info.info_syn ls.ls_name with
      | Some s -> syntax_arguments_typed s (print_term info)
        (print_type info) f fmt tl
      | None -> begin match tl with (* for cvc3 wich doesn't accept (toto ) *)
          | [] -> fprintf fmt "%a" print_ident ls.ls_name
          | _ -> fprintf fmt "(%a@ %a)"
              print_ident ls.ls_name (print_list space (print_term info)) tl
        end end
  | Tquant (q, fq) ->
      let q = match q with Tforall -> "forall" | Texists -> "exists" in
      let vl, tl, f = t_open_quant fq in
      (* TODO trigger dépend des capacités du prover : 2 printers?
      smtwithtriggers/smtstrict *)
      if tl = [] then
        fprintf fmt "@[(%s@ (%a)@ %a)@]"
          q
          (print_var_list info) vl
          (print_fmla info) f
      else
        fprintf fmt "@[(%s@ (%a)@ (! %a %a))@]"
          q
          (print_var_list info) vl
          (print_fmla info) f
          (print_triggers info) tl;
      List.iter forget_var vl
  | Tbinop (Tand, f1, f2) ->
      fprintf fmt "@[(and@ %a@ %a)@]" (print_fmla info) f1 (print_fmla info) f2
  | Tbinop (Tor, f1, f2) ->
      fprintf fmt "@[(or@ %a@ %a)@]" (print_fmla info) f1 (print_fmla info) f2
  | Tbinop (Timplies, f1, f2) ->
      fprintf fmt "@[(=>@ %a@ %a)@]"
        (print_fmla info) f1 (print_fmla info) f2
  | Tbinop (Tiff, f1, f2) ->
      fprintf fmt "@[(=@ %a@ %a)@]" (print_fmla info) f1 (print_fmla info) f2
  | Tnot f ->
      fprintf fmt "@[(not@ %a)@]" (print_fmla info) f
  | Ttrue ->
      fprintf fmt "true"
  | Tfalse ->
      fprintf fmt "false"
  | Tif (f1, f2, f3) ->
      fprintf fmt "@[(ite %a@ %a@ %a)@]"
        (print_fmla info) f1 (print_fmla info) f2 (print_fmla info) f3
  | Tlet (t1, tb) ->
      let v, f2 = t_open_bound tb in
      fprintf fmt "@[(let ((%a %a))@ %a)@]" print_var v
        (print_term info) t1 (print_fmla info) f2;
      forget_var v
  | Tcase _ -> unsupportedTerm f
      "smtv2 : you must eliminate match"
  | Tvar _ | Tconst _ | Teps _ -> raise (FmlaExpected f)

and print_expr info fmt =
  TermTF.t_select (print_term info fmt) (print_fmla info fmt)

and print_trigger info fmt e = fprintf fmt "%a" (print_expr info) e

and print_triggers info fmt = function
  | [] -> ()
  | a::l -> fprintf fmt ":pattern (%a) %a"
    (print_list space (print_trigger info)) a
    (print_triggers info) l

let _print_logic_binder info fmt v =
  fprintf fmt "%a: %a" print_ident v.vs_name
    (print_type info) v.vs_ty

let print_type_decl info fmt ts =
  if ts.ts_def <> None then () else
  if Mid.mem ts.ts_name info.info_syn then () else
  fprintf fmt "(declare-sort %a %i)@\n@\n"
    print_ident ts.ts_name (List.length ts.ts_args)

let print_param_decl info fmt ls =
  if Mid.mem ls.ls_name info.info_syn then () else
  fprintf fmt "@[<hov 2>(declare-fun %a (%a) %a)@]@\n@\n"
    print_ident ls.ls_name
    (print_list space (print_type info)) ls.ls_args
    (print_type_value info) ls.ls_value

let print_logic_decl info fmt (ls,def) =
  if Mid.mem ls.ls_name info.info_syn then () else
  let vsl,expr = Decl.open_ls_defn def in
  fprintf fmt "@[<hov 2>(declare-fun %a (%a) %a %a)@]@\n@\n"
    print_ident ls.ls_name
    (print_var_list info) vsl
    (print_type_value info) ls.ls_value
    (print_expr info) expr;
  List.iter forget_var vsl

let print_prop_decl info fmt k pr f = match k with
  | Paxiom ->
      fprintf fmt "@[<hov 2>;; %s@\n(assert@ %a)@]@\n@\n"
        pr.pr_name.id_string (* FIXME? collisions *)
        (print_fmla info) f
  | Pgoal ->
      fprintf fmt "@[(assert@\n";
      fprintf fmt "@[;; %a@]@\n" print_ident pr.pr_name;
      (match pr.pr_name.id_loc with
        | None -> ()
        | Some loc -> fprintf fmt " @[;; %a@]@\n"
            Loc.gen_report_position loc);
      fprintf fmt "  @[(not@ %a))@]@\n" (print_fmla info) f;
      fprintf fmt "@[(check-sat)@]@\n"
  | Plemma| Pskip -> assert false

let print_decl info fmt d = match d.d_node with
  | Dtype ts ->
      print_type_decl info fmt ts
  | Ddata _ -> unsupportedDecl d
      "smtv2 : algebraic type are not supported"
  | Dparam ls ->
      print_param_decl info fmt ls
  | Dlogic dl ->
      print_list nothing (print_logic_decl info) fmt dl
  | Dind _ -> unsupportedDecl d
      "smtv2 : inductive definition are not supported"
  | Dprop (k,pr,f) ->
      if Mid.mem pr.pr_name info.info_syn then () else
      print_prop_decl info fmt k pr f

let print_decl info fmt = catch_unsupportedDecl (print_decl info fmt)

let distingued =
  let dist_syntax mls = function
    | [MAls ls;MAstr s] -> Mls.add ls s mls
    | _ -> assert false in
  let dist_dist syntax mls = function
    | [MAls ls;MAls lsdis] ->
      begin try
              Mid.add lsdis.ls_name (Mls.find ls syntax) mls
        with Not_found -> mls end
    | _ -> assert false in
  Trans.on_meta meta_syntax_logic (fun syntax ->
    let syntax = List.fold_left dist_syntax Mls.empty syntax in
    Trans.on_meta Discriminate.meta_lsinst (fun dis ->
      let dis2 = List.fold_left (dist_dist syntax) Mid.empty dis in
      Trans.return dis2))

let print_task_old pr thpr _blacklist fmt task =
  print_prelude fmt pr;
  print_th_prelude task fmt thpr;
  let info = {
    info_syn = Mid.union (fun _ _ s -> Some s)
      (get_syntax_map task) (Trans.apply distingued task);
    (* complex_type = Hty.create 5; *)
  }
  in
  let decls = Task.task_decls task in
  fprintf fmt "%a@." (print_list nothing (print_decl info)) decls

let () = register_printer "smtv2"
  (fun _env pr thpr blacklist ?old:_ fmt task ->
     forget_all ident_printer;
     print_task_old pr thpr blacklist fmt task)
  ~desc:"Printer for the SMTlib version 2 format."

(*
let print_decls =
  let add_ls sm acc = function
    | [MAls ls; MAls lsdis] ->
        begin try
          Mid.add lsdis.ls_name (Mid.find ls.ls_name sm) acc
        with Not_found -> acc end
    | _ -> assert false in
  let print dls sm fmt d =
    let info = {
      info_syn = List.fold_left (add_ls sm) sm dls;
    } in
    print_decl info fmt d in
  Trans.on_meta Discriminate.meta_lsinst (fun dls ->
    Printer.sprint_decls (print dls))

let print_task _env pr thpr _blacklist ?old:_ fmt task =
  (* In trans-based p-printing [forget_all] is taboo *)
  (* forget_all ident_printer; *)
  print_prelude fmt pr;
  print_th_prelude task fmt thpr;
  fprintf fmt "%a@." (print_list nothing string)
    (List.rev (Trans.apply print_decls task))

let () = register_printer "smtv2new" print_task
  ~desc:"Printer for the SMTlib version 2 format."
*)
