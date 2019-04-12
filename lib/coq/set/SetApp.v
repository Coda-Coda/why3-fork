(* This file is generated by Why3's Coq-realize driver *)
(* Beware! Only edit allowed sections below    *)
Require Import BuiltIn.
Require BuiltIn.
Require HighOrd.
Require int.Int.
Require set.Fset.

(* Why3 goal *)
Definition elt : Type.
Proof.
(* TODO find something more interesting *)
apply bool.
Defined.

(* Why3 goal *)
Definition set : Type.
Proof.
(* TODO find something more interesting *)
apply bool.
Defined.

(* Why3 goal *)
Definition to_fset : set -> set.Fset.fset elt.
Proof.
(* TODO find something more interesting *)
intros. exists (fun _ => false).
exists nil. split. constructor. intros. split.
intros. destruct H. intro. inversion H.
Defined.

(* Why3 goal *)
Definition choose : set -> elt.
Proof.
intros.
apply true.
Defined.

(* Why3 goal *)
Lemma choose_spec :
  forall (s:set), ~ set.Fset.is_empty (to_fset s) ->
  set.Fset.mem (choose s) (to_fset s).
Proof.
intros s h1.
destruct h1. unfold set.Fset.is_empty. intros.
unfold to_fset. simpl. unfold set.Set.mem.
intuition.
Qed.
