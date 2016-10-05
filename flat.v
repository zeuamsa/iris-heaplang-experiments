From iris.program_logic Require Export auth weakestpre saved_prop.
From iris.proofmode Require Import invariants ghost_ownership.
From iris.heap_lang Require Export lang.
From iris.heap_lang Require Import proofmode notation.
From iris.heap_lang.lib Require Import spin_lock.
From iris.algebra Require Import upred frac agree excl dec_agree upred_big_op gset gmap.
From iris.tests Require Import misc atomic treiber_stack.

Definition doOp : val :=
  λ: "f" "p",
     match: !"p" with
       InjL "x" => "p" <- InjR ("f" "x")
     | InjR "_" => #()
     end.

Definition doOp' (f:val) : val :=
  λ: "p",
     match: !"p" with
       InjL "x" => "p" <- InjR (f "x")
     | InjR "_" => #()
     end.

Definition try_srv : val :=
  λ: "lk" "s" "f",
    if: try_acquire "lk"
      then let: "hd" := !"s" in
           let: "f'" := doOp "f" in
           iter "hd" "f'";;
           release "lk"
      else #().

Definition loop: val :=
  rec: "loop" "f" "p" "s" "lk" :=
    match: !"p" with
    InjL "_" =>
        try_srv "lk" "s" "f";;
        "loop" "f" "p" "s" "lk"
    | InjR "r" => "r"
    end.

Definition install : val :=
  λ: "x" "s",
     let: "p" := ref (InjL "x") in
     push "s" "p";;
     "p".

Definition mk_flat : val :=
  λ: "f",
   let: "lk" := newlock #() in
   let: "s" := new_stack #() in
   λ: "x",
      let: "p" := install "x" "s" in
      loop "f" "p" "s" "lk".

Global Opaque doOp try_srv install loop mk_flat.

Definition reqR := prodR fracR (dec_agreeR val). (* request x should be kept same *)
Definition toks : Type := gname * gname * gname * gname * gname. (* a bunch of tokens to do state transition *)
Definition tokmR := evmapR loc toks. (* tie each slot to tokens *)
Definition reqmR := evmapR loc val. (* tie each slot to request value *)
Class flatG Σ := FlatG {
  req_G :> inG Σ reqR;
  tok_G :> inG Σ (authR tokmR);
  sp_G  :> savedPropG Σ (cofe_funCF val idCF)
}.

Definition flatΣ : gFunctors :=
  #[ GFunctor (constRF reqR);
     GFunctor (constRF (authR tokmR));
     savedPropΣ (cofe_funCF val idCF)
   ].

Instance subG_flatΣ {Σ} : subG flatΣ Σ → flatG Σ.
Proof. intros [?%subG_inG [?%subG_inG [? _]%subG_inv]%subG_inv]%subG_inv. split; apply _. Qed.

