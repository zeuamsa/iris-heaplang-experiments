(** This file explores the relation between two kinds of logically atomic specs:
TaDA-style and HoCAP-style.  The key difference between these specs is as follows:
- TaDA-style specs require the client to prove a mask-changing view shift
  which, at the linearization point, gets used to access the atomic
  precondition. The client can open invariants to prove this view shift. The
  library then works with this precondition, transforms it to the postcondition
  (which usually involves changing the abstract state), and gives that back to
  the client for a "closing" mask-changing view shift, where the client can
  close the invariants again.
  The flow of resources at the lineraization point is "client gives resources to
  library; library gives altered resources back to client".
  A TaDA-style specs has an "atomic pre/postcondition", making them easy to
  relate to a sequential spec for the same kind of data structure.
- HoCAP-style specs require the client to prove a non-mask-changing view shift
  which may assume as an assumption the "old" abstract state of the library, and
  has to produce the "new" abstract state. Unlike TaDA-style specs,
  it is up to the *client* to change the abstract state to match the current
  operation.
  The flow of resources at the linearization point is "library gives resources
  to client; client gives altered resources back to library".
  This pattern also does not really have a notion of "atomic pre/postcondition"
  (it might be tempting to use this term for the LHS of the view shift, but note
  that the LHS is *covariant*, not contravariant like preconditions should be).
  The relation between a sequential specification and its atomic counterpart is
  more complex with HoCAP-style specs than it is with TaDA-style specs.
  HoCAP-style specs come in two variants: "authoritative" and "predicate".
  Both can be found below.

One consequence of this difference is that there are some specs where the HoCAP
style simply does not work: one cannot use the HoCAP style to prove a spec about
the abstraction of *another library*.  See
<https://people.mpi-sws.org/~jung/iris/logatom-talk-2019.pdf#page=89> and
[heap_lang.lib.increment] in the Iris repository for an example of this.
(When unqualified, "logically atomic" in Iris usually means TaDA-style.)

For libraries that only state atomic transitions for their own abstraction, the
two styles are equivalent, as this file shows: we give two different HoCAP-style
specs (the "authoritative" variant, which is closer to the original HoCAP paper,
and the "predicate" variant which is somewhat simpler), and we show them both
equivalent with each other and with the TaDA-style spec. *)


From stdpp Require Import namespaces.
From iris.algebra Require Import excl auth list.
From iris.base_logic.lib Require Import invariants.
From iris.program_logic Require Import atomic.
From iris.heap_lang Require Import proofmode notation atomic_heap.
From iris_examples.logatom.elimination_stack Require spec.
From iris.prelude Require Import options.

Module tada := elimination_stack.spec.

