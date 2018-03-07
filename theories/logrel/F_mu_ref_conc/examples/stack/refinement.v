From iris.algebra Require Import auth.
From iris.program_logic Require Import adequacy ectxi_language.
From iris_examples.logrel.F_mu_ref_conc Require Import soundness_binary.
From iris_examples.logrel.F_mu_ref_conc.examples Require Import lock.
From iris_examples.logrel.F_mu_ref_conc.examples.stack Require Import
  CG_stack FG_stack stack_rules.
From iris.proofmode Require Import tactics.

Definition stackN : namespace := nroot .@ "stack".

Section Stack_refinement.
  Context `{heapIG Σ, cfgSG Σ, inG Σ (authR stackUR)}.
  Notation D := (prodC valC valC -n> iProp Σ).
  Implicit Types Δ : listC D.

  Lemma FG_CG_counter_refinement :
    [] ⊨ FG_stack ≤log≤ CG_stack : TForall (TProd (TProd
           (TArrow (TVar 0) TUnit)
           (TArrow TUnit (TSum TUnit (TVar 0))))
           (TArrow (TArrow (TVar 0) TUnit) TUnit)).
  Proof.
    (* executing the preambles *)
    iIntros (Δ [|??] ρ ?) "#[Hspec HΓ]"; iIntros (j K) "Hj"; last first.
    { iDestruct (interp_env_length with "HΓ") as %[=]. } 
    iClear "HΓ". cbn -[FG_stack CG_stack].
    rewrite ?empty_env_subst /CG_stack /FG_stack.
    iApply wp_value; eauto.
    iExists (TLamV _); iFrame "Hj".
    clear j K. iAlways. iIntros (τi) "%". iIntros (j K) "Hj /=".
    iMod (step_tlam _ _ j K with "[Hj]") as "Hj"; eauto.
    iApply wp_pure_step_later; auto. iNext.
    iMod (steps_newlock _ _ j (AppRCtx (RecV _) :: K) with "[Hj]")
      as (l) "[Hj Hl]"; eauto.
    iMod (step_rec _ _ j K with "[$Hj]") as "Hj"; eauto.
    simpl.
    rewrite CG_locked_push_subst CG_locked_pop_subst
            CG_iter_subst CG_snap_subst. simpl. asimpl.
    iMod (step_alloc  _ _ j (AppRCtx (RecV _) :: K) with "[Hj]")
      as (stk') "[Hj Hstk']"; [| |simpl; by iFrame|]; auto.
    iMod (step_rec _ _ j K with "[$Hj]") as "Hj"; eauto.
    simpl.
    rewrite CG_locked_push_subst CG_locked_pop_subst
            CG_iter_subst CG_snap_subst. simpl. asimpl.
    iApply (wp_bind (fill [FoldCtx; AllocCtx; AppRCtx (RecV _)]));
      iApply wp_wand_l; iSplitR; [iIntros (v) "Hv"; iExact "Hv"|].
    iApply wp_alloc; first done. iNext; iIntros (istk) "Histk".
    iApply (wp_bind (fill [AppRCtx (RecV _)]));
      iApply wp_wand_l; iSplitR; [iIntros (v) "Hv"; iExact "Hv"|].
    iApply wp_alloc; first done. iNext; iIntros (stk) "Hstk".
    simpl. iApply wp_pure_step_later; trivial. iNext. simpl.
    rewrite FG_push_subst FG_pop_subst FG_iter_subst. simpl. asimpl.
    (* establishing the invariant *)
    iMod (own_alloc (● (∅ : stackUR))) as (γ) "Hemp"; first done.
    set (istkG := StackG _ _ γ).
    change γ with (@stack_name _ istkG).
    change H1 with (@stack_inG _ istkG).
    clearbody istkG. clear γ H1.
    iAssert (@stack_owns _ istkG _ ∅) with "[Hemp]" as "Hoe".
    { rewrite /stack_owns big_sepM_empty fmap_empty. iFrame "Hemp"; trivial. }
    iMod (stack_owns_alloc with "[$Hoe $Histk]") as "[Hoe Hls]".
    iAssert (StackLink τi (LocV istk, FoldV (InjLV UnitV))) with "[Hls]" as "HLK".
    { rewrite StackLink_unfold.
      iExists _, _. iSplitR; simpl; trivial.
      iFrame "Hls". iLeft. iSplit; trivial. }
    iAssert ((∃ istk v h, (stack_owns h)
                         ∗ stk' ↦ₛ v
                         ∗ stk ↦ᵢ (FoldV (LocV istk))
                         ∗ StackLink τi (LocV istk, v)
                         ∗ l ↦ₛ (#♭v false)
             )%I) with "[Hoe Hstk Hstk' HLK Hl]" as "Hinv".
    { iExists _, _, _. by iFrame "Hoe Hstk' Hstk Hl HLK". }
    iMod (inv_alloc stackN with "[Hinv]") as "#Hinv"; [iNext; iExact "Hinv"|].
    clear istk.
    Opaque stack_owns.
    (* splitting *)
    iApply wp_value; simpl; trivial.
    iExists (PairV (PairV (CG_locked_pushV _ _) (CG_locked_popV _ _)) (RecV _)).
    simpl. rewrite CG_locked_push_of_val CG_locked_pop_of_val. iFrame "Hj".
    iExists (_, _), (_, _); iSplit; eauto.
    iSplit.
    (* refinement of push and pop *)
    - iExists (_, _), (_, _); iSplit; eauto. iSplit.
      + (* refinement of push *)
        iAlways. clear j K. iIntros ( [v1 v2] ) "#Hrel". iIntros (j K) "Hj /=".
        rewrite -(FG_push_folding (Loc stk)).
        iLöb as "Hlat".
        rewrite {2}(FG_push_folding (Loc stk)).
        iApply wp_pure_step_later; auto using to_of_val.
        iNext.
        rewrite -(FG_push_folding (Loc stk)).
        asimpl.
        iApply (wp_bind (fill [AppRCtx (RecV _)]));
          iApply wp_wand_l; iSplitR; [iIntros (v) "Hv"; iExact "Hv"|].
        iInv stackN as (istk v h) "[Hoe [Hstk' [Hstk [HLK Hl]]]]" "Hclose".
        iApply (wp_load with "Hstk"). iNext. iIntros "Hstk".
        iMod ("Hclose" with "[Hoe Hstk' HLK Hl Hstk]") as "_".
        { iNext. iExists _, _, _; by iFrame "Hoe Hstk' HLK Hl Hstk". }
        clear v h.
        iApply wp_pure_step_later; auto using to_of_val.
        iModIntro. iNext. asimpl.
        iApply (wp_bind (fill [FoldCtx;
                               CasRCtx (LocV _) (FoldV (LocV _)); IfCtx _ _]));
          iApply wp_wand_l; iSplitR; [iIntros (w) "Hw"; iExact "Hw"|].
        iApply wp_alloc; simpl; trivial.
        iNext. iIntros (ltmp) "Hltmp".
        iApply (wp_bind (fill [IfCtx _ _]));
          iApply wp_wand_l; iSplitR; [iIntros (w) "H"; iExact "H"|].
        iInv stackN as (istk2 v h) "[Hoe [Hstk' [Hstk [HLK Hl]]]]" "Hclose".
        (* deciding whether CAS will succeed or fail *)
        destruct (decide (istk = istk2)) as [|Hneq]; subst.
        * (* CAS succeeds *)
          (* In this case, the specification pushes *)
          iMod "Hstk'". iMod "Hl".
          iMod (steps_CG_locked_push _ _ j K with "[Hj Hl Hstk']")
            as "[Hj [Hstk' Hl]]"; first solve_ndisj.
          { rewrite CG_locked_push_of_val. by iFrame "Hspec Hstk' Hj". }
          iApply (wp_cas_suc with "Hstk"); auto.
          iNext. iIntros "Hstk".
          iMod (stack_owns_alloc with "[$Hoe $Hltmp]") as "[Hoe Hpt]".
          iMod ("Hclose" with "[-Hj]") as "_".
          { iNext. iExists ltmp, _, _.
            iFrame "Hoe Hstk' Hstk Hl".
            do 2 rewrite StackLink_unfold.
            rewrite -StackLink_unfold.
            iExists _, _. iSplit; trivial.
            iFrame "Hpt". eauto 10. }
          iModIntro.
          iApply wp_pure_step_later; auto. iNext; iApply wp_value; trivial.
          iExists UnitV; eauto.
        * iApply (wp_cas_fail with "Hstk"); auto. congruence.
          iNext. iIntros "Hstk". iMod ("Hclose" with "[-Hj]").
          { iNext. iExists _, _, _. by iFrame "Hoe Hstk' Hstk Hl". }
          iApply wp_pure_step_later; auto. iModIntro. iNext. by iApply "Hlat".
      + (* refinement of pop *)
        iAlways. clear j K. iIntros ( [v1 v2] ) "[% %]".
        iIntros (j K) "Hj /="; simplify_eq/=.
        rewrite -(FG_pop_folding (Loc stk)).
        iLöb as "Hlat".
        rewrite {2}(FG_pop_folding (Loc stk)).
        iApply wp_pure_step_later; auto. iNext.
        rewrite -(FG_pop_folding (Loc stk)).
        asimpl.
        iApply (wp_bind (fill [UnfoldCtx; AppRCtx (RecV _)]));
          iApply wp_wand_l; iSplitR; [iIntros (v) "Hv"; iExact "Hv"|].
        iInv stackN as (istk v h) "[Hoe [Hstk' [Hstk [#HLK Hl]]]]" "Hclose".
        iApply (wp_load with "Hstk"). iNext. iIntros "Hstk".
        iPoseProof "HLK" as "HLK'".
        (* Checking whether the stack is empty *)
        rewrite {2}StackLink_unfold.
        iDestruct "HLK'" as (istk2 w) "[% [Hmpt [[% %]|HLK']]]"; simplify_eq/=.
        * (* The stack is empty *)
          iMod (steps_CG_locked_pop_fail with "[$Hspec $Hstk' $Hl $Hj]")
             as "[Hj [Hstk' Hl]]"; first solve_ndisj.
          iMod ("Hclose" with "[-Hj Hmpt]") as "_".
          { iNext. iExists _, _, _. by iFrame "Hoe Hstk' Hstk Hl". }
          iApply (wp_bind (fill [AppRCtx (RecV _)]));
            iApply wp_wand_l; iSplitR; [iModIntro; iIntros (w) "Hw"; iExact "Hw"|].
          iApply wp_pure_step_later; simpl; auto using to_of_val.
          iModIntro. iNext. iApply wp_value.
          iApply wp_pure_step_later; auto. iNext. asimpl.
          clear h.
          iApply (wp_bind (fill [AppRCtx (RecV _)]));
            iApply wp_wand_l; iSplitR; [iIntros (w) "Hw"; iExact "Hw"|].
          iClear "HLK".
          iInv stackN as (istk3 w h) "[Hoe [Hstk' [Hstk [HLK Hl]]]]" "Hclose".
          iDestruct (stack_owns_later_open_close with "Hoe Hmpt") as "[Histk HLoe]".
          iApply (wp_load with "Histk").
          iNext. iIntros "Histk". iMod ("Hclose" with "[-Hj]") as "_".
          { iNext. iExists _, _, _. iFrame "Hstk' Hstk HLK Hl".
            by iApply "HLoe". }
          iApply wp_pure_step_later; simpl; trivial.
          iModIntro. iNext. asimpl.
          iApply wp_pure_step_later; trivial.
          iNext. iApply wp_value; simpl; trivial. iExists (InjLV UnitV).
          iSplit; trivial. iLeft. iExists (_, _); repeat iSplit; simpl; trivial.
        * (* The stack is not empty *)
          iMod ("Hclose" with "[-Hj Hmpt HLK']") as "_".
          { iNext. iExists _, _, _. by iFrame "Hstk' Hstk HLK Hl". }
          iApply (wp_bind (fill [AppRCtx (RecV _)]));
            iApply wp_wand_l; iSplitR; [iModIntro; iIntros (w') "Hw"; iExact "Hw"|].
          iApply wp_pure_step_later; simpl; auto.
          iModIntro. iNext. iApply wp_value. iApply wp_pure_step_later; auto.
          iNext. asimpl.
          clear h.
          iApply (wp_bind (fill [AppRCtx (RecV _)]));
            iApply wp_wand_l; iSplitR; [iIntros (w') "Hw"; iExact "Hw"|].
          iClear "HLK".
          iInv stackN as (istk3 w' h) "[Hoe [Hstk' [Hstk [HLK Hl]]]]" "Hclose".
          iDestruct (stack_owns_later_open_close with "Hoe Hmpt") as "[Histk HLoe]".
          iApply (wp_load with "Histk"). iNext; iIntros "Histk".
          iDestruct ("HLoe" with "Histk") as "Hh".
          iMod ("Hclose" with "[-Hj Hmpt HLK']") as "_".
          { iNext. iExists _, _, _. by iFrame "Hstk' Hstk HLK Hl". }
          iApply wp_pure_step_later; auto.
          iModIntro. iNext. asimpl.
          iDestruct "HLK'" as (y1 z1 y2 z2) "[% HLK']". subst. simpl.
          iApply wp_pure_step_later; [simpl; by rewrite ?to_of_val |].
          iNext.
          iApply (wp_bind (fill [CasRCtx (LocV _) (FoldV (LocV _)); IfCtx _ _]));
            iApply wp_wand_l; iSplitR; [iIntros (w) "Hw"; iExact "Hw"|].
          asimpl. iApply wp_pure_step_later; auto.
          simpl. iNext. iApply wp_value.
          iApply (wp_bind (fill [IfCtx _ _]));
            iApply wp_wand_l; iSplitR; [iIntros (w) "Hw"; iExact "Hw"|].
          clear istk3 h. asimpl.
          iInv stackN as (istk3 w h) "[Hoe [Hstk' [Hstk [#HLK Hl]]]]" "Hclose".
          (* deciding whether CAS will succeed or fail *)
          destruct (decide (istk2 = istk3)) as [|Hneq]; subst.
          -- (* CAS succeeds *)
            (* In this case, the specification pushes *)
            iApply (wp_cas_suc with "Hstk"); simpl; auto.
            iNext. iIntros "Hstk {HLK'}". iPoseProof "HLK" as "HLK'".
            rewrite {2}StackLink_unfold.
            iDestruct "HLK'" as (istk4 w2) "[% [Hmpt' HLK']]"; simplify_eq/=.
            iDestruct (stack_mapstos_agree with "[Hmpt Hmpt']") as %?;
              first (iSplit; [iExact "Hmpt"| iExact "Hmpt'"]).
            iDestruct "HLK'" as "[[% %]|HLK']"; simplify_eq/=.
            iDestruct "HLK'" as (yn1 yn2 zn1 zn2)
                                   "[% [% [#Hrel HLK'']]]"; simplify_eq/=.
             (* Now we have proven that specification can also pop. *)
             rewrite CG_locked_pop_of_val.
             iMod (steps_CG_locked_pop_suc with "[$Hspec $Hstk' $Hl $Hj]")
                as "[Hj [Hstk' Hl]]"; first solve_ndisj.
             iMod ("Hclose" with "[-Hj]") as "_".
             { iNext. iIntros "{Hmpt Hmpt' HLK}". rewrite StackLink_unfold.
               iDestruct "HLK''" as (istk5 w2) "[% [Hmpt HLK]]"; simplify_eq/=.
               iExists istk5, _, _. iFrame "Hoe Hstk' Hstk Hl".
               rewrite StackLink_unfold.
               iExists _, _; iSplitR; trivial.
               by iFrame "HLK". }
             iApply wp_pure_step_later; auto. iModIntro. iNext.
             iApply (wp_bind (fill [InjRCtx])); iApply wp_wand_l;
               iSplitR; [iIntros (w) "Hw"; iExact "Hw"|].
             iApply wp_pure_step_later; auto. iApply wp_value.
             iNext. iApply wp_value; simpl.
             iExists (InjRV _); iFrame "Hj".
             iRight. iExists (_, _). iSplit; trivial.
          -- (* CAS will fail *)
            iApply (wp_cas_fail with "Hstk"); [rewrite /= ?to_of_val //; congruence..|].
            iNext. iIntros "Hstk". iMod ("Hclose" with "[-Hj]") as "_".
            { iNext. iExists _, _, _. by iFrame "Hoe Hstk' Hstk HLK Hl". }
            iApply wp_pure_step_later; auto. iModIntro. iNext. by iApply "Hlat".
    - (* refinement of iter *)
      iAlways. clear j K. iIntros ( [f1 f2] ) "/= #Hfs". iIntros (j K) "Hj".
      iApply wp_pure_step_later; auto using to_of_val. iNext.
      iMod (step_rec with "[$Hspec $Hj]") as "Hj"; [by rewrite to_of_val|solve_ndisj|].
      asimpl. rewrite FG_iter_subst CG_snap_subst CG_iter_subst. asimpl.
      replace (FG_iter (of_val f1)) with (of_val (FG_iterV (of_val f1)))
        by (by rewrite FG_iter_of_val).
      replace (CG_iter (of_val f2)) with (of_val (CG_iterV (of_val f2)))
        by (by rewrite CG_iter_of_val).
      iApply (wp_bind (fill [AppRCtx _])); iApply wp_wand_l;
        iSplitR; [iIntros (w) "Hw"; iExact "Hw"|].
      iInv stackN as (istk3 w h) "[Hoe [>Hstk' [>Hstk [#HLK >Hl]]]]" "Hclose".
      iMod (steps_CG_snap _ _ _ (AppRCtx _ :: K)
            with "[Hstk' Hj Hl]") as "[Hj [Hstk' Hl]]"; first solve_ndisj.
      { rewrite ?fill_app. simpl. by iFrame "Hspec Hstk' Hl Hj". }
      iApply (wp_load with "[$Hstk]"). iNext. iIntros "Hstk".
      iMod ("Hclose" with "[-Hj]") as "_".
      { iNext. iExists _, _, _; by iFrame "Hoe Hstk' Hstk HLK Hl". }
      clear h. iModIntro.
      rewrite ?fill_app /= -FG_iter_folding.
      iLöb as "Hlat" forall (istk3 w) "HLK".
      rewrite {2}FG_iter_folding.
      iApply wp_pure_step_later; simpl; trivial.
      rewrite -FG_iter_folding. asimpl. rewrite FG_iter_subst.
      iNext.
      iApply (wp_bind (fill [LoadCtx; CaseCtx _ _])); iApply wp_wand_l;
        iSplitR; [iIntros (v) "Hw"; iExact "Hw"|].
      iApply wp_pure_step_later; trivial. iApply wp_value. iNext.
      iApply (wp_bind (fill [CaseCtx _ _])); iApply wp_wand_l;
        iSplitR; [iIntros (v) "Hw"; iExact "Hw"|].
      rewrite StackLink_unfold.
      iDestruct "HLK" as (istk4 v) "[% [Hmpt HLK]]"; simplify_eq/=.
      iInv stackN as (istk5 v' h) "[Hoe [Hstk' [Hstk [HLK' Hl]]]]" "Hclose".
      iDestruct (stack_owns_later_open_close with "Hoe Hmpt") as "[Histk HLoe]".
      iApply (wp_load with "[$Histk]"). iNext. iIntros "Histk".
      iDestruct ("HLoe" with "Histk") as "Hh".
      iDestruct "HLK" as "[[% %]|HLK'']"; simplify_eq/=.
      * rewrite CG_iter_of_val.
        iMod (steps_CG_iter_end with "[$Hspec $Hj]") as "Hj"; first solve_ndisj.
        iMod ("Hclose" with "[-Hj]").
        { iNext. iExists _, _, _. by iFrame "Hh Hstk' Hstk Hl". }
        iApply wp_pure_step_later; trivial.
        iModIntro. iNext. iApply wp_value; trivial. iExists UnitV; eauto.
      * iDestruct "HLK''" as (yn1 yn2 zn1 zn2)
                              "[% [% [#Hrel HLK'']]]"; simplify_eq/=.
        rewrite CG_iter_of_val.
        iMod (steps_CG_iter with "[$Hspec $Hj]") as "Hj"; first solve_ndisj.
        iMod ("Hclose" with "[-Hj HLK'']") as "_".
        { iNext. iExists _, _, _. by iFrame "Hh Hstk' Hstk Hl". }
        simpl.
        iApply wp_pure_step_later; simpl; rewrite ?to_of_val; trivial.
        rewrite FG_iter_subst CG_iter_subst. asimpl.
        iModIntro. iNext.
        iApply (wp_bind (fill [AppRCtx _; AppRCtx (RecV _)]));
          iApply wp_wand_l; iSplitR; [iIntros (w') "Hw"; iExact "Hw"|].
        iApply wp_pure_step_later; simpl; rewrite ?to_of_val; trivial. iNext.
        iApply wp_value.
        iApply (wp_bind (fill [AppRCtx (RecV _)]));
          iApply wp_wand_l; iSplitR; [iIntros (w') "Hw"; iExact "Hw"|].
        rewrite StackLink_unfold.
        iDestruct "HLK''" as (istk6 w') "[% HLK]"; simplify_eq/=.
        iSpecialize ("Hfs" $! (yn1, zn1) with "Hrel").
        iSpecialize ("Hfs" $! _ (AppRCtx (RecV _) :: K)).
        iApply wp_wand_l; iSplitR "Hj"; [|iApply "Hfs"; by iFrame "#"].
        iIntros (u) "/="; iDestruct 1 as (z) "[Hj [% %]]".
        simpl. subst. asimpl.
        iMod (step_rec with "[$Hspec $Hj]") as "Hj"; [done..|].
        asimpl. rewrite CG_iter_subst. asimpl.
        replace (CG_iter (of_val f2)) with (of_val (CG_iterV (of_val f2)))
          by (by rewrite CG_iter_of_val).
        iMod (step_snd _ _ _ (AppRCtx _ :: K) with "[$Hspec Hj]") as "Hj";
          [| | |simpl; by iFrame "Hj"|]; rewrite ?to_of_val; auto.
        iApply wp_pure_step_later; trivial.
        iNext. simpl. rewrite FG_iter_subst. asimpl.
        replace (FG_iter (of_val f1)) with (of_val (FG_iterV (of_val f1)))
          by (by rewrite FG_iter_of_val).
        iApply (wp_bind (fill [AppRCtx _]));
          iApply wp_wand_l; iSplitR; [iIntros (w'') "Hw"; iExact "Hw"|].
        iApply wp_pure_step_later; auto using to_of_val.
        simpl. iNext. rewrite -FG_iter_folding. iApply wp_value.
        iApply ("Hlat" $! istk6 zn2 with "[Hj] [HLK]"); trivial.
        rewrite StackLink_unfold; iAlways; simpl.
        iDestruct "HLK" as "[Histk6 [HLK|HLK]]";
          iExists istk6, w'; iSplit; auto; iFrame "#".
        iRight. iDestruct "HLK" as (? ? ? ?) "(?&?&?&?)".
        iExists _, _, _, _; iFrame "#".
  Qed.
End Stack_refinement.

Theorem stack_ctx_refinement :
  [] ⊨ FG_stack ≤ctx≤ CG_stack : TForall (TProd (TProd
        (TArrow (TVar 0) TUnit)
        (TArrow TUnit (TSum TUnit (TVar 0))))
        (TArrow (TArrow (TVar 0) TUnit) TUnit)).
Proof.
  set (Σ := #[invΣ; gen_heapΣ loc val; GFunctor (authR cfgUR); GFunctor (authR stackUR)]).
  set (HG := soundness_unary.HeapPreIG Σ _ _).
  eapply (binary_soundness Σ); eauto using FG_stack_closed, CG_stack_closed.
  intros; apply FG_CG_counter_refinement.
Qed.