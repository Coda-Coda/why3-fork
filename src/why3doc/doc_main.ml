(**************************************************************************)
(*                                                                        *)
(*  Copyright (C) 2010-2012                                               *)
(*    François Bobot                                                      *)
(*    Jean-Christophe Filliâtre                                           *)
(*    Claude Marché                                                       *)
(*    Guillaume Melquiond                                                 *)
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
open Why3
open Util
open Theory

let () = Debug.set_flag Glob.flag

(* command line parsing *)

let usage_msg = sprintf
  "Usage: %s [options...] [files...]"
  (Filename.basename Sys.argv.(0))

let opt_loadpath = ref []
let opt_output = ref None
let opt_queue = Queue.create ()

let option_list = Arg.align [
  "-L", Arg.String (fun s -> opt_loadpath := s :: !opt_loadpath),
      "<dir> Add <dir> to the library search path";
  "-o", Arg.String (fun s -> opt_output := Some s),
      "<dir> Print files in <dir>";
  "--output", Arg.String (fun s -> opt_output := Some s),
      " same as -o";
]

let add_opt_file x = Queue.add x opt_queue

let () =
  Arg.parse option_list add_opt_file usage_msg;
  let config = Whyconf.read_config None in
  let main = Whyconf.get_main config in
  opt_loadpath := List.rev_append !opt_loadpath (Whyconf.loadpath main);
  Doc_def.set_loadpath !opt_loadpath;
  Doc_def.set_output_dir !opt_output

let css =
  let css_fname = match !opt_output with
    | None -> "style.css"
    | Some dir -> Filename.concat dir "style.css"
  in
  if not (Sys.file_exists css_fname) then Doc_html.style_css css_fname;
  css_fname

let do_file env fname =
  let m = Env.read_file env fname in
  let add _s th = Doc_def.add_ident th.th_name in
  Mstr.iter add m

let print_file fname =
  let fhtml = Doc_def.output_file fname in
  let c = open_out fhtml in
  let fmt = formatter_of_out_channel c in
  let f = Filename.basename fname in
  Doc_html.print_header fmt ~title:f ~css ();
  Doc_lexer.do_file fmt fname;
  Doc_html.print_footer fmt ();
  close_out c

let () =
  Queue.iter Doc_def.add_file opt_queue;
  try
    let env = Env.create_env !opt_loadpath in
    Queue.iter (do_file env) opt_queue;
    Queue.iter print_file opt_queue
  with e when not (Debug.test_flag Debug.stack_trace) ->
    eprintf "%a@." Exn_printer.exn_printer e;
    exit 1

(*
Local Variables:
compile-command: "unset LANG; make -C ../.. bin/why3doc.opt"
End:
*)
