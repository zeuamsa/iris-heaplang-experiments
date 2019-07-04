From iris.algebra Require Import excl auth agree frac list cmra csum.
From iris.base_logic.lib Require Export invariants.
From iris.program_logic Require Export atomic.
From iris.proofmode Require Import tactics.
From iris.heap_lang Require Import proofmode notation.
From iris_examples.logatom.rdcss Require Import spec.
Import uPred bi List Decidable.
Set Default Proof Using "Type".

(** Using prophecy variables with helping: implementing a simplified version of
   the restricted double-compare single-swap from "A Practical Multi-Word Compare-and-Swap Operation" by Harris et al. (DISC 2002)
 *)

(** * Implementation of the functions. *)

(* 1) l_m corresponds to the A location in the paper and can differ when helping another thread
      in the same RDCSS instance.
   2) l_n corresponds to the B location in the paper and identifies a single RDCSS instance.
   3) Values stored at the B location have type

      Val + Ref (Ref * Val * Val * Val * Proph)

      3.1) If the value is injL n, then no operation is on-going and the logical state is n.
      3.2) If the value is injR (Ref (l_m', m1', n1', n2', p)), then an operation is on-going
           with corresponding A location l_m'. The reference pointing to the tuple of values
           corresponds to the descriptor in the paper. We use the name l_descr for such a
           descriptor reference.
*)

(*
  new_rdcss(n) :=
    let l_n = ref ( ref(injL n) ) in
    ref l_n
 *)
Definition new_rdcss : val :=
  λ: "n",
    let: "l_n" := ref (InjL "n") in "l_n".

(*
  complete(l_descr, l_n) :=
    let (l_m, m1, n1, n2, p) := !l_descr in
    (* data = (l_m, m1, n1, n2, p) *)
    let l_ghost = ref #() in
    let n_new = (if !l_m = m1 then n1 else n2) in
      Resolve (CmpXchg l_n (InjR l_descr) (ref (InjL n_new))) p l_ghost ; #().
 *)
Definition complete : val :=
  λ: "l_descr" "l_n",
    let: "data" := !"l_descr" in
    (* data = (l_m, m1, n1, n2, p) *)
    let: "l_m" := Fst (Fst (Fst (Fst ("data")))) in
    let: "m1"  := Snd (Fst (Fst (Fst ("data")))) in
    let: "n1"  := Snd (Fst (Fst ("data"))) in
    let: "n2"  := Snd (Fst ("data")) in
    let: "p"   := Snd ("data") in
    let: "l_ghost" := ref #() in
    let: "n_new" := (if: !"l_m" = "m1" then "n2" else "n1") in
    Resolve (CmpXchg "l_n" (InjR "l_descr") (InjL "n_new")) "p" "l_ghost" ;; #().

(*
  get(l_n) :=
    match: !l_n with
    | injL n    => n
    | injR (l_descr) =>
        complete(l_descr, l_n);
        get(l_n)
    end.
 *)
Definition get : val :=
  rec: "get" "l_n" :=
    match: !"l_n" with
      InjL "n"    => "n"
    | InjR "l_descr" =>
        complete "l_descr" "l_n" ;;
        "get" "l_n"
    end.

(*
  rdcss(l_m, l_n, m1, n1, n2) :=
    let p := NewProph in
    let l_descr := ref (l_m, m1, n1, n2, p) in
    (rec: rdcss_inner()
       let (r, b) := CmpXchg(l_n, InjL n1, InjR l_descr) in
       match r with
         InjL n => 
           if b then
             complete(l_descr, l_n) ; n1
           else
             n
       | InjR l_descr_other =>
           complete(l_descr_other, l_n) ;
           rdcss_inner()
       end
     )()
*)
Definition rdcss: val :=
  λ: "l_m" "l_n" "m1" "n1" "n2",
    (* allocate fresh descriptor *)
    let: "p" := NewProph in
    let: "l_descr" := ref ("l_m", "m1", "n1", "n2", "p") in
    (* start rdcss computation with allocated descriptor *)
    ( rec: "rdcss_inner" "_" :=
        let: "r" := CmpXchg "l_n" (InjL "n1") (InjR "l_descr") in
        match: Fst "r" with
          InjL "n" =>
            (* non-descriptor value read, check if CAS was successful *)
            if: Snd "r" then
              (* CmpXchg was successful, finish operation *)
              complete "l_descr" "l_n" ;; "n1"
            else
              (* CmpXchg failed, hence we could linearize at the CmpXchg *)
              "n"
        | InjR "l_descr_other" =>
            (* a descriptor from a different operation was read, try to help and then restart *)
            complete "l_descr_other" "l_n" ;;
            "rdcss_inner" #()
        end
    ) #().

