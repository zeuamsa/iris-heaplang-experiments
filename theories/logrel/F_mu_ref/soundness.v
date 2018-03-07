From iris_examples.logrel.F_mu_ref Require Export fundamental.
From iris.proofmode Require Import tactics.
From iris.program_logic Require Import adequacy.
From iris.base_logic Require Import auth.

Class heapPreG Σ := HeapPreG {
  heap_preG_iris :> invPreG Σ;
  heap_preG_heap :> gen_heapPreG loc val Σ
}.

Theorem soundness Σ `{heapPreG Σ} e τ e' thp σ σ' :
  (∀ `{heapG Σ}, [] ⊨ e : τ) →
  rtc step ([e], σ) (thp, σ') → e' ∈ thp →
  is_Some (to_val e') ∨ reducible e' σ'.
Proof.
  intros Hlog ??. cut (adequate NotStuck e σ (λ _, True)); first (intros [_ ?]; eauto).
  eapply (wp_adequacy Σ _); eauto.
  iIntros (Hinv).
  iMod (own_alloc (● to_gen_heap σ)) as (γ) "Hh".
  { apply (auth_auth_valid _ (to_gen_heap_valid _ _ σ)). }
  iModIntro. iExists (λ σ, own γ (● to_gen_heap σ)); iFrame.
  set (HeapΣ := (HeapG Σ Hinv (GenHeapG _ _ Σ _ _ _ γ))).
  iApply (wp_wand with "[]").
  - rewrite -(empty_env_subst e).
    iApply (Hlog HeapΣ [] []). iApply (@interp_env_nil _ HeapΣ).
  - auto.
Qed.

Corollary type_soundness e τ e' thp σ σ' :
  [] ⊢ₜ e : τ →
  rtc step ([e], σ) (thp, σ') → e' ∈ thp →
  is_Some (to_val e') ∨ reducible e' σ'.
Proof.
  intros ??. set (Σ := #[invΣ ; gen_heapΣ loc val]).
  set (HG := HeapPreG Σ _ _). 
  eapply (soundness Σ).
  - intros ?. by apply fundamental. 
  - eauto.
Qed.