(** A general HoCAP-style interface for a stack, modeled after the spec in
[hocap/abstract_bag.v]. This style is similar to what was done in the HoCAP
paper, except that we avoid unnecessary quantification over propositions and
instead make use of viewn shifts *without* a persistence modality (in HoCAP,
view shifts are always persistent). This does not change the meaning of the
spec, it just makes it easier to use in Coq.
We might call this "Iris-adjusted HoCAP-style specs".

There are two differences to the [abstract_bag] spec:
- We split [bag_contents] into an authoritative part and a fragment as this
  slightly strengthens the spec ([stack_content_frag_exclusive] is added),
- We also slightly weaken the spec by adding [make_laterable], which is needed
  because Iris' TaDA-style logically atomic triples can only capture laterable
  resources, which is needed when implementing e.g. the elimination stack on top
  of an abstract logically atomic heap.

This spec uses the "authoritative" variant of HoCAP specs.
See below for the "predicate"-based alternative *)
Module hocap_auth.
Record stack {??} `{!heapGS ??} := AtomicStack {
  (* -- operations -- *)
  new_stack : val;
  push : val;
  pop : val;
  (* -- other data -- *)
  name : Type;
  name_eqdec : EqDecision name;
  name_countable : Countable name;
  (* -- predicates -- *)
  is_stack (N : namespace) (??s : name) (v : val) : iProp ??;
  stack_content_frag (??s : name) (l : list val) : iProp ??;
  stack_content_auth (??s : name) (l : list val) : iProp ??;
  (* -- predicate properties -- *)
  is_stack_persistent N ??s v : Persistent (is_stack N ??s v);
  stack_content_frag_timeless ??s l : Timeless (stack_content_frag ??s l);
  stack_content_auth_timeless ??s l : Timeless (stack_content_auth ??s l);
  stack_content_frag_exclusive ??s l1 l2 :
    stack_content_frag ??s l1 -??? stack_content_frag ??s l2 -??? False;
  stack_content_auth_exclusive ??s l1 l2 :
    stack_content_auth ??s l1 -??? stack_content_auth ??s l2 -??? False;
  stack_content_agree ??s l1 l2 :
    stack_content_frag ??s l1 -??? stack_content_auth ??s l2 -??? ???l1 = l2???;
  stack_content_update ??s l l' :
    stack_content_frag ??s l -???
    stack_content_auth ??s l -???
    |==> stack_content_frag ??s l' ??? stack_content_auth ??s l';
  (* -- operation specs -- *)
  new_stack_spec N :
    {{{ True }}} new_stack #() {{{ ??s s, RET s; is_stack N ??s s ??? stack_content_frag ??s [] }}};
  push_spec N ??s s (v : val) (?? : val ??? iProp ??) :
    is_stack N ??s s -???
    make_laterable (??? l, stack_content_auth ??s l ={?????????N}=??? stack_content_auth ??s (v::l) ??? ?? #()) -???
    WP push s v {{ ?? }};
  pop_spec N ??s s (?? : val ??? iProp ??) :
    is_stack N ??s s -???
    make_laterable (??? l, stack_content_auth ??s l ={?????????N}=???
          match l with [] => stack_content_auth ??s [] ??? ?? NONEV
                | v :: l' => stack_content_auth ??s l' ??? ?? (SOMEV v) end) -???
    WP pop s {{ ?? }};
}.
Global Arguments stack _ {_}.

Global Existing Instances
  is_stack_persistent stack_content_frag_timeless stack_content_auth_timeless
  name_eqdec name_countable.

End hocap_auth.

(** A general HoCAP-style interface for a stack, with a user-defined predicate
instead of an authoritative element, thereby departing even further from the
HoCAP paper.  This style matches [concurrent_stacks.spec]. *)
Module hocap_pred.
Record stack {??} `{!heapGS ??} := AtomicStack {
  (* -- operations -- *)
  new_stack : val;
  push : val;
  pop : val;
  (* -- predicates -- *)
  is_stack (N : namespace) (v : val) (P : list val ??? iProp ??) : iProp ??;
  (* -- predicate properties -- *)
  is_stack_persistent N P v : Persistent (is_stack N P v);
  is_stack_ne N v n : Proper (pointwise_relation _ (dist n) ==> dist n) (is_stack N v);
  (* -- operation specs -- *)
  new_stack_spec N P :
    {{{ ??? P [] }}} new_stack #() {{{ s, RET s; is_stack N s P }}};
  push_spec N s P (v : val) (?? : val ??? iProp ??) :
    is_stack N s P -???
    make_laterable (??? l, ??? P l ={?????????N}=??? ??? P (v::l) ??? ?? #()) -???
    WP push s v {{ ?? }};
  pop_spec N s P (?? : val ??? iProp ??) :
    is_stack N s P -???
    make_laterable (??? l, ??? P l ={?????????N}=???
          match l with [] => ??? P [] ??? ?? NONEV
                | v :: l' => ??? P l' ??? ?? (SOMEV v) end) -???
    WP pop s {{ ?? }};
}.
Global Arguments stack _ {_}.

Global Existing Instances is_stack_persistent.

End hocap_pred.

(** Now we show the following three implications:
- hocap_auth implies tada.
- tada implies hocap_pred.
- hocap_pred implies hocap_auth.
*)


(** From a HoCAP-"auth" stack we can directly implement the TaDA interface.

Roughly:
tada.is_stack := hocap_auth.is_stack
tada.stack_content := hocap_auth.stack_content_frag
*)
Section hocap_auth_tada.
  Context `{!heapGS ??} (stack: hocap_auth.stack ??).

  Lemma tada_push N ??s s (v : val) :
    stack.(hocap_auth.is_stack) N ??s s -???
    <<< ??? l : list val, stack.(hocap_auth.stack_content_frag) ??s l >>>
      stack.(hocap_auth.push) s v @ ???N
    <<< stack.(hocap_auth.stack_content_frag) ??s (v::l), RET #() >>>.
  Proof.
    iIntros "Hstack". iIntros (??) "H??".
    iApply (hocap_auth.push_spec with "Hstack").
    iApply (make_laterable_intro with "[] H??"). iIntros "!# H??" (l) "Hauth".
    iMod "H??" as (l') "[Hfrag [_ Hclose]]".
    iDestruct (hocap_auth.stack_content_agree with "Hfrag Hauth") as %->.
    iMod (hocap_auth.stack_content_update with "Hfrag Hauth") as "[Hfrag $]".
    iMod ("Hclose" with "Hfrag") as "H??". done.
  Qed.

  Lemma tada_pop N ??s (s : val) :
    stack.(hocap_auth.is_stack) N ??s s -???
    <<< ??? l : list val, stack.(hocap_auth.stack_content_frag) ??s l >>>
      stack.(hocap_auth.pop) s @ ???N
    <<< stack.(hocap_auth.stack_content_frag) ??s (tail l),
        RET match l with [] => NONEV | v :: _ => SOMEV v end >>>.
  Proof.
    iIntros "Hstack". iIntros (??) "H??".
    iApply (hocap_auth.pop_spec with "Hstack").
    iApply (make_laterable_intro with "[] H??"). iIntros "!# H??" (l) "Hauth".
    iMod "H??" as (l') "[Hfrag [_ Hclose]]".
    iDestruct (hocap_auth.stack_content_agree with "Hfrag Hauth") as %->.
    destruct l;
    iMod (hocap_auth.stack_content_update with "Hfrag Hauth") as "[Hfrag $]";
    iMod ("Hclose" with "Hfrag") as "H??"; done.
  Qed.

  Definition hocap_auth_tada : tada.atomic_stack ?? :=
    {| tada.new_stack_spec := stack.(hocap_auth.new_stack_spec);
       tada.push_spec := tada_push;
       tada.pop_spec := tada_pop;
       tada.stack_content_exclusive := stack.(hocap_auth.stack_content_frag_exclusive) |}.

End hocap_auth_tada.

(** From a TaDA-style stack, we can implement a HoCAP-"pred" stack by
 adding an invariant.

Roughly:
hocap_pred.is_stack P := tada.is_stack * inv (??? l, tada.stack_content l * P l)
*)
Section tada_hocap_pred.
  Context `{!heapGS ??} (stack: tada.atomic_stack ??).
  Implicit Type P : list val ??? iProp ??.

  Definition hocap_pred_is_stack N v P : iProp ?? :=
    (??? ??s, stack.(tada.is_stack) (N .@ "stack") ??s v ???
     inv (N .@ "wrapper") (??? l, stack.(tada.stack_content) ??s l ??? P l))%I.

  Instance hocap_pred_is_stack_ne N v n :
    Proper (pointwise_relation _ (dist n) ==> dist n) (hocap_pred_is_stack N v).
  Proof. solve_proper. Qed.

  Lemma hocap_pred_new_stack N P :
    {{{ ??? P [] }}}
      stack.(tada.new_stack) #()
    {{{ s, RET s; hocap_pred_is_stack N s P }}}.
  Proof.
    iIntros (??) "HP H??". iApply wp_fupd. iApply tada.new_stack_spec; first done.
    iIntros "!>" (??s s) "[Hstack Hcont]".
    iApply "H??". rewrite /hocap_pred_is_stack. iExists ??s. iFrame.
    iApply inv_alloc. eauto with iFrame.
  Qed.

  Lemma hocap_pred_push N s P (v : val) (?? : val ??? iProp ??) :
    hocap_pred_is_stack N s P -???
    make_laterable (??? l, ??? P l ={?????????N}=??? ??? P (v::l) ??? ?? #()) -???
    WP stack.(tada.push) s v {{ ?? }}.
  Proof.
    iIntros "#Hstack Hupd". iDestruct "Hstack" as (??s) "[Hstack Hinv]".
    awp_apply (tada.push_spec with "Hstack").
    iInv "Hinv" as (l) "[>Hcont HP]".
    iAaccIntro with "Hcont"; first by eauto 10 with iFrame.
    iIntros "Hcont".
    iMod (fupd_mask_subseteq (??? ??? ???N)) as "Hclose"; first solve_ndisj.
    iMod (make_laterable_elim with "Hupd") as "Hupd".
    iMod ("Hupd" with "HP") as "[HP H??]".
    iMod "Hclose" as "_". iIntros "!>".
    eauto with iFrame.
  Qed.

  Lemma hocap_pred_pop N s P (?? : val ??? iProp ??) :
    hocap_pred_is_stack N s P -???
    make_laterable (??? l, ??? P l ={?????????N}=???
          match l with [] => ??? P [] ??? ?? NONEV
                | v :: l' => ??? P l' ??? ?? (SOMEV v) end) -???
    WP stack.(tada.pop) s {{ ?? }}.
  Proof.
    iIntros "#Hstack Hupd". iDestruct "Hstack" as (??s) "[Hstack Hinv]".
    awp_apply (tada.pop_spec with "Hstack").
    iInv "Hinv" as (l) "[>Hcont HP]".
    iAaccIntro with "Hcont"; first by eauto 10 with iFrame.
    iIntros "Hcont". destruct l.
    - iMod (fupd_mask_subseteq (??? ??? ???N)) as "Hclose"; first solve_ndisj.
      iMod (make_laterable_elim with "Hupd") as "Hupd".
      iMod ("Hupd" with "HP") as "[HP H??]".
      iMod "Hclose" as "_". iIntros "!>"; eauto with iFrame.
    - iMod (fupd_mask_subseteq (??? ??? ???N))  as "Hclose"; first solve_ndisj.
      iMod (make_laterable_elim with "Hupd") as "Hupd".
      iMod ("Hupd" with "HP") as "[HP H??]".
      iMod "Hclose" as "_". iIntros "!>"; eauto with iFrame.
  Qed.

  Program Definition tada_hocap_pred : hocap_pred.stack ?? :=
    {| hocap_pred.new_stack_spec := hocap_pred_new_stack;
       hocap_pred.push_spec := hocap_pred_push;
       hocap_pred.pop_spec := hocap_pred_pop |}.

End tada_hocap_pred.

(** From a hocap_pred stack, we can implement a hocap_auth stack by adding an
auth.

Roughly:
hocap_auth.is_stack := hocap_pred.is_stack (?? l, auth l)
hocap_auth.stack_content_auth := auth
hocap_auth.stack_content_frag := frag
*)

(** The CMRA & functor we need. *)
Class hocapG ?? := HocapG {
  hocap_stateG :> inG ?? (authR (optionUR $ exclR (listO valO)));
}.
Definition hocap?? : gFunctors :=
  #[GFunctor (exclR unitO); GFunctor (authR (optionUR $ exclR (listO valO)))].

Global Instance subG_hocap?? {??} : subG hocap?? ?? ??? hocapG ??.
Proof. solve_inG. Qed.

Section hocap_pred_auth.
  Context `{!heapGS ??} `{!hocapG ??} (stack: hocap_pred.stack ??).

  Definition hocap_name : Type := gname.
  Implicit Types ??s : hocap_name.

  Definition hocap_auth_stack_content_auth ??s l : iProp ?? := own ??s (??? Excl' l).
  Definition hocap_auth_stack_content_frag ??s l : iProp ?? := own ??s (??? Excl' l).

  Definition hocap_auth_is_stack N ??s v : iProp ?? :=
    stack.(hocap_pred.is_stack) N v (hocap_auth_stack_content_auth ??s).

  Lemma hocap_auth_new_stack N :
    {{{ True }}}
      stack.(hocap_pred.new_stack) #()
    {{{ ??s s, RET s; hocap_auth_is_stack N ??s s ??? hocap_auth_stack_content_frag ??s [] }}}.
  Proof.
    iIntros (??) "_ H??". iApply wp_fupd.
    iMod (own_alloc (??? Excl' [] ??? ??? Excl' [])) as (??s) "[Hs??? Hs???]".
    { apply auth_both_valid_discrete. split; done. }
    iApply (hocap_pred.new_stack_spec _ _ (hocap_auth_stack_content_auth ??s) with "[Hs??? //]").
    iIntros "!>" (s) "#Hstack". iApply "H??".
    rewrite /hocap_auth_is_stack. by iFrame.
  Qed.

  Lemma hocap_auth_push N ??s s (v : val) (?? : val ??? iProp ??) :
    hocap_auth_is_stack N ??s s -???
    make_laterable (??? l, hocap_auth_stack_content_auth ??s l ={?????????N}=???
      hocap_auth_stack_content_auth ??s (v::l) ??? ?? #()) -???
    WP stack.(hocap_pred.push) s v {{ ?? }}.
  Proof.
    iIntros "#Hstack Hupd". iApply (hocap_pred.push_spec with "Hstack").
    (* FIXME can we have proof mode support for make_laterable_intro? *)
    iApply (laterable.make_laterable_intro with "[] Hupd"); iIntros "!# Hupd".
    iIntros (l) ">Hs".
    (* FIXME can we have proof mode support for make_laterable_elim? *)
    iDestruct (make_laterable_elim with "Hupd") as ">Hupd".
    iMod ("Hupd" with "Hs") as "[Hs $]". done.
  Qed.

  Lemma hocap_auth_pop N ??s s (?? : val ??? iProp ??) :
    hocap_auth_is_stack N ??s s -???
    make_laterable (??? l, hocap_auth_stack_content_auth ??s l ={?????????N}=???
          match l with [] => hocap_auth_stack_content_auth ??s [] ??? ?? NONEV
                | v :: l' => hocap_auth_stack_content_auth ??s l' ??? ?? (SOMEV v) end) -???
    WP stack.(hocap_pred.pop) s {{ ?? }}.
  Proof.
    iIntros "#Hstack Hupd". iApply (hocap_pred.pop_spec with "Hstack").
    iApply (laterable.make_laterable_intro with "[] Hupd"); iIntros "!# Hupd".
    iIntros (l) ">Hs".
    iDestruct (make_laterable_elim with "Hupd") as ">Hupd".
    iMod ("Hupd" with "Hs") as "Hs??".
    iModIntro. destruct l; iDestruct "Hs??" as "[Hs H??]"; eauto with iFrame.
  Qed.

  Program Definition hocap_pred_auth : hocap_auth.stack ?? :=
    {| hocap_auth.new_stack_spec := hocap_auth_new_stack;
       hocap_auth.push_spec := hocap_auth_push;
       hocap_auth.pop_spec := hocap_auth_pop |}.
  Next Obligation.
    iIntros (???) "Hf1 Hf2".
    iDestruct (own_valid_2 with "Hf1 Hf2") as %[]%auth_frag_op_valid_1.
  Qed.
  Next Obligation.
    iIntros (???) "Ha1 Ha2".
    iDestruct (own_valid_2 with "Ha1 Ha2") as %[]%auth_auth_op_valid.
  Qed.
  Next Obligation.
    iIntros (???) "Hf Ha". iDestruct (own_valid_2 with "Ha Hf") as
      %[->%Excl_included%leibniz_equiv _]%auth_both_valid_discrete. done.
  Qed.
  Next Obligation.
    iIntros (???) "Hf Ha". iMod (own_update_2 with "Ha Hf") as "[? ?]".
    { eapply auth_update, option_local_update, (exclusive_local_update _ (Excl _)). done. }
    by iFrame.
  Qed.

End hocap_pred_auth.


(** Show that our way of writing the [pop_spec] is equivalent to what is done in
[concurrent_stack.spec].  IOW, the conjunction-vs-match doesn't matter. *)
Section pop_equiv.
  Context `{invGS ??} (T : Type).

  Lemma pop_equiv E (I : list T ??? iProp ??) (??emp : iProp ??) (??ret : T ??? iProp ??) :
    (??? l, I l ={E}=???
       match l with [] => I [] ??? ??emp | v :: l' => I l' ??? ??ret v end)
    ??????
    (??? v vs, I (v :: vs) ={E}=??? ??ret v ??? I vs)
    ??? (I [] ={E}=??? ??emp ??? I []).
  Proof.
    iSplit.
    - iIntros "H??". iSplit.
      + iIntros (??) "HI". iMod ("H??" with "HI") as "[$ $]". done.
      + iIntros "HI". iMod ("H??" with "HI") as "[$ $]". done.
    - iIntros "H??" (l) "HI". destruct l; rewrite [(I _ ??? _)%I]bi.sep_comm; by iApply "H??".
  Qed.
End pop_equiv.
