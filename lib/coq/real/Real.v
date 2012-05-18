(* This file is generated by Why3's Coq driver *)
(* Beware! Only edit allowed sections below    *)
Require Import ZArith.
Require Import Rbase.

(* Why3 goal *)
Definition infix_ls: R -> R -> Prop.
exact Rlt.
Defined.

(* Why3 assumption *)
Definition infix_lseq(x:R) (y:R): Prop := (infix_ls x y) \/ (x = y).

(* Why3 goal *)
Definition infix_pl: R -> R -> R.
exact Rplus.
Defined.

(* Why3 goal *)
Definition prefix_mn: R -> R.
exact Ropp.
Defined.

(* Why3 goal *)
Definition infix_as: R -> R -> R.
exact Rmult.
Defined.

(* Why3 goal *)
Lemma Unit_def : forall (x:R), ((infix_pl x 0%R) = x).
exact Rplus_0_r.
Qed.

(* Why3 goal *)
Lemma Assoc : forall (x:R) (y:R) (z:R), ((infix_pl (infix_pl x y)
  z) = (infix_pl x (infix_pl y z))).
exact Rplus_assoc.
Qed.

(* Why3 goal *)
Lemma Inv_def : forall (x:R), ((infix_pl x (prefix_mn x)) = 0%R).
exact Rplus_opp_r.
Qed.

(* Why3 goal *)
Lemma Comm : forall (x:R) (y:R), ((infix_pl x y) = (infix_pl y x)).
exact Rplus_comm.
Qed.

(* Why3 goal *)
Lemma Assoc1 : forall (x:R) (y:R) (z:R), ((infix_as (infix_as x y)
  z) = (infix_as x (infix_as y z))).
exact Rmult_assoc.
Qed.

(* Why3 goal *)
Lemma Mul_distr : forall (x:R) (y:R) (z:R), ((infix_as x (infix_pl y
  z)) = (infix_pl (infix_as x y) (infix_as x z))).
exact Rmult_plus_distr_l.
Qed.

(* Why3 assumption *)
Definition infix_mn(x:R) (y:R): R := (infix_pl x (prefix_mn y)).

(* Why3 goal *)
Lemma Comm1 : forall (x:R) (y:R), ((infix_as x y) = (infix_as y x)).
exact Rmult_comm.
Qed.

(* Why3 goal *)
Lemma Unitary : forall (x:R), ((infix_as 1%R x) = x).
exact Rmult_1_l.
Qed.

(* Why3 goal *)
Lemma NonTrivialRing : ~ (0%R = 1%R).
apply not_eq_sym.
exact R1_neq_R0.
Qed.

(* Why3 goal *)
Definition inv: R -> R.
exact Rinv.
Defined.

(* Why3 goal *)
Lemma Inverse : forall (x:R), (~ (x = 0%R)) -> ((infix_as x (inv x)) = 1%R).
exact Rinv_r.
Qed.

(* Why3 assumption *)
Definition infix_sl(x:R) (y:R): R := (infix_as x (inv y)).

(* Why3 goal *)
Lemma add_div : forall (x:R) (y:R) (z:R), (~ (z = 0%R)) ->
  ((infix_sl (infix_pl x y) z) = (infix_pl (infix_sl x z) (infix_sl y z))).
intros.
unfold infix_sl, infix_as, infix_pl.
field.
Qed.

(* Why3 goal *)
Lemma sub_div : forall (x:R) (y:R) (z:R), (~ (z = 0%R)) ->
  ((infix_sl (infix_mn x y) z) = (infix_mn (infix_sl x z) (infix_sl y z))).
intros.
unfold infix_sl, infix_as, infix_mn, infix_pl, prefix_mn.
field.
Qed.

(* Why3 goal *)
Lemma neg_div : forall (x:R) (y:R), (~ (y = 0%R)) -> ((infix_sl (prefix_mn x)
  y) = (prefix_mn (infix_sl x y))).
intros.
unfold infix_sl, infix_as, prefix_mn.
field.
Qed.

(* Why3 goal *)
Lemma assoc_mul_div : forall (x:R) (y:R) (z:R), (~ (z = 0%R)) ->
  ((infix_sl (infix_as x y) z) = (infix_as x (infix_sl y z))).
intros x y z _.
apply Rmult_assoc.
Qed.

(* Why3 goal *)
Lemma assoc_div_mul : forall (x:R) (y:R) (z:R), ((~ (y = 0%R)) /\
  ~ (z = 0%R)) -> ((infix_sl (infix_sl x y) z) = (infix_sl x (infix_as y
  z))).
intros x y z (Zy, Zz).
unfold infix_sl, infix_as, inv.
rewrite Rmult_assoc.
now rewrite Rinv_mult_distr.
Qed.

(* Why3 goal *)
Lemma assoc_div_div : forall (x:R) (y:R) (z:R), ((~ (y = 0%R)) /\
  ~ (z = 0%R)) -> ((infix_sl x (infix_sl y z)) = (infix_sl (infix_as x z)
  y)).
intros x y z (Zy, Zz).
unfold infix_sl, infix_as, inv.
field.
now split.
Qed.

(* Why3 goal *)
Lemma Refl : forall (x:R), (infix_lseq x x).
exact Rle_refl.
Qed.

(* Why3 goal *)
Lemma Trans : forall (x:R) (y:R) (z:R), (infix_lseq x y) -> ((infix_lseq y
  z) -> (infix_lseq x z)).
exact Rle_trans.
Qed.

(* Why3 goal *)
Lemma Antisymm : forall (x:R) (y:R), (infix_lseq x y) -> ((infix_lseq y x) ->
  (x = y)).
exact Rle_antisym.
Qed.

(* Why3 goal *)
Lemma Total : forall (x:R) (y:R), (infix_lseq x y) \/ (infix_lseq y x).
intros x y.
destruct (Rle_or_lt x y) as [H|H].
now left.
right.
now apply Rlt_le.
Qed.

(* Why3 goal *)
Lemma ZeroLessOne : (infix_lseq 0%R 1%R).
exact Rle_0_1.
Qed.

(* Why3 goal *)
Lemma CompatOrderAdd : forall (x:R) (y:R) (z:R), (infix_lseq x y) ->
  (infix_lseq (infix_pl x z) (infix_pl y z)).
intros x y z.
exact (Rplus_le_compat_r z x y).
Qed.

(* Why3 goal *)
Lemma CompatOrderMult : forall (x:R) (y:R) (z:R), (infix_lseq x y) ->
  ((infix_lseq 0%R z) -> (infix_lseq (infix_as x z) (infix_as y z))).
intros x y z H Zz.
now apply Rmult_le_compat_r.
Qed.


