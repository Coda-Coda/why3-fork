(* This file is generated by Why3's Coq driver *)
(* Beware! Only edit allowed sections below    *)
Require Import ZArith.
Require Import Rbase.
Require int.Int.
Definition implb(x:bool) (y:bool): bool := match (x,
  y) with
  | (true, false) => false
  | (_, _) => true
  end.

Parameter pow2: Z -> Z.


Axiom Power_0 : ((pow2 0%Z) = 1%Z).

Axiom Power_s : forall (n:Z), (0%Z <= n)%Z ->
  ((pow2 (n + 1%Z)%Z) = (2%Z * (pow2 n))%Z).

Axiom Power_1 : ((pow2 1%Z) = 2%Z).

Axiom Power_sum : forall (n:Z) (m:Z), ((0%Z <= n)%Z /\ (0%Z <= m)%Z) ->
  ((pow2 (n + m)%Z) = ((pow2 n) * (pow2 m))%Z).

Axiom pow2_0 : ((pow2 0%Z) = 1%Z).

Axiom pow2_1 : ((pow2 1%Z) = 2%Z).

Axiom pow2_2 : ((pow2 2%Z) = 4%Z).

Axiom pow2_3 : ((pow2 3%Z) = 8%Z).

Axiom pow2_4 : ((pow2 4%Z) = 16%Z).

Axiom pow2_5 : ((pow2 5%Z) = 32%Z).

Axiom pow2_6 : ((pow2 6%Z) = 64%Z).

Axiom pow2_7 : ((pow2 7%Z) = 128%Z).

Axiom pow2_8 : ((pow2 8%Z) = 256%Z).

Axiom pow2_9 : ((pow2 9%Z) = 512%Z).

Axiom pow2_10 : ((pow2 10%Z) = 1024%Z).

Axiom pow2_11 : ((pow2 11%Z) = 2048%Z).

Axiom pow2_12 : ((pow2 12%Z) = 4096%Z).

Axiom pow2_13 : ((pow2 13%Z) = 8192%Z).

Axiom pow2_14 : ((pow2 14%Z) = 16384%Z).

Axiom pow2_15 : ((pow2 15%Z) = 32768%Z).

Axiom pow2_16 : ((pow2 16%Z) = 65536%Z).

Axiom pow2_17 : ((pow2 17%Z) = 131072%Z).

Axiom pow2_18 : ((pow2 18%Z) = 262144%Z).

Axiom pow2_19 : ((pow2 19%Z) = 524288%Z).

Axiom pow2_20 : ((pow2 20%Z) = 1048576%Z).

Axiom pow2_21 : ((pow2 21%Z) = 2097152%Z).

Axiom pow2_22 : ((pow2 22%Z) = 4194304%Z).

Axiom pow2_23 : ((pow2 23%Z) = 8388608%Z).

Axiom pow2_24 : ((pow2 24%Z) = 16777216%Z).

Axiom pow2_25 : ((pow2 25%Z) = 33554432%Z).

Axiom pow2_26 : ((pow2 26%Z) = 67108864%Z).

Axiom pow2_27 : ((pow2 27%Z) = 134217728%Z).

Axiom pow2_28 : ((pow2 28%Z) = 268435456%Z).

Axiom pow2_29 : ((pow2 29%Z) = 536870912%Z).

Axiom pow2_30 : ((pow2 30%Z) = 1073741824%Z).

Axiom pow2_31 : ((pow2 31%Z) = 2147483648%Z).

Axiom pow2_32 : ((pow2 32%Z) = 4294967296%Z).

Axiom pow2_33 : ((pow2 33%Z) = 8589934592%Z).

Axiom pow2_34 : ((pow2 34%Z) = 17179869184%Z).

Axiom pow2_35 : ((pow2 35%Z) = 34359738368%Z).

Axiom pow2_36 : ((pow2 36%Z) = 68719476736%Z).

Axiom pow2_37 : ((pow2 37%Z) = 137438953472%Z).

Axiom pow2_38 : ((pow2 38%Z) = 274877906944%Z).

Axiom pow2_39 : ((pow2 39%Z) = 549755813888%Z).

Axiom pow2_40 : ((pow2 40%Z) = 1099511627776%Z).

Axiom pow2_41 : ((pow2 41%Z) = 2199023255552%Z).

Axiom pow2_42 : ((pow2 42%Z) = 4398046511104%Z).

Axiom pow2_43 : ((pow2 43%Z) = 8796093022208%Z).

Axiom pow2_44 : ((pow2 44%Z) = 17592186044416%Z).

Axiom pow2_45 : ((pow2 45%Z) = 35184372088832%Z).

Axiom pow2_46 : ((pow2 46%Z) = 70368744177664%Z).

Axiom pow2_47 : ((pow2 47%Z) = 140737488355328%Z).

Axiom pow2_48 : ((pow2 48%Z) = 281474976710656%Z).

Axiom pow2_49 : ((pow2 49%Z) = 562949953421312%Z).

Axiom pow2_50 : ((pow2 50%Z) = 1125899906842624%Z).

Axiom pow2_51 : ((pow2 51%Z) = 2251799813685248%Z).

Axiom pow2_52 : ((pow2 52%Z) = 4503599627370496%Z).

Axiom pow2_53 : ((pow2 53%Z) = 9007199254740992%Z).

Axiom pow2_54 : ((pow2 54%Z) = 18014398509481984%Z).

Axiom pow2_55 : ((pow2 55%Z) = 36028797018963968%Z).

Axiom pow2_56 : ((pow2 56%Z) = 72057594037927936%Z).

Axiom pow2_57 : ((pow2 57%Z) = 144115188075855872%Z).

Axiom pow2_58 : ((pow2 58%Z) = 288230376151711744%Z).

Axiom pow2_59 : ((pow2 59%Z) = 576460752303423488%Z).

Axiom pow2_60 : ((pow2 60%Z) = 1152921504606846976%Z).

Axiom pow2_61 : ((pow2 61%Z) = 2305843009213693952%Z).

Axiom pow2_62 : ((pow2 62%Z) = 4611686018427387904%Z).

Axiom pow2_63 : ((pow2 63%Z) = 9223372036854775808%Z).

Parameter size: Z.


Parameter bv : Type.

Axiom size_positive : (1%Z <  size)%Z.

Parameter nth: bv -> Z -> bool.


Parameter bvzero: bv.


Axiom Nth_zero : forall (n:Z), ((0%Z <= n)%Z /\ (n <  size)%Z) ->
  ((nth bvzero n) = false).

Parameter bvone: bv.


Axiom Nth_one : forall (n:Z), ((0%Z <= n)%Z /\ (n <  size)%Z) -> ((nth bvone
  n) = true).

Definition eq(v1:bv) (v2:bv): Prop := forall (n:Z), ((0%Z <= n)%Z /\
  (n <  size)%Z) -> ((nth v1 n) = (nth v2 n)).

Axiom extensionality : forall (v1:bv) (v2:bv), (eq v1 v2) -> (v1 = v2).

Parameter bw_and: bv -> bv -> bv.


Axiom Nth_bw_and : forall (v1:bv) (v2:bv) (n:Z), ((0%Z <= n)%Z /\
  (n <  size)%Z) -> ((nth (bw_and v1 v2) n) = (andb (nth v1 n) (nth v2 n))).

Parameter bw_or: bv -> bv -> bv.


Axiom Nth_bw_or : forall (v1:bv) (v2:bv) (n:Z), ((0%Z <= n)%Z /\
  (n <  size)%Z) -> ((nth (bw_or v1 v2) n) = (orb (nth v1 n) (nth v2 n))).

Parameter bw_xor: bv -> bv -> bv.


Axiom Nth_bw_xor : forall (v1:bv) (v2:bv) (n:Z), ((0%Z <= n)%Z /\
  (n <  size)%Z) -> ((nth (bw_xor v1 v2) n) = (xorb (nth v1 n) (nth v2 n))).

Axiom Nth_bw_xor_v1true : forall (v1:bv) (v2:bv) (n:Z), (((0%Z <= n)%Z /\
  (n <  size)%Z) /\ ((nth v1 n) = true)) -> ((nth (bw_xor v1 v2)
  n) = (negb (nth v2 n))).

Axiom Nth_bw_xor_v1false : forall (v1:bv) (v2:bv) (n:Z), (((0%Z <= n)%Z /\
  (n <  size)%Z) /\ ((nth v1 n) = false)) -> ((nth (bw_xor v1 v2)
  n) = (nth v2 n)).

Axiom Nth_bw_xor_v2true : forall (v1:bv) (v2:bv) (n:Z), (((0%Z <= n)%Z /\
  (n <  size)%Z) /\ ((nth v2 n) = true)) -> ((nth (bw_xor v1 v2)
  n) = (negb (nth v1 n))).

Axiom Nth_bw_xor_v2false : forall (v1:bv) (v2:bv) (n:Z), (((0%Z <= n)%Z /\
  (n <  size)%Z) /\ ((nth v2 n) = false)) -> ((nth (bw_xor v1 v2)
  n) = (nth v1 n)).

Parameter bw_not: bv -> bv.


Axiom Nth_bw_not : forall (v:bv) (n:Z), ((0%Z <= n)%Z /\ (n <  size)%Z) ->
  ((nth (bw_not v) n) = (negb (nth v n))).

Parameter lsr: bv -> Z -> bv.


Axiom lsr_nth_low : forall (b:bv) (n:Z) (s:Z), (((0%Z <= n)%Z /\
  (n <  size)%Z) /\ (((0%Z <= s)%Z /\ (s <  size)%Z) /\
  ((n + s)%Z <  size)%Z)) -> ((nth (lsr b s) n) = (nth b (n + s)%Z)).

Axiom lsr_nth_high : forall (b:bv) (n:Z) (s:Z), (((0%Z <= n)%Z /\
  (n <  size)%Z) /\ (((0%Z <= s)%Z /\ (s <  size)%Z) /\
  (size <= (n + s)%Z)%Z)) -> ((nth (lsr b s) n) = false).

Parameter asr: bv -> Z -> bv.


Axiom asr_nth_low : forall (b:bv) (n:Z) (s:Z), ((0%Z <= n)%Z /\
  (n <  size)%Z) -> ((0%Z <= s)%Z -> (((n + s)%Z <  size)%Z -> ((nth (asr b
  s) n) = (nth b (n + s)%Z)))).

Axiom asr_nth_high : forall (b:bv) (n:Z) (s:Z), ((0%Z <= n)%Z /\
  (n <  size)%Z) -> ((0%Z <= s)%Z -> ((size <= (n + s)%Z)%Z -> ((nth (asr b
  s) n) = (nth b (size - 1%Z)%Z)))).

Parameter lsl: bv -> Z -> bv.


Axiom lsl_nth_high : forall (b:bv) (n:Z) (s:Z), ((0%Z <= n)%Z /\
  (n <  size)%Z) -> ((0%Z <= s)%Z -> ((0%Z <= (n - s)%Z)%Z -> ((nth (lsl b s)
  n) = (nth b (n - s)%Z)))).

Axiom lsl_nth_low : forall (b:bv) (n:Z) (s:Z), ((0%Z <= n)%Z /\
  (n <  size)%Z) -> ((0%Z <= s)%Z -> (((n - s)%Z <  0%Z)%Z -> ((nth (lsl b s)
  n) = false))).

Parameter to_nat_sub: bv -> Z -> Z -> Z.


Axiom to_nat_sub_zero : forall (b:bv) (j:Z) (i:Z), (((0%Z <= i)%Z /\
  (i <= j)%Z) /\ (j <  size)%Z) -> (((nth b j) = false) -> ((to_nat_sub b j
  i) = (to_nat_sub b (j - 1%Z)%Z i))).

Axiom to_nat_sub_one : forall (b:bv) (j:Z) (i:Z), (((0%Z <= i)%Z /\
  (i <= j)%Z) /\ (j <  size)%Z) -> (((nth b j) = true) -> ((to_nat_sub b j
  i) = ((pow2 (j - i)%Z) + (to_nat_sub b (j - 1%Z)%Z i))%Z)).

Axiom to_nat_sub_high : forall (b:bv) (j:Z) (i:Z), (j <  i)%Z ->
  ((to_nat_sub b j i) = 0%Z).

Axiom to_nat_of_zero2 : forall (b:bv) (i:Z) (j:Z), (((j <  size)%Z /\
  (i <= j)%Z) /\ (0%Z <= i)%Z) -> ((forall (k:Z), ((k <= j)%Z /\
  (i <  k)%Z) -> ((nth b k) = false)) -> ((to_nat_sub b j
  0%Z) = (to_nat_sub b i 0%Z))).

(* YOU MAY EDIT THE CONTEXT BELOW *)

(* DO NOT EDIT BELOW *)

Theorem to_nat_of_zero : forall (b:bv) (i:Z) (j:Z), ((j <  size)%Z /\
  (0%Z <= i)%Z) -> ((forall (k:Z), ((k <= j)%Z /\ (i <= k)%Z) -> ((nth b
  k) = false)) -> ((to_nat_sub b j i) = 0%Z)).
(* YOU MAY EDIT THE PROOF BELOW *)
Open Scope Z_scope.
intros b i j Hij.
cut(j<size).
apply Zlt_lower_bound_ind with (z:=i)
                    (P:= fun j=>  j < size ->
(forall k : Z, k <= j /\ i <= k -> nth b k = false) -> to_nat_sub b j i = 0).

(*apply Zlt_lower_bound_ind with (z:=i)
                    (P:= fun j=> (forall k : Z, (k <= j)%Z /\ (i <= k)%Z -> nth b k = false) ->
to_nat_sub b j i = 0%Z).
*)

intros x Hind Hxi Hxsize.
assert (h: (i=x \/ i<x)) by omega.
destruct h.
subst x;auto.
intro Hbits.
rewrite to_nat_sub_zero;auto with zarith.
rewrite to_nat_sub_high;auto with zarith.
intro.
rewrite to_nat_sub_zero;auto with zarith.
destruct Hij.
destruct H.
exact H1.
destruct Hij.
destruct H.
exact H.
Qed.
(* DO NOT EDIT BELOW *)