(** ** Proof setup *)

Definition valUR      := authR $ optionUR $ exclR valO.
Definition tokenUR    := exclR unitO.
Definition one_shotUR := csumR (exclR unitO) (agreeR unitO).

Class rdcssG Σ := RDCSSG {
                     rdcss_valG      :> inG Σ valUR;
                     rdcss_tokenG    :> inG Σ tokenUR;
                     rdcss_one_shotG :> inG Σ one_shotUR;
                   }.

Definition rdcssΣ : gFunctors :=
  #[GFunctor valUR; GFunctor tokenUR; GFunctor one_shotUR].

Instance subG_rdcssΣ {Σ} : subG rdcssΣ Σ → rdcssG Σ.
Proof. solve_inG. Qed.

Section rdcss.
  Context {Σ} `{!heapG Σ, !rdcssG Σ, !gcG Σ }.
  Context (N : namespace).

  Local Definition descrN   := N .@ "descr".
  Local Definition rdcssN := N .@ "rdcss".

  (** Updating and synchronizing the value RAs *)

  Lemma sync_values γ_n (n m : val) :
    own γ_n (● Excl' n) -∗ own γ_n (◯ Excl' m) -∗ ⌜n = m⌝.
  Proof.
    iIntros "H● H◯". iCombine "H●" "H◯" as "H". iDestruct (own_valid with "H") as "H".
      by iDestruct "H" as %[H%Excl_included%leibniz_equiv _]%auth_both_valid.
  Qed.

  Lemma update_value γ_n (n1 n2 m : val) :
    own γ_n (● Excl' n1) -∗ own γ_n (◯ Excl' n2) ==∗ own γ_n (● Excl' m) ∗ own γ_n (◯ Excl' m).
  Proof.
    iIntros "H● H◯". iCombine "H●" "H◯" as "H". rewrite -own_op. iApply (own_update with "H").
    by apply auth_update, option_local_update, exclusive_local_update.
  Qed.

  Definition rdcss_content (γ_n : gname) (n : val) := (own γ_n (◯ Excl' n))%I.

  (** Definition of the invariant *)

  Fixpoint val_to_some_loc (pvs : list (val * val)) : option loc :=
    match pvs with
    | ((_, #true)%V, LitV (LitLoc l)) :: _  => Some l
    | _                         :: vs => val_to_some_loc vs
    | _                               => None
    end.

  Inductive abstract_state : Set :=
  | Quiescent : val → abstract_state
  | Updating : loc → loc → val → val → val → proph_id → abstract_state.

  Definition state_to_val (s : abstract_state) : val :=
    match s with
    | Quiescent n => InjLV n
    | Updating l_descr l_m m1 n1 n2 p => InjRV #l_descr
    end.

  Definition own_token γ := (own γ (Excl ()))%I.

  Definition pending_state P (n1 : val) (proph_winner : option loc) l_ghost_winner (γ_n : gname) :=
    (P ∗ ⌜match proph_winner with None => True | Some l => l = l_ghost_winner end⌝ ∗ own γ_n (● Excl' n1))%I.

  (* After the prophecy said we are going to win the race, we commit and run the AU,
     switching from [pending] to [accepted]. *)
  Definition accepted_state Q (proph_winner : option loc) (l_ghost_winner : loc) :=
    (l_ghost_winner ↦{1/2} - ∗ match proph_winner with None => True | Some l => ⌜l = l_ghost_winner⌝ ∗ Q end)%I.

  (* The same thread then wins the CAS and moves from [accepted] to [done].
     Then, the [γ_t] token guards the transition to take out [Q].
     Remember that the thread winning the CAS might be just helping.  The token
     is owned by the thread whose request this is.
     In this state, [l_ghost_winner] serves as a token to make sure that
     only the CAS winner can transition to here, and owning half of [l_descr] serves as a
     "location" token to ensure there is no ABA going on. Notice how [rdcss_inv]
     owns *more than* half of its [l_descr] in the Updating state,
     which means we know that the [l_descr] there and here cannot be the same. *)
  Definition done_state Qn (l_descr l_ghost_winner : loc) (γ_t : gname) :=
    ((Qn ∨ own_token γ_t) ∗ l_ghost_winner ↦ - ∗ (l_descr ↦{1/2} -) )%I.

  (* Invariant expressing the descriptor protocol.
     We always need the [proph] in here so that failing threads coming late can
     always resolve their stuff.
     Moreover, we need a way for anyone who has observed the [done] state to
     prove that we will always remain [done]; that's what the one-shot token [γ_s] is for. *)
  Definition descr_inv P Q (p : proph_id) n (l_n l_descr l_ghost_winner : loc) γ_n γ_t γ_s : iProp Σ :=
    (∃ vs, proph p vs ∗
      (own γ_s (Cinl $ Excl ()) ∗
       (l_n ↦{1/2} InjRV #l_descr ∗ ( pending_state P n (val_to_some_loc vs) l_ghost_winner γ_n
        ∨ accepted_state (Q n) (val_to_some_loc vs) l_ghost_winner ))
       ∨ own γ_s (Cinr $ to_agree ()) ∗ done_state (Q n) l_descr l_ghost_winner γ_t))%I.

  Local Hint Extern 0 (environments.envs_entails _ (descr_inv _ _ _ _ _ _ _ _ _ _)) => unfold descr_inv.

  Definition pau P Q γ l_m m1 n1 n2 :=
    (▷ P -∗ ◇ AU << ∀ (m n : val), (gc_mapsto l_m m) ∗ rdcss_content γ n >> @ (⊤∖↑N)∖↑gcN, ∅
                 << (gc_mapsto l_m m) ∗ (rdcss_content γ (if (decide ((m = m1) ∧ (n = n1))) then n2 else n)),
                    COMM Q n >>)%I.

  Definition rdcss_inv γ_n l_n :=
    (∃ (s : abstract_state),
       l_n ↦{1/2} (state_to_val s) ∗
       match s with
       | Quiescent n =>
           (* (InjLV #n) = state_to_val (Quiescent n) *)
           (* In this state the CAS which expects to read (InjRV _) in
              [complete] fails always.*)
           l_n ↦{1/2} (InjLV n) ∗ own γ_n (● Excl' n)
        | Updating l_descr l_m m1 n1 n2 p =>
           ∃ q P Q l_ghost_winner γ_t γ_s,
             (* (InjRV #l_descr) = state_to_val (Updating l_descr l_m m1 n1 n2 p) *)
             (* There are two pieces of per-[descr]-protocol ghost state:
             - [γ_t] is a token owned by whoever created this protocol and used
               to get out the [Q] in the end.
             - [γ_s] reflects whether the protocol is [done] yet or not. *)
           (* We own *more than* half of [l_descr], which shows that this cannot
              be the [l_descr] of any [descr] protocol in the [done] state. *)
             ⌜val_is_unboxed m1⌝ ∗
             l_descr ↦{1/2 + q} (#l_m, m1, n1, n2, #p)%V ∗  
             inv descrN (descr_inv P Q p n1 l_n l_descr l_ghost_winner γ_n γ_t γ_s) ∗
             □ pau P Q γ_n l_m m1 n1 n2 ∗ is_gc_loc l_m
       end)%I.

  Local Hint Extern 0 (environments.envs_entails _ (rdcss_inv _ _)) => unfold rdcss_inv.

  Definition is_rdcss (γ_n : gname) (l_n: loc) :=
    (inv rdcssN (rdcss_inv γ_n l_n) ∧ gc_inv ∧ ⌜N ## gcN⌝)%I.

  Global Instance is_rdcss_persistent γ_n l_n: Persistent (is_rdcss γ_n l_n) := _.

  Global Instance rdcss_content_timeless γ_n n : Timeless (rdcss_content γ_n n) := _.
  
  Global Instance abstract_state_inhabited: Inhabited abstract_state := populate (Quiescent #0).

  Lemma rdcss_content_exclusive γ_n l_n_1 l_n_2 :
    rdcss_content γ_n l_n_1 -∗ rdcss_content γ_n l_n_2 -∗ False.
  Proof.
    iIntros "Hn1 Hn2". iDestruct (own_valid_2 with "Hn1 Hn2") as %?.
    done.
  Qed.

  (** A few more helper lemmas that will come up later *)

  Lemma mapsto_valid_3 l v1 v2 q :
    l ↦ v1 -∗ l ↦{q} v2 -∗ ⌜False⌝.
  Proof.
    iIntros "Hl1 Hl2". iDestruct (mapsto_valid_2 with "Hl1 Hl2") as %Hv.
    apply (iffLR (frac_valid' _)) in Hv. by apply Qp_not_plus_q_ge_1 in Hv.
  Qed.

  (** Once a [descr] protocol is [done] (as reflected by the [γ_s] token here),
      we can at any later point in time extract the [Q]. *)
  Lemma state_done_extract_Q P Q p n l_n l_descr l_ghost γ_n γ_t γ_s :
    inv descrN (descr_inv P Q p n l_n l_descr l_ghost γ_n γ_t γ_s) -∗
    own γ_s (Cinr (to_agree ())) -∗
    □(own_token γ_t ={⊤}=∗ ▷ (Q n)).
  Proof.
    iIntros "#Hinv #Hs !# Ht".
    iInv descrN as (vs) "(Hp & [NotDone | Done])".
    * (* Moved back to NotDone: contradiction. *)
      iDestruct "NotDone" as "(>Hs' & _ & _)".
      iDestruct (own_valid_2 with "Hs Hs'") as %?. contradiction.
    * iDestruct "Done" as "(_ & QT & Hghost)".
      iDestruct "QT" as "[Qn | >T]"; last first.
      { iDestruct (own_valid_2 with "Ht T") as %Contra.
          by inversion Contra. }
      iSplitR "Qn"; last done. iIntros "!> !>". unfold descr_inv.
      iExists _. iFrame "Hp". iRight.
      unfold done_state. iFrame "#∗".
  Qed.

  (** ** Proof of [complete] *)

  (** The part of [complete] for the succeeding thread that moves from [accepted] to [done] state *)
  Lemma complete_succeeding_thread_pending (γ_n γ_t γ_s : gname) l_n P Q p
        (n1 n : val) (l_descr l_ghost : loc) Φ :
    inv rdcssN (rdcss_inv γ_n l_n) -∗
    inv descrN (descr_inv P Q p n1 l_n l_descr l_ghost γ_n γ_t γ_s) -∗
    l_ghost ↦{1 / 2} #() -∗
    (□(own_token γ_t ={⊤}=∗ ▷ (Q n1)) -∗ Φ #()) -∗
    own γ_n (● Excl' n) -∗
    WP Resolve (CmpXchg #l_n (InjRV #l_descr) (InjLV n)) #p #l_ghost ;; #() {{ v, Φ v }}.
  Proof.
    iIntros "#InvC #InvS Hl_ghost HQ Hn●". wp_bind (Resolve _ _ _)%E.
    iInv rdcssN as (s) "(>Hln & Hrest)".
    iInv descrN as (vs) "(>Hp & [NotDone | Done])"; last first.
    { (* We cannot be [done] yet, as we own the "ghost location" that serves
         as token for that transition. *)
      iDestruct "Done" as "(_ & _ & Hlghost & _)".
      iDestruct "Hlghost" as (v') ">Hlghost".
        by iDestruct (mapsto_valid_2 with "Hl_ghost Hlghost") as %?.
    }
    iDestruct "NotDone" as "(>Hs & >Hln' & [Pending | Accepted])".
    { (* We also cannot be [Pending] any more we have [own γ_n] showing that this
       transition has happened   *)
       iDestruct "Pending" as "[_ >[_ Hn●']]".
       iCombine "Hn●" "Hn●'" as "Contra".
       iDestruct (own_valid with "Contra") as %Contra. by inversion Contra.
    }
    (* So, we are [Accepted]. Now we can show that (InjRV l_descr) = (state_to_val s), because
       while a [descr] protocol is not [done], it owns enough of
       the [rdcss] protocol to ensure that does not move anywhere else. *)
    destruct s as [n' | l_descr' l_m' m1' n1' n2' p'].
    { simpl. iDestruct (mapsto_agree with "Hln Hln'") as %Heq. inversion Heq. }
    iDestruct (mapsto_agree with "Hln Hln'") as %[= ->].
    simpl.
    iDestruct "Hrest" as (q P' Q' l_ghost' γ_t' γ_s') "(_ & [>Hld >Hld'] & Hrest)".
    (* We perform the CAS. *)
    iCombine "Hln Hln'" as "Hln".
    wp_apply (wp_resolve with "Hp"); first done. wp_cmpxchg_suc.
    iIntros (vs' ->) "Hp'". simpl.
    (* Update to Done. *)
    iDestruct "Accepted" as "[Hl_ghost_inv [HEq Q]]".
    iMod (own_update with "Hs") as "Hs".
    { apply (cmra_update_exclusive (Cinr (to_agree ()))). done. }
    iDestruct "Hs" as "#Hs'". iModIntro.
    iSplitL "Hl_ghost_inv Hl_ghost Q Hp' Hld".
    (* Update state to Done. *)
    { iNext. iExists _. iFrame "Hp'". iRight. unfold done_state.
      iFrame "#∗". iSplitR "Hld"; iExists _; done. }
    iModIntro. iSplitR "HQ".
    { iNext. iDestruct "Hln" as "[Hln1 Hln2]".
      iExists (Quiescent n). iFrame. }
    iApply wp_fupd. wp_seq. iApply "HQ".
    iApply state_done_extract_Q; done.
  Qed.

  (** The part of [complete] for the failing thread *)
  Lemma complete_failing_thread γ_n γ_t γ_s l_n l_descr P Q p n1 n l_ghost_inv l_ghost Φ :
    l_ghost_inv ≠ l_ghost →
    inv rdcssN (rdcss_inv γ_n l_n) -∗
    inv descrN (descr_inv P Q p n1 l_n l_descr l_ghost_inv γ_n γ_t γ_s) -∗
    (□(own_token γ_t ={⊤}=∗ ▷ (Q n1)) -∗ Φ #()) -∗
    WP Resolve (CmpXchg #l_n (InjRV #l_descr) (InjLV n)) #p #l_ghost ;; #() {{ v, Φ v }}.
  Proof.
    iIntros (Hnl) "#InvC #InvS HQ". wp_bind (Resolve _ _ _)%E.
    iInv rdcssN as (s) "(>Hln & Hrest)".
    iInv descrN as (vs) "(>Hp & [NotDone | [#Hs Done]])".
    { (* If the [descr] protocol is not done yet, we can show that it
         is the active protocol still (l = l').  But then the CAS would
         succeed, and our prophecy would have told us that.
         So here we can prove that the prophecy was wrong. *)
        iDestruct "NotDone" as "(_ & >Hln' & State)".
        iDestruct (mapsto_agree with "Hln Hln'") as %[=->].
        iCombine "Hln Hln'" as "Hln".
        wp_apply (wp_resolve with "Hp"); first done; wp_cmpxchg_suc.
        iIntros (vs' ->). simpl.
        iDestruct "State" as "[Pending | Accepted]".
        + iDestruct "Pending" as "[_ [Hvs _]]". iDestruct "Hvs" as %Hvs. by inversion Hvs.
        + iDestruct "Accepted" as "[_ [Hvs _]]". iDestruct "Hvs" as %Hvs. by inversion Hvs. }
    (* So, we know our protocol is [Done]. *)
    (* It must be that (state_to_val s) ≠ l because we are in the failing thread. *)
    destruct s as [n' | l_descr' l_m' m1' n1' n2' p'].
    { (* (injL n) is the current value, hence the CAS fails *)
      (* FIXME: proof duplication *)
      wp_apply (wp_resolve with "Hp"); first done. wp_cmpxchg_fail.
      iIntros (vs' ->) "Hp". iModIntro.
      iSplitL "Done Hp". { by eauto 12 with iFrame. } iModIntro.
      iSplitL "Hln Hrest". { by eauto 12 with iFrame. }
      wp_seq. iApply "HQ".
      iApply state_done_extract_Q; done.
    }
    (* (injR l_descr') is the current value *)
    destruct (decide (l_descr' = l_descr)) as [->|Hn]. {
      (* The [descr] protocol is [done] while still being the active protocol
         of the [rdcss] instance?  Impossible, now we will own more than the whole descriptor location! *)
      iDestruct "Done" as "(_ & _ & >Hld)".
      iDestruct "Hld" as (v') "Hld".
      iDestruct "Hrest" as (q P' Q' l_ghost' γ_t' γ_s') "(_ & >[Hld' Hld''] & Hrest)".
      iDestruct (mapsto_combine with "Hld Hld'") as "[Hld _]".
      rewrite Qp_half_half. iDestruct (mapsto_valid_3 with "Hld Hld''") as "[]".
    }
    (* The CAS fails. *)
    wp_apply (wp_resolve with "Hp"); first done. wp_cmpxchg_fail.
    iIntros (vs' ->) "Hp". iModIntro.
    iSplitL "Done Hp". { by eauto 12 with iFrame. } iModIntro.
    iSplitL "Hln Hrest". { by eauto 12 with iFrame. }
    wp_seq. iApply "HQ".
    iApply state_done_extract_Q; done.
  Qed.

  (** ** Proof of [complete] *)
  (* The postcondition basically says that *if* you were the thread to own
     this request, then you get [Q].  But we also try to complete other
     thread's requests, which is why we cannot ask for the token
     as a precondition. *)
  Lemma complete_spec (l_n l_m l_descr : loc) (m1 n1 n2 : val) (p : proph_id) γ_n γ_t γ_s l_ghost_inv P Q q:
    val_is_unboxed m1 →
    N ## gcN → 
    inv rdcssN (rdcss_inv γ_n l_n) -∗
    inv descrN (descr_inv P Q p n1 l_n l_descr l_ghost_inv γ_n γ_t γ_s) -∗
    □ pau P Q γ_n l_m m1 n1 n2 -∗
    is_gc_loc l_m -∗
    gc_inv -∗
    {{{ l_descr ↦{q} (#l_m, m1, n1, n2, #p) }}}
       complete #l_descr #l_n
    {{{ RET #(); □ (own_token γ_t ={⊤}=∗ ▷(Q n1)) }}}.
  Proof.
    iIntros (Hm_unbox Hdisj) "#InvC #InvS #PAU #isGC #InvGC".
    iModIntro. iIntros (Φ) "Hld HQ".  wp_lam. wp_let.
    wp_bind (! _)%E. wp_load. iClear "Hld". wp_pures.
    wp_alloc l_ghost as "[Hl_ghost' Hl_ghost'2]". wp_pures.
    wp_bind (! _)%E. 
    (* open outer invariant *)
    iInv rdcssN as (s) "(>Hln & Hrest)"=>//.
    (* two different proofs depending on whether we are succeeding thread *)
    destruct (decide (l_ghost_inv = l_ghost)) as [-> | Hnl].
    - (* we are the succeeding thread *)
      (* we need to move from [pending] to [accepted]. *)
      iInv descrN as (vs) "(>Hp & [(>Hs & >Hln' & [Pending | Accepted]) | [#Hs Done]])".
      + (* Pending: update to accepted *)
        iDestruct "Pending" as "[P >[Hvs Hn●]]".
        iDestruct ("PAU" with "P") as ">AU".
        iMod (gc_access with "InvGC") as "Hgc"; first solve_ndisj.
        (* open and *COMMIT* AU, sync B location l_n and A location l_m *)
        iMod "AU" as (m' n') "[CC [_ Hclose]]".
        iDestruct "CC" as "[Hgc_lm Hn◯]". 
        (* sync B location and update it if required *)
        iDestruct (sync_values with "Hn● Hn◯") as %->.
        iMod (update_value _ _ _ (if decide (m' = m1 ∧ n' = n') then n2 else n') with "Hn● Hn◯")
          as "[Hn● Hn◯]".
        (* get access to A location *)
        iDestruct ("Hgc" with "Hgc_lm") as "[Hl Hgc_close]".
        (* read A location *)
        wp_load.
        (* sync A location *)
        iMod ("Hgc_close" with "Hl") as "[Hgc_lm Hgc_close]".
        (* give back access to A location *)
        iMod ("Hclose" with "[Hn◯ Hgc_lm]") as "Q"; first by iFrame.
        iModIntro. iMod "Hgc_close" as "_".
        (* close descr inv *)
        iModIntro. iSplitL "Q Hl_ghost' Hp Hvs Hs Hln'".
        { iModIntro. iNext. iExists _. iFrame "Hp". iLeft. iFrame.
          iRight. iSplitL "Hl_ghost'"; first by iExists _.
          destruct (val_to_some_loc vs) eqn:Hvts; iFrame. }
        (* close outer inv *)
        iModIntro. iSplitR "Hl_ghost'2 HQ Hn●".
        { by eauto 12 with iFrame. }
        iModIntro.
        destruct (decide (m' = m1)) as [-> | ?];
        wp_op;
        case_bool_decide; simplify_eq; wp_if; wp_pures;
           [rewrite decide_True; last done | rewrite decide_False; last tauto];
          iApply (complete_succeeding_thread_pending
                    with "InvC InvS Hl_ghost'2 HQ Hn●").
      + (* Accepted: contradiction *)
        iDestruct "Accepted" as "[>Hl_ghost_inv _]".
        iDestruct "Hl_ghost_inv" as (v') "Hlghost".
        iCombine "Hl_ghost'" "Hl_ghost'2" as "Hl_ghost'".
        by iDestruct (mapsto_valid_2 with "Hlghost Hl_ghost'") as %?.
      + (* Done: contradiction *)
        iDestruct "Done" as "[QT >[Hlghost _]]".
        iDestruct "Hlghost" as (v') "Hlghost".
        iCombine "Hl_ghost'" "Hl_ghost'2" as "Hl_ghost'".
        by iDestruct (mapsto_valid_2 with "Hlghost Hl_ghost'") as %?.
    - (* we are the failing thread *)
      (* close invariant *)
      iMod (is_gc_access with "InvGC isGC") as (v) "[Hlm Hclose]"; first solve_ndisj.
      wp_load.
      iMod ("Hclose" with "Hlm") as "_". iModIntro.
      iModIntro.
      iSplitL "Hln Hrest".
      { iExists _. iFrame. iFrame. }
      (* two equal proofs depending on value of m1 *)
      wp_op.
      destruct (decide (v = m1)) as [-> | ];
      case_bool_decide; simplify_eq; wp_if;  wp_pures;
      iApply (complete_failing_thread
                 with "InvC InvS HQ"); done.
  Qed.

  (** ** Proof of [rdcss] *)
  Lemma rdcss_spec γ_n (l_n l_m: loc) (m1 n1 n2: val) :
    val_is_unboxed m1 →
    val_is_unboxed (InjLV n1) →
    is_rdcss γ_n l_n -∗
    <<< ∀ (m n: val), gc_mapsto l_m m ∗ rdcss_content γ_n n >>>
        rdcss #l_m #l_n m1 n1 n2 @((⊤∖↑N)∖↑gcN)
    <<< gc_mapsto l_m m ∗ rdcss_content γ_n (if decide (m = m1 ∧ n = n1) then n2 else n), RET n >>>.
  Proof.
    iIntros (Hm1_unbox Hn1_unbox) "Hrdcss". iDestruct "Hrdcss" as "(#InvR & #InvGC & Hdisj)".
    iDestruct "Hdisj" as %Hdisj. iIntros (Φ) "AU". 
    (* allocate fresh descriptor *)
    wp_lam. wp_pures. 
    wp_apply wp_new_proph; first done.
    iIntros (proph_values p) "Hp".
    wp_let. wp_alloc l_descr as "Hld".
    wp_pures.
    (* invoke inner recursive function [rdcss_inner] *)
    iLöb as "IH".
    wp_bind (CmpXchg _ _ _)%E.
    (* open outer invariant for the CAS *)
    iInv rdcssN as (s) "(>Hln & Hrest)".
    destruct s as [n | l_descr' l_m' m1' n1' n2' p'].
    - (* l_n ↦ injL n *)
      (* a non-value descriptor n is currently stored at l_n *)
      iDestruct "Hrest" as ">[Hln' Hn●]".
      destruct (decide (n1 = n)) as [-> | Hneq].
      + (* values match -> CAS is successful *)
        iCombine "Hln Hln'" as "Hln".
        wp_cmpxchg_suc.
        (* Take a "peek" at [AU] and abort immediately to get [gc_is_gc f]. *)
        iMod "AU" as (b' n') "[[Hf CC] [Hclose _]]".
        iDestruct (gc_is_gc with "Hf") as "#Hgc".
        iMod ("Hclose" with "[Hf CC]") as "AU"; first by iFrame.
        (* Initialize new [descr] protocol .*)
        iDestruct (laterable with "AU") as (AU_later) "[AU #AU_back]".
        iMod (own_alloc (Excl ())) as (γ_t) "Token"; first done.
        iMod (own_alloc (Cinl $ Excl ())) as (γ_s) "Hs"; first done.
        iDestruct "Hln" as "[Hln Hln']".
        set (winner := default l_descr (val_to_some_loc proph_values)).
        iMod (inv_alloc descrN _ (descr_inv AU_later _ _ _ _ _ winner _ _ _)
              with "[AU Hs Hp Hln' Hn●]") as "#Hinv".
        {
          iNext. iExists _. iFrame "Hp". iLeft. iFrame. iLeft.
          iFrame. destruct (val_to_some_loc proph_values); simpl; done.
        }
        iModIntro. iDestruct "Hld" as "[Hld1 [Hld2 Hld3]]". iSplitR "Hld2 Token".
        { (* close outer invariant *)
          iNext. iCombine "Hld1 Hld3" as "Hld1". iExists (Updating l_descr l_m m1 n n2 p).
          eauto 12 with iFrame. 
        }
        wp_pures.
        wp_apply (complete_spec with "[] [] [] [] [] [$Hld2]");[ done..|].
        iIntros "Ht". iMod ("Ht" with "Token") as "Φ". by wp_seq.
      + (* values do not match -> CAS fails 
           we can commit here *)
        wp_cmpxchg_fail.
        iMod "AU" as (m'' n'') "[[Hm◯ Hn◯] [_ Hclose]]"; simpl.
        (* synchronize B location *)
        iDestruct (sync_values with "Hn● Hn◯") as %->.
        iMod ("Hclose" with "[Hm◯ Hn◯]") as "HΦ".
        {  destruct (decide _) as [[_ ?] | _]; [done | iFrame ]. }
        iModIntro. iSplitR "HΦ".
        { iModIntro. iExists (Quiescent n''). iFrame. }
        wp_pures. iFrame.
    - (* l_n ↦ injR l_ndescr' *)
      (* a descriptor l_descr' is currently stored at l_n -> CAS fails
         try to help the on-going operation *)
      wp_cmpxchg_fail. 
      iModIntro.
      (* extract descr invariant *)
      iDestruct "Hrest" as (q P Q l_ghost γ_t γ_s) "(#Hm1'_unbox & [Hld1 [Hld2 Hld3]] & #InvS & #P_AU & #P_GC)".
      iDestruct "Hm1'_unbox" as %Hm1'_unbox.
      iSplitR "AU Hld2 Hld Hp".
      (* close invariant, retain some permission to l_descr', so it can be read later *)
      { iModIntro. iExists (Updating l_descr' l_m' m1' n1' n2' p'). iFrame. eauto 12 with iFrame. }
      wp_pures.
      wp_apply (complete_spec with "[] [] [] [] [] [$Hld2]"); [done..|].
      iIntros "_". wp_seq. wp_pures.
      iApply ("IH" with "AU Hp Hld").
  Qed.

  (** ** Proof of [new_rdcss] *)
  Lemma new_rdcss_spec (n: val) :
    N ## gcN → gc_inv -∗
    {{{ True }}}
        new_rdcss n
    {{{ l_n γ_n, RET #l_n ; is_rdcss γ_n l_n ∗ rdcss_content γ_n n }}}.
  Proof.
    iIntros (Hdisj) "#InvGC". iModIntro.
    iIntros (Φ) "_ HΦ". wp_lam. wp_apply wp_fupd.
    wp_alloc l_n as "Hln".
    iMod (own_alloc (● Excl' n  ⋅ ◯ Excl' n)) as (γ_n) "[Hn● Hn◯]".
    { by apply auth_both_valid. }
    iMod (inv_alloc rdcssN _ (rdcss_inv γ_n l_n)
      with "[Hln Hn●]") as "#InvR".
    { iNext. iDestruct "Hln" as "[Hln1 Hln2]".
      iExists (Quiescent n). iFrame. }
    wp_let.
    iModIntro.
    iApply ("HΦ" $! l_n γ_n).
    iSplitR; last by iFrame. by iFrame "#". 
  Qed.

  (** ** Proof of [get] *)
  Lemma get_spec γ_n l_n :
    is_rdcss γ_n l_n -∗
    <<< ∀ (n : val), rdcss_content γ_n n >>>
        get #l_n @(⊤∖↑N)
    <<< rdcss_content γ_n n, RET n >>>.
  Proof.
    iIntros "Hrdcss". iDestruct "Hrdcss" as "(#InvR & #InvGC & Hdisj)".
    iDestruct "Hdisj" as %Hdisj. iIntros (Φ) "AU". 
    iLöb as "IH". wp_lam. repeat (wp_proj; wp_let). wp_bind (! _)%E.
    iInv rdcssN as (s) "(>Hln & Hrest)".
    wp_load.
    destruct s as [n | l_descr l_m m1 n1 n2 p].
    - iMod "AU" as (au_n) "[Hn◯ [_ Hclose]]"; simpl.
      iDestruct "Hrest" as "[Hln' Hn●]".
      iDestruct (sync_values with "Hn● Hn◯") as %->.
      iMod ("Hclose" with "Hn◯") as "HΦ". 
      iModIntro. iSplitR "HΦ". {
        iNext. iExists (Quiescent au_n). iFrame.
      }
      wp_match. iApply "HΦ".
    - iDestruct "Hrest" as (q P Q l_ghost γ_t γ_s) "(#Hm1_unbox & [Hld [Hld' Hld'']] & #InvS & #PAU & #GC)".
      iDestruct "Hm1_unbox" as %Hm1_unbox.
      iModIntro. iSplitR "AU Hld'". {
        iNext. iExists (Updating l_descr l_m m1 n1 n2 p). eauto 12 with iFrame. 
      }
      wp_match. 
      wp_apply (complete_spec with "[] [] [] [] [] [$Hld']"); [done..|].
      iIntros "Ht". wp_seq. iApply "IH". iApply "AU".
  Qed.

End rdcss.

Definition atomic_rdcss `{!heapG Σ, !rdcssG Σ, !gcG Σ} :
  spec.atomic_rdcss Σ :=
  {| spec.new_rdcss_spec := new_rdcss_spec;
     spec.rdcss_spec := rdcss_spec;
     spec.get_spec := get_spec;
     spec.rdcss_content_exclusive := rdcss_content_exclusive |}.

Typeclasses Opaque rdcss_content is_rdcss.