Section proof.
  Context `{!heapG Σ, !lockG Σ, !evidenceG loc val Σ, !flatG Σ} (N : namespace).
  Context (R: iProp Σ).

  Definition init_s (ts: toks) :=
    let '(_, γ1, γ3, _, _) := ts in (own γ1 (Excl ()) ★ own γ3 (Excl ()))%I.

  Definition installed_s (ts: toks) (f x: val) :=
    let '(γx, γ1, _, γ4, γq) := ts in
    (∃ (P: val → iProp Σ) Q, own γx ((1/2)%Qp, DecAgree x) ★ P x ★ ({{ R ★ P x }} f x {{ v, R ★ Q x v }}) ★
                             saved_prop_own γq (Q x) ★ own γ1 (Excl ()) ★ own γ4 (Excl ()))%I.

  Definition received_s (ts: toks) (x: val) γr :=
    let '(γx, _, _, γ4, _) := ts in
    (own γx ((1/2/2)%Qp, DecAgree x) ★ own γr (Excl ()) ★ own γ4 (Excl ()))%I.

  Definition finished_s (ts: toks) (x y: val) :=
    let '(γx, γ1, _, γ4, γq) := ts in
    (∃ Q: val → val → iProp Σ,
       own γx ((1/2)%Qp, DecAgree x) ★ saved_prop_own γq (Q x) ★
       Q x y ★ own γ1 (Excl ()) ★ own γ4 (Excl ()))%I.

  Definition evm := ev loc toks.
  
  (* p slot invariant *)
  Definition p_inv (γm γr: gname) (f v: val) :=
    (∃ (ts: toks) (p : loc),
       v = #p ★ evm γm p ts ★
       ((* INIT *)
        (∃ y: val, p ↦{1/2} InjRV y ★ init_s ts)∨
        (* INSTALLED *)
        (∃ x: val, p ↦{1/2} InjLV x ★ installed_s ts f x) ∨
        (* RECEIVED *)
        (∃ x: val, p ↦{1/2} InjLV x ★ received_s ts x γr) ∨
        (* FINISHED *)
        (∃ x y: val, p ↦{1/2} InjRV y ★ finished_s ts x y)))%I.

  Definition srv_stack_inv γs γm γr s f := (∃ xs, is_stack' (p_inv γm γr f) γs xs s)%I.

  Definition srv_tokm_inv γm := (∃ m : tokmR, own γm (● m) ★ [★ map] p ↦ _ ∈ m, ∃ v, p ↦{1/2} v)%I.

  Lemma install_push_spec
        (Φ: val → iProp Σ)
        (p: loc) (γs γm γr: gname) (ts: toks)
        (s: loc) (f x: val) :
    heapN ⊥ N →
    heap_ctx ★ inv N (srv_stack_inv γs γm γr s f ★ srv_tokm_inv γm) ★
    evm γm p ts ★ installed_s ts f x ★
    p ↦{1/2} InjLV x ★ ((∃ hd, evs γs hd #p) -★ Φ #())
    ⊢ WP push #s #p {{ Φ }}.
  Proof.
    iIntros (HN) "(#Hh & #? & Hpm & Hs & Hp & HΦ)".
    rewrite /srv_stack_inv.
    iDestruct (push_spec N (p_inv γm γr f) (fun v => (∃ hd, evs γs hd #p) ★ v = #())%I
               with "[-HΦ]") as "Hpush"=>//.
    - iFrame "Hh". iSplitL "Hp Hs Hpm"; last eauto.
      iExists ts. iExists p. iSplit=>//. iFrame "Hpm".
      iRight. iLeft. iExists x. iFrame.
    - iApply wp_wand_r.
      iSplitL "Hpush"; first done.
      iIntros (?) "[? %]". subst.
      by iApply "HΦ".
  Qed.

  Definition installed_recp (ts: toks) (x: val) (Q: val → val → iProp Σ) :=
    let '(γx, _, γ3, _, γq) := ts in
    (own γ3 (Excl ()) ★ own γx ((1/2)%Qp, DecAgree x) ★ saved_prop_own γq (Q x))%I.

  Lemma install_spec
        (Φ: val → iProp Σ) P Q
        (f x: val) (γs γm γr: gname) (s: loc):
    heapN ⊥ N →
    heap_ctx ★ inv N (srv_stack_inv γs γm γr s f ★ srv_tokm_inv γm) ★ P x ★ ({{ R ★ P x }} f x {{ v, R ★ Q x v }}) ★
    (∀ (p: loc) (ts: toks), installed_recp ts x Q -★ evm γm p ts -★(∃ hd, evs γs hd #p) -★ Φ #p)
    ⊢ WP install x #s {{ Φ }}.
  Proof.
    iIntros (HN) "(#Hh & #? & Hpx & Hf & HΦ)".
    wp_seq. wp_let. wp_alloc p as "Hl".
    iApply pvs_wp.
    iVs (own_alloc (Excl ())) as (γ1) "Ho1"; first done.
    iVs (own_alloc (Excl ())) as (γ3) "Ho3"; first done.
    iVs (own_alloc (Excl ())) as (γ4) "Ho4"; first done.
    iVs (own_alloc (1%Qp, DecAgree x)) as (γx) "Hx"; first done.
    iVs (saved_prop_alloc (F:=(cofe_funCF val idCF)) (Q x)%I) as (γq) "#?".
    iInv N as "[Hrs >Hm]" "Hclose".
    iDestruct "Hm" as (m) "[Hm HRm]".
    destruct (m !! p) eqn:Heqn.
    - (* old name *)
      iDestruct (big_sepM_delete (fun p _ => ∃ v : val, p ↦{1 / 2} v)%I m with "HRm") as "[Hp HRm]"=>//.
      iDestruct "Hp" as (?) "Hp". iExFalso. iApply bogus_heap; last by iFrame "Hh Hl Hp". auto.
    - (* fresh name *)
      iDestruct (evmap_alloc _ _ _ m p (γx, γ1, γ3, γ4, γq) with "[Hm]") as "==>[Hm1 Hm2]"=>//.
      iDestruct "Hl" as "[Hl1 Hl2]".
      iVs ("Hclose" with "[HRm Hm1 Hl1 Hrs]").
      + iNext. iFrame. iExists ({[p := (1%Qp, DecAgree (γx, γ1, γ3, γ4, γq))]} ⋅ m). iFrame.
        rewrite <-(insert_singleton_op m)=>//.
        iDestruct (big_sepM_insert _ m with "[-]") as "H"=>//.
        iSplitL "Hl1"; last by iAssumption. eauto.
      + iDestruct (pack_ev with "Hm2") as "Hev".
        iDestruct (dup_ev with "Hev") as "==>[Hev1 Hev2]".
        iDestruct (own_update with "Hx") as "==>[Hx1 Hx2]"; first by apply pair_l_frac_op_1'.
        iVsIntro. wp_let. wp_bind ((push _) _).
        iApply install_push_spec=>//.
        iFrame "#". rewrite /evm /installed_s.
        iFrame.
        iSplitL "Hpx Hx1 Hf".
        { iExists P, Q. by iFrame. }
        iIntros "Hhd". wp_seq. iVsIntro.
        iSpecialize ("HΦ" $! p (γx, γ1, γ3, γ4, γq) with "[-Hev1 Hhd]")=>//.
        { rewrite /installed_recp. iFrame. iFrame "#". }
        by iApply ("HΦ" with "Hev1").
  Qed.

  Lemma loop_iter_list_spec Φ (f: val) (s hd: loc) (γs γm γr: gname) xs:
    heapN ⊥ N →
    heap_ctx ★ inv N (srv_stack_inv γs γm γr s f ★ srv_tokm_inv γm) ★ own γr (Excl ()) ★ R ★
    is_list' γs hd xs ★ (own γr (Excl ()) -★ R -★ Φ #())
    ⊢ WP doOp f {{ f', WP iter #hd f' {{ Φ }} }}.
  Proof.
    iIntros (HN) "(#Hf & #? & Ho2 & HR & Hlist' & HΦ)".
    iApply pvs_wp.
    iDestruct (dup_is_list' with "[Hlist']") as "==>[Hl1 Hl2]"; first by iFrame.
    iDestruct (dup_is_list' with "[Hl2]") as "==>[Hl2 Hl3]"; first by iFrame.
    iVsIntro. wp_seq.
    iDestruct (iter_spec _ (p_inv γm γr f) (fun v => v = #() ★ own γr (Excl ()) ★ R)%I γs s
                         (is_list' γs hd xs ★ own γr (Excl ()) ★ R)%I (srv_tokm_inv γm) xs hd
                         (doOp' f) (doOp' f)
                         with "[-Hl1 HΦ]") as "Hiter"=>//.
    - rewrite /f_spec.
      iIntros (Φ' p _ Hin) "(#Hh & #? & (Hls & Ho2 & HR) & HΦ')".
      wp_let. wp_bind (! _)%E. iInv N as "[Hs >Hm]" "Hclose".
      iDestruct "Hs" as (xs' hd') "[>Hhd [>Hxs HRs]]".
      iDestruct (dup_is_list' with "[Hls]") as "==>[Hls1 Hls2]"; first by iFrame.
      iDestruct "HRs" as (m) "[>Hom HRs]".
      (* acccess *)
      iDestruct (access with "[Hom HRs Hls1]") as (hd'' ?) "(Hrest & HRx & % & Hom)"=>//; first iFrame.
      iDestruct "HRx" as (v') "[>% [Hpinv' >Hhd'']]". inversion H1. subst.
      iDestruct "Hpinv'" as (ts p'') "[>% [>Hevm [Hp | [Hp | [Hp | Hp]]]]]"; subst.
      + iDestruct "Hp" as (y) "(>Hp & Hs)".
        wp_load. iVs ("Hclose" with "[-HΦ' Ho2 HR Hls2]").
        { iNext. iFrame. iExists xs', hd'.
          iFrame "Hhd Hxs". iExists m.
          iFrame "Hom". iDestruct (big_sepM_delete _ m with "[Hrest Hhd'' Hevm Hp Hs]") as "?"=>//.
          iFrame. iExists #p''. iSplitR; first done. iExists ts, p''.
          iSplitR; first done. iFrame. iLeft. iExists y. iFrame. }
        iVsIntro. wp_match. iApply "HΦ'". by iFrame.
      + iDestruct "Hp" as (x') "(Hp & Hs)".
        wp_load. destruct ts as [[[[γx γ1] γ3] γ4] γq].
        iDestruct "Hs" as  (P Q) "(Hx & Hpx & Hf & HoQ& Ho1 & Ho4)".
        iDestruct (dup_ev with "Hevm") as "==>[Hevm1 Hevm2]".
        iAssert (|=r=> own γx (((1/2/2)%Qp, DecAgree x') ⋅
                               ((1/2/2)%Qp, DecAgree x')))%I with "[Hx]" as "==>[Hx1 Hx2]".
        { iDestruct (own_update with "Hx") as "?"; last by iAssumption.
          rewrite -{1}(Qp_div_2 (1/2)%Qp).
          by apply pair_l_frac_op'. }
        iVs ("Hclose" with "[-Hf Hls2 Ho1 Hx2 HR Hevm2 HoQ Hpx HΦ']").
        { iNext. iFrame. iExists xs', hd'.
          iFrame "Hhd Hxs". iExists m.
          iFrame "Hom". iDestruct (big_sepM_delete _ m with "[-]") as "?"=>//.
          simpl. iFrame. iExists #p''. iSplitR; auto. rewrite /allocated.
          iExists (γx, γ1, γ3, γ4, γq), p''. iSplitR; auto.
          iFrame. iRight. iRight. iLeft. iExists x'. iFrame. }
        iVsIntro. wp_match.
        wp_bind (f _). iApply wp_wand_r. iSplitL "Hpx Hf HR".
        { iApply "Hf". iFrame. }
        iIntros (v) "[HR HQ]".
        wp_value. iVsIntro. iInv N as "[Hs >Hm]" "Hclose".
        iDestruct "Hs" as (xs'' hd''') "[>Hhd [>Hxs HRs]]".
        iDestruct "HRs" as (m') "[>Hom HRs]".
        iDestruct (dup_is_list' with "[Hls2]") as "==>[Hls2 Hls3]"; first by iFrame.
        iDestruct (access with "[Hom HRs Hls2]") as (hd'''' q) "(Hrest & HRx & % & Hom)"=>//; first iFrame.
        iDestruct "HRx" as (v'') "[>% [Hpinv' >Hhd'']]". inversion H2. subst.
        iDestruct "Hpinv'" as ([[[[γx' γ1'] γ3'] γ4'] γq'] p'''') "[>% [>Hevm Hps]]".
        inversion H3. subst.
        destruct (decide (γ1 = γ1' ∧ γx = γx' ∧ γ3 = γ3' ∧ γ4 = γ4' ∧ γq = γq')) as [[? [? [? [? ?]]]]|Hneq]; subst.
        {
          iDestruct "Hps" as "[Hp | [Hp | [Hp | Hp]]]".
          * iDestruct "Hp" as (?) "(_ & >Ho1' & _)".
            iApply excl_falso. iFrame.
          * iDestruct "Hp" as (?) "[>? Hs]". iDestruct "Hs" as (? ?) "(_ & _ & _ & _ & >Ho1' & _)".
            iApply excl_falso. iFrame.
          * iDestruct "Hp" as (x5) ">(Hp & Hx & Ho2 & Ho4)".
            iDestruct "Hm" as (m2) "[Hom2 HRm]".
            destruct (m2 !! p'''') eqn:Heqn.
            {
              iDestruct (big_sepM_delete _ m2 with "HRm") as "[HRk HRm]"=>//.
              iDestruct "HRk" as (?) "HRk".
              iDestruct (heap_mapsto_op_1 with "[HRk Hp]") as "[% Hp]"; first by iFrame.
              rewrite Qp_div_2. wp_store.
              (* now close the invariant *)
              iDestruct (m_frag_agree with "[Hx Hx2]") as "==>[Hx %]"; first iFrame.
              subst. rewrite Qp_div_2. iVs ("Hclose" with "[-HΦ' Ho2 HR Hls3]").
              { iNext. iDestruct "Hp" as "[Hp1 Hp2]".
                iAssert (srv_tokm_inv γm) with "[Hp1 HRm Hom2]" as "HRm".
                { iExists m2. iFrame. iApply (big_sepM_delete _ m2)=>//.
                  iFrame. eauto. }
                iFrame. iExists xs''. iFrame. iExists hd'''. iFrame.
                iExists m'. iFrame.
                iDestruct (big_sepM_delete _ m' with "[-]") as "?"=>//.
                { simpl. iFrame. iExists #p''''.
                  iSplitR; first auto. iExists (γx', γ1', γ3', γ4', γq'), p''''.
                  iSplitR; first auto. iFrame "Hevm". iRight. iRight.
                  iRight. iExists x5, v. iFrame.
                  iExists Q. iFrame.                  
                }
              }
              iApply "HΦ'". by iFrame.
            }
            { iExFalso. iApply (map_agree_none' _ _ _ m2)=>//. iFrame. }
          * iDestruct "Hp" as (? ?) "[? Hs]". iDestruct "Hs" as (?) "(_ & _ & _ & >Ho1' & _)".
            iApply excl_falso. iFrame.
        }
        { iDestruct (ev_agree with "[Hevm Hevm2]") as "==>[_ [_ %]]"; first iFrame.
          inversion H4. subst. by contradiction Hneq. }
      + destruct ts as [[[[γx γ1] γ3] γ4] γq]. iDestruct "Hp" as (y) "(_ & _ & >Ho2' & _)".
        iApply excl_falso. iFrame.
      + destruct ts as [[[[γx γ1] γ3] γ4] γq]. iDestruct "Hp" as (x' y) "[Hp Hs]".
        iDestruct "Hs" as (Q) "(>Hx & HoQ & HQxy & >Ho1 & >Ho4)".
        wp_load. iVs ("Hclose" with "[-HΦ' HR Ho2 Hls2]").
        { iNext. iFrame. iExists xs', hd'.
          iFrame "Hhd Hxs". iExists m.
          iFrame "Hom". iDestruct (big_sepM_delete _ m with "[-]") as "?"=>//.
          iFrame. iExists #p''. iSplitR; first auto. iExists (γx, γ1, γ3, γ4, γq), p''.
          iSplitR; auto. iFrame. iRight. iRight. iRight. iExists x', y. iFrame.
          iExists Q. iFrame. }
        iVsIntro. wp_match. iApply "HΦ'". by iFrame.
    - apply to_of_val.
    - rewrite /srv_stack_inv. iFrame "#". iFrame. iIntros "(? & ? & ?)". by iFrame.
    - iApply wp_wand_r. iSplitL "Hiter"; first done.
      iIntros (?) "[% [Ho2 HR]]". subst. iApply ("HΦ" with "Ho2 HR").
  Qed.

  Definition own_γ3 (ts: toks) := let '(_, _, γ3, _, _) := ts in own γ3 (Excl ()).
  Definition finished_recp (ts: toks) (x y: val) :=
    let '(γx, _, _, _, γq) := ts in
    (∃ Q, own γx ((1 / 2)%Qp, DecAgree x) ★ saved_prop_own γq (Q x) ★ Q x y)%I.

  Lemma try_srv_spec Φ (s: loc) (lk: val) (f: val)
        (γs γr γm γlk: gname):
    heapN ⊥ N →
    heap_ctx ★ inv N (srv_stack_inv γs γm γr s f ★ srv_tokm_inv γm) ★
    is_lock N γlk lk (own γr (Excl ()) ★ R) ★ Φ #()
    ⊢ WP try_srv lk #s f {{ Φ }}.
  Proof.
    iIntros (?) "(#? & #? & #? & HΦ)".
    wp_seq. wp_let. wp_let.
    wp_bind (try_acquire _). iApply try_acquire_spec.
    iFrame "#". iSplit; last by wp_if.
    (* acquired the lock *)
    iIntros "Hlocked [Ho2 HR]".
    wp_if. wp_bind (! _)%E.
    iInv N as "[H >Hm]" "Hclose".
    iDestruct "H" as (xs' hd') "[>Hs [>Hxs HRs]]".
    wp_load. iDestruct (dup_is_list' with "[Hxs]") as "==>[Hxs1 Hxs2]"; first by iFrame.
    iVs ("Hclose" with "[Hs Hxs1 HRs Hm]").
    { iNext. iFrame. iExists xs', hd'. by iFrame. }
    iVsIntro. wp_let. wp_bind (doOp f).
    iApply wp_wand_r. iSplitL "HR Ho2 Hxs2".
    { iApply (loop_iter_list_spec (fun v => own γr (Excl ()) ★ R ★ v = #()))%I=>//.
      iFrame "#". iFrame. iIntros "? ?". by iFrame. }
    iIntros (f') "Hf'".
    wp_let. wp_bind ((iter _) _).
    iApply wp_wand_r. iSplitL "Hf'"; first iApply "Hf'".
    iIntros (?) "[Ho2 [HR %]]". subst.
    wp_seq. iApply release_spec.
    iFrame "#". iFrame.
  Qed.
    
  Lemma loop_spec Φ (p s: loc) (lk: val) (f: val)
        (γs γr γm γlk: gname) (ts: toks):
    heapN ⊥ N →
    heap_ctx ★ inv N (srv_stack_inv γs γm γr s f ★ srv_tokm_inv γm) ★
    is_lock N γlk lk (own γr (Excl ()) ★ R) ★
    own_γ3 ts ★ evm γm p ts ★
    (∃ hd, evs γs hd #p) ★ (∀ x y, finished_recp ts x y -★ Φ y)
    ⊢ WP loop f #p #s lk {{ Φ }}.
  Proof.
    iIntros (HN) "(#Hh & #? & #? & Ho3 & Hev & Hhd & HΦ)".
    iLöb as "IH". wp_rec. repeat wp_let.
    wp_bind (! _)%E. iInv N as "[Hinv >?]" "Hclose".
    iDestruct "Hinv" as (xs hd) "[>Hs [>Hxs HRs]]".
    iDestruct "HRs" as (m) "[>Hom HRs]".
    iDestruct "Hhd" as (hdp ?) "Hhd".
    destruct (m !! hdp) eqn:Heqn.
    - iDestruct (big_sepM_delete_later _ m with "HRs") as "[Hp Hrs]"=>//.
      iDestruct "Hp" as (?) "[>% [Hpr ?]]"; subst.
      iDestruct "Hpr" as (ts' p') "(>% & >Hp' & Hp)".
      subst. iDestruct (map_agree_eq' _ _ γs m with "[Hom Hhd]") as "(Hom & Hhd & %)"=>//.
      { iFrame. rewrite /ev. eauto. }
      inversion H0. subst.
      iDestruct (ev_agree with "[Hev Hp']") as "==>[Hγs2 [Hγs %]]"; first iFrame. subst.
      destruct ts as [[[[γx γ1] γ3] γ4] γq].
      iDestruct "Hp" as "[Hp | [Hp | [ Hp | Hp]]]".
      + iDestruct "Hp" as (?) "(_ & _ & >Ho3')".
        iApply excl_falso. iFrame.
      + iDestruct "Hp" as (x) "(>Hp & Hs')".
        wp_load. iVs ("Hclose" with "[-Hγs2 Ho3 HΦ Hhd]").
        { iNext. iFrame. iExists xs, hd. iFrame. iExists m. iFrame.
          iDestruct (big_sepM_delete _ m with "[-]") as "?"=>//.
          iFrame. iExists #p'. iSplitR; first auto. iExists (γx, γ1, γ3, γ4, γq), p'.
          iSplitR; first auto. iFrame.
          iRight. iLeft. iExists x. iFrame. }
        iVsIntro. wp_match.
        wp_bind (try_srv _ _ _). iApply try_srv_spec=>//.
        iFrame "#". wp_seq.
        iAssert (∃ hd, evs γs hd #p')%I with "[Hhd]" as "Hhd"; eauto.
        by iApply ("IH" with "Ho3 Hγs2 Hhd").
      + iDestruct "Hp" as (x) "(Hp & Hx & Ho2 & Ho4)".
        wp_load.
        iVs ("Hclose" with "[-Hγs Ho3 HΦ Hhd]").
        { iNext. iFrame. iExists xs, hd. iFrame. iExists m. iFrame.
          iDestruct (big_sepM_delete _ m with "[-]") as "?"=>//.
          iFrame. iExists #p'. iSplitR; auto. iExists (γx, γ1, γ3, γ4, γq), p'.
          iSplitR; first auto. iFrame.
          iRight. iRight. iLeft. iExists x. iFrame. }
        iVsIntro. wp_match.
        wp_bind (try_srv _ _ _). iApply try_srv_spec=>//.
        iFrame "#". wp_seq.
        iAssert (∃ hd, evs γs hd #p')%I with "[Hhd]" as "Hhd"; eauto.
        by iApply ("IH" with "Ho3 Hγs Hhd").
       + iDestruct "Hp" as (x y) "[>Hp Hs']". iDestruct "Hs'" as (Q) "(>Hx & HoQ & HQ & >Ho1 & >Ho4)".
          wp_load. iVs ("Hclose" with "[-Hγs Ho4 HΦ Hx HoQ HQ]").
          { iNext. iFrame. iExists xs, hd. iFrame. iExists m. iFrame.
            iDestruct (big_sepM_delete _ m with "[-]") as "?"=>//.
            iFrame. iExists #p'. iSplitR; auto. iExists (γx, γ1, γ3, γ4, γq), p'.
            iSplitR; first auto. iFrame.
            iLeft. iExists y. iFrame. }
          iVsIntro. wp_match. iApply ("HΦ" with "[-]"). iFrame.
          iExists Q. iFrame.
    - iExFalso. iApply (map_agree_none' _ _ _ m)=>//. iFrame "Hom".
      rewrite /ev. eauto.
  Qed.

  Definition flatten (f' f: val) :=
    (∀ P Q, (∀ x:val, {{ R ★ P x }} f x {{ v, R ★ Q x v }}) →
            (∀ x:val, {{ P x }} f' x {{ v, ▷ Q x v }}))%I.

  Lemma mk_flat_spec (f: val) :
    ∀ (Φ: val → iProp Σ),
      heapN ⊥ N →
      heap_ctx ★ R ★ (∀ f', □ flatten f' f -★ Φ f') ⊢ WP mk_flat f {{ Φ }}.
  Proof.
    iIntros (Φ HN) "(#Hh & HR & HΦ)".
    iVs (own_alloc (Excl ())) as (γr) "Ho2"; first done.
    iVs (own_alloc (● (∅: tokmR) ⋅ ◯ ∅)) as (γm) "[Hm _]"; first by rewrite -auth_both_op.
    iAssert (srv_tokm_inv γm) with "[Hm]" as "Hm"; first eauto.
    { iExists ∅. iFrame. by rewrite big_sepM_empty. }
    wp_seq. wp_bind (newlock _).
    iApply (newlock_spec _ (own γr (Excl ()) ★ R))%I=>//.
    iFrame "Hh Ho2 HR". iIntros (lk γlk) "#Hlk".
    wp_let. wp_bind (new_stack _).
    iApply (new_stack_spec' _ (p_inv γm γr f))=>//.
    iFrame "Hh Hm". iIntros (γ s) "#Hss".
    wp_let. iVsIntro. iApply "HΦ". rewrite /flatten.
    iAlways. iIntros (P Q) "#Hf".
    iIntros (x) "!# Hp". wp_let.
    wp_bind ((install _) _).
    iApply (install_spec _ P Q)=>//.
    iFrame "#". iFrame "Hp". iSplitR; first iApply "Hf".
    iIntros (p [[[[γx γ1] γ3] γ4] γq]) "(Ho3 & Hx & HoQ) Hev Hhd".
    wp_let. iApply loop_spec=>//.
    iFrame "#". iFrame.
    iIntros (? ?) "Hs".
    iDestruct "Hs" as (Q') "(Hx' & HoQ' & HQ')".
    destruct (decide (x = a)) as [->|Hneq].
    - iDestruct (saved_prop_agree with "[HoQ HoQ']") as "Heq"; first by iFrame.
      iNext. admit. (* iRewrite "Heq" in "HQ'". *)
    - iExFalso. iCombine "Hx" "Hx'" as "Hx".
      iDestruct (own_valid with "Hx") as %[_ H1].
      rewrite pair_op //= dec_agree_ne in H1=>//.
  Admitted.

End proof.
