From iris_examples.logrel.F_mu_ref_conc Require Export lang.
From iris_examples.logrel.F_mu_ref_conc.binary Require Export fundamental.
From iris.proofmode Require Import proofmode.
From iris.prelude Require Import options.

Export F_mu_ref_conc.

Inductive ctx_item :=
  | CTX_Rec
  | CTX_AppL (e2 : expr)
  | CTX_AppR (e1 : expr)
  (* Products *)
  | CTX_PairL (e2 : expr)
  | CTX_PairR (e1 : expr)
  | CTX_Fst
  | CTX_Snd
  (* Sums *)
  | CTX_InjL
  | CTX_InjR
  | CTX_CaseL (e1 : expr) (e2 : expr)
  | CTX_CaseM (e0 : expr) (e2 : expr)
  | CTX_CaseR (e0 : expr) (e1 : expr)
  (* Nat bin op *)
  | CTX_BinOpL (op : binop) (e2 : expr)
  | CTX_BinOpR (op : binop) (e1 : expr)
  (* If *)
  | CTX_IfL (e1 : expr) (e2 : expr)
  | CTX_IfM (e0 : expr) (e2 : expr)
  | CTX_IfR (e0 : expr) (e1 : expr)
  (* Recursive Types *)
  | CTX_Fold
  | CTX_Unfold
  (* Polymorphic Types *)
  | CTX_TLam
  | CTX_TApp
  (* Concurrency *)
  | CTX_Fork
  (* Reference Types *)
  | CTX_Alloc
  | CTX_Load
  | CTX_StoreL (e2 : expr)
  | CTX_StoreR (e1 : expr)
  (* Compare and swap used for fine-grained concurrency *)
  | CTX_CAS_L (e1 : expr) (e2 : expr)
  | CTX_CAS_M (e0 : expr) (e2 : expr)
  | CTX_CAS_R (e0 : expr) (e1 : expr).

Definition fill_ctx_item (ctx : ctx_item) (e : expr) : expr :=
  match ctx with
  | CTX_Rec => Rec e
  | CTX_AppL e2 => App e e2
  | CTX_AppR e1 => App e1 e
  | CTX_PairL e2 => Pair e e2
  | CTX_PairR e1 => Pair e1 e
  | CTX_Fst => Fst e
  | CTX_Snd => Snd e
  | CTX_InjL => InjL e
  | CTX_InjR => InjR e
  | CTX_CaseL e1 e2 => Case e e1 e2
  | CTX_CaseM e0 e2 => Case e0 e e2
  | CTX_CaseR e0 e1 => Case e0 e1 e
  | CTX_BinOpL op e2 => BinOp op e e2
  | CTX_BinOpR op e1 => BinOp op e1 e
  | CTX_IfL e1 e2 => If e e1 e2
  | CTX_IfM e0 e2 => If e0 e e2
  | CTX_IfR e0 e1 => If e0 e1 e
  | CTX_Fold => Fold e
  | CTX_Unfold => Unfold e
  | CTX_TLam => TLam e
  | CTX_TApp => TApp e
  | CTX_Fork => Fork e
  | CTX_Alloc => Alloc e
  | CTX_Load => Load e
  | CTX_StoreL e2 => Store e e2
  | CTX_StoreR e1 => Store e1 e
  | CTX_CAS_L e1 e2 => CAS e e1 e2
  | CTX_CAS_M e0 e2 => CAS e0 e e2
  | CTX_CAS_R e0 e1 => CAS e0 e1 e
  end.

Definition ctx := list ctx_item.

Definition fill_ctx (K : ctx) (e : expr) : expr := foldr fill_ctx_item e K.

(** typed ctx *)
Inductive typed_ctx_item :
    ctx_item ??? list type ??? type ??? list type ??? type ??? Prop :=
  | TP_CTX_Rec ?? ?? ??' :
     typed_ctx_item CTX_Rec (TArrow ?? ??' :: ?? :: ??) ??' ?? (TArrow ?? ??')
  | TP_CTX_AppL ?? e2 ?? ??' :
     typed ?? e2 ?? ???
     typed_ctx_item (CTX_AppL e2) ?? (TArrow ?? ??') ?? ??'
  | TP_CTX_AppR ?? e1 ?? ??' :
     typed ?? e1 (TArrow ?? ??') ???
     typed_ctx_item (CTX_AppR e1) ?? ?? ?? ??'
  | TP_CTX_PairL ?? e2 ?? ??' :
     typed ?? e2 ??' ???
     typed_ctx_item (CTX_PairL e2) ?? ?? ?? (TProd ?? ??')
  | TP_CTX_PairR ?? e1 ?? ??' :
     typed ?? e1 ?? ???
     typed_ctx_item (CTX_PairR e1) ?? ??' ?? (TProd ?? ??')
  | TP_CTX_Fst ?? ?? ??' :
     typed_ctx_item CTX_Fst ?? (TProd ?? ??') ?? ??
  | TP_CTX_Snd ?? ?? ??' :
     typed_ctx_item CTX_Snd ?? (TProd ?? ??') ?? ??'
  | TP_CTX_InjL ?? ?? ??' :
     typed_ctx_item CTX_InjL ?? ?? ?? (TSum ?? ??')
  | TP_CTX_InjR ?? ?? ??' :
     typed_ctx_item CTX_InjR ?? ??' ?? (TSum ?? ??')
  | TP_CTX_CaseL ?? e1 e2 ??1 ??2 ??' :
     typed (??1 :: ??) e1 ??' ??? typed (??2 :: ??) e2 ??' ???
     typed_ctx_item (CTX_CaseL e1 e2) ?? (TSum ??1 ??2) ?? ??'
  | TP_CTX_CaseM ?? e0 e2 ??1 ??2 ??' :
     typed ?? e0 (TSum ??1 ??2) ??? typed (??2 :: ??) e2 ??' ???
     typed_ctx_item (CTX_CaseM e0 e2) (??1 :: ??) ??' ?? ??'
  | TP_CTX_CaseR ?? e0 e1 ??1 ??2 ??' :
     typed ?? e0 (TSum ??1 ??2) ??? typed (??1 :: ??) e1 ??' ???
     typed_ctx_item (CTX_CaseR e0 e1) (??2 :: ??) ??' ?? ??'
  | TP_CTX_IfL ?? e1 e2 ?? :
     typed ?? e1 ?? ??? typed ?? e2 ?? ???
     typed_ctx_item (CTX_IfL e1 e2) ?? (TBool) ?? ??
  | TP_CTX_IfM ?? e0 e2 ?? :
     typed ?? e0 (TBool) ??? typed ?? e2 ?? ???
     typed_ctx_item (CTX_IfM e0 e2) ?? ?? ?? ??
  | TP_CTX_IfR ?? e0 e1 ?? :
     typed ?? e0 (TBool) ??? typed ?? e1 ?? ???
     typed_ctx_item (CTX_IfR e0 e1) ?? ?? ?? ??
  | TP_CTX_BinOpL op ?? e2 :
     typed ?? e2 TNat ???
     typed_ctx_item (CTX_BinOpL op e2) ?? TNat ?? (binop_res_type op)
  | TP_CTX_BinOpR op e1 ?? :
     typed ?? e1 TNat ???
     typed_ctx_item (CTX_BinOpR op e1) ?? TNat ?? (binop_res_type op)
  | TP_CTX_Fold ?? ?? :
     typed_ctx_item CTX_Fold ?? ??.[(TRec ??)/] ?? (TRec ??)
  | TP_CTX_Unfold ?? ?? :
     typed_ctx_item CTX_Unfold ?? (TRec ??) ?? ??.[(TRec ??)/]
  | TP_CTX_TLam ?? ?? :
     typed_ctx_item CTX_TLam (subst (ren (+1)) <$> ??) ?? ?? (TForall ??)
  | TP_CTX_TApp ?? ?? ??' :
     typed_ctx_item CTX_TApp ?? (TForall ??) ?? ??.[??'/]
  | TP_CTX_Fork ?? :
     typed_ctx_item CTX_Fork ?? TUnit ?? TUnit
  | TPCTX_Alloc ?? ?? :
     typed_ctx_item CTX_Alloc ?? ?? ?? (Tref ??)
  | TP_CTX_Load ?? ?? :
     typed_ctx_item CTX_Load ?? (Tref ??) ?? ??
  | TP_CTX_StoreL ?? e2 ?? :
     typed ?? e2 ?? ??? typed_ctx_item (CTX_StoreL e2) ?? (Tref ??) ?? TUnit
  | TP_CTX_StoreR ?? e1 ?? :
     typed ?? e1 (Tref ??) ???
     typed_ctx_item (CTX_StoreR e1) ?? ?? ?? TUnit
  | TP_CTX_CasL ?? e1  e2 ?? :
     EqType ?? ??? typed ?? e1 ?? ??? typed ?? e2 ?? ???
     typed_ctx_item (CTX_CAS_L e1 e2) ?? (Tref ??) ?? TBool
  | TP_CTX_CasM ?? e0 e2 ?? :
     EqType ?? ??? typed ?? e0 (Tref ??) ??? typed ?? e2 ?? ???
     typed_ctx_item (CTX_CAS_M e0 e2) ?? ?? ?? TBool
  | TP_CTX_CasR ?? e0 e1 ?? :
     EqType ?? ??? typed ?? e0 (Tref ??) ??? typed ?? e1 ?? ???
     typed_ctx_item (CTX_CAS_R e0 e1) ?? ?? ?? TBool.

Lemma typed_ctx_item_typed k ?? ?? ??' ??' e :
  typed ?? e ?? ??? typed_ctx_item k ?? ?? ??' ??' ???
  typed ??' (fill_ctx_item k e) ??'.
Proof. induction 2; simpl; eauto using typed. Qed.

Inductive typed_ctx: ctx ??? list type ??? type ??? list type ??? type ??? Prop :=
  | TPCTX_nil ?? ?? :
     typed_ctx nil ?? ?? ?? ??
  | TPCTX_cons ??1 ??1 ??2 ??2 ??3 ??3 k K :
     typed_ctx_item k ??2 ??2 ??3 ??3 ???
     typed_ctx K ??1 ??1 ??2 ??2 ???
     typed_ctx (k :: K) ??1 ??1 ??3 ??3.

Lemma typed_ctx_typed K ?? ?? ??' ??' e :
  typed ?? e ?? ??? typed_ctx K ?? ?? ??' ??' ??? typed ??' (fill_ctx K e) ??'.
Proof. induction 2; simpl; eauto using typed_ctx_item_typed. Qed.

Lemma typed_ctx_n_closed K ?? ?? ??' ??' e :
  (??? f, e.[upn (length ??) f] = e) ??? typed_ctx K ?? ?? ??' ??' ???
  ??? f, (fill_ctx K e).[upn (length ??') f] = (fill_ctx K e).
Proof.
  intros H1 H2; induction H2; simpl; auto.
  rename select (typed_ctx_item _ _ _ _ _) into Hty.
  induction Hty => f; asimpl; simpl in *;
    repeat match goal with H : _ |- _ => rewrite fmap_length in H end;
    try f_equal;
    eauto using typed_n_closed;
    try match goal with H : _ |- _ => eapply (typed_n_closed _ _ _ H) end.
Qed.

Definition ctx_refines (?? : list type)
    (e e' : expr) (?? : type) :=
  typed ?? e ?? ??? typed ?? e' ?? ???
  ??? K thp ?? v,
  typed_ctx K ?? ?? [] TUnit ???
  rtc erased_step ([fill_ctx K e], ???) (of_val v :: thp, ??) ???
  ??? thp' ??' v', rtc erased_step ([fill_ctx K e'], ???) (of_val v' :: thp', ??').
Notation "?? ??? e '???ctx???' e' : ??" :=
  (ctx_refines ?? e e' ??) (at level 74, e, e', ?? at next level).

Ltac fold_interp :=
  match goal with
  | |- context [ interp_expr (interp_arrow (interp ?A) (interp ?A'))
                            ?B (?C, ?D) ] =>
    change (interp_expr (interp_arrow (interp A) (interp A')) B (C, D)) with
    (interp_expr (interp (TArrow A A')) B (C, D))
  | |- context [ interp_expr (interp_prod (interp ?A) (interp ?A'))
                            ?B (?C, ?D) ] =>
    change (interp_expr (interp_prod (interp A) (interp A')) B (C, D)) with
    (interp_expr (interp (TProd A A')) B (C, D))
  | |- context [ interp_expr (interp_prod (interp ?A) (interp ?A'))
                            ?B (?C, ?D) ] =>
    change (interp_expr (interp_prod (interp A) (interp A')) B (C, D)) with
    (interp_expr (interp (TProd A A')) B (C, D))
  | |- context [ interp_expr (interp_sum (interp ?A) (interp ?A'))
                            ?B (?C, ?D) ] =>
    change (interp_expr (interp_sum (interp A) (interp A')) B (C, D)) with
    (interp_expr (interp (TSum A A')) B (C, D))
  | |- context [ interp_expr (interp_rec (interp ?A)) ?B (?C, ?D) ] =>
    change (interp_expr (interp_rec (interp A)) B (C, D)) with
    (interp_expr (interp (TRec A)) B (C, D))
  | |- context [ interp_expr (interp_forall (interp ?A))
                            ?B (?C, ?D) ] =>
    change (interp_expr (interp_forall (interp A)) B (C, D)) with
    (interp_expr (interp (TForall A)) B (C, D))
  | |- context [ interp_expr (interp_ref (interp ?A))
                            ?B (?C, ?D) ] =>
    change (interp_expr (interp_ref (interp A)) B (C, D)) with
    (interp_expr (interp (Tref A)) B (C, D))
  end.

Section bin_log_related_under_typed_ctx.
  Context `{heapIG ??, cfgSG ??}.

  Lemma bin_log_related_under_typed_ctx ?? e e' ?? ??' ??' K :
    (??? f, e.[upn (length ??) f] = e) ???
    (??? f, e'.[upn (length ??) f] = e') ???
    typed_ctx K ?? ?? ??' ??' ???
    ?? ??? e ???log??? e' : ?? -??? ??' ??? fill_ctx K e ???log??? fill_ctx K e' : ??'.
  Proof.
    revert ?? ?? ??' ??' e e'.
    induction K as [|k K IHK]=> ?? ?? ??' ??' e e' H1 H2; simpl.
    { inversion_clear 1; trivial. }
    inversion_clear 1 as [|? ? ? ? ? ? ? ? Hx1 Hx2].
    iIntros "#H".
    iPoseProof (IHK with "H") as "H'"; [done|done|done|].
    iClear "H".
    inversion Hx1; subst; simpl; try fold_interp.
    - iApply bin_log_related_rec; done.
    - iApply bin_log_related_app; last iApply binary_fundamental; done.
    - iApply bin_log_related_app; first iApply binary_fundamental; done.
    - iApply bin_log_related_pair; last iApply binary_fundamental; done.
    - iApply bin_log_related_pair; first iApply binary_fundamental; done.
    - iApply bin_log_related_fst; eauto.
    - iApply bin_log_related_snd; eauto.
    - iApply bin_log_related_injl; eauto.
    - iApply bin_log_related_injr; eauto.
    - iApply bin_log_related_case;
        [|iApply binary_fundamental|iApply binary_fundamental]; done.
    - iApply bin_log_related_case;
        [iApply binary_fundamental| |iApply binary_fundamental]; done.
    - iApply bin_log_related_case;
        [iApply binary_fundamental|iApply binary_fundamental|]; done.
    - iApply bin_log_related_if;
        [|iApply binary_fundamental|iApply binary_fundamental]; done.
    - iApply bin_log_related_if;
        [iApply binary_fundamental| |iApply binary_fundamental]; done.
    - iApply bin_log_related_if;
        [iApply binary_fundamental|iApply binary_fundamental|]; done.
    - iApply bin_log_related_nat_binop; [|iApply binary_fundamental]; done.
    - iApply bin_log_related_nat_binop; [iApply binary_fundamental|]; done.
    - iApply bin_log_related_fold; done.
    - iApply bin_log_related_unfold; done.
    - iApply bin_log_related_tlam; done.
    - iApply bin_log_related_tapp; done.
    - iApply bin_log_related_fork; done.
    - iApply bin_log_related_alloc; done.
    - iApply bin_log_related_load; done.
    - iApply bin_log_related_store; [|iApply binary_fundamental]; done.
    - iApply bin_log_related_store; [iApply binary_fundamental|]; done.
    - iApply bin_log_related_CAS;
        [done| |iApply binary_fundamental|iApply binary_fundamental]; done.
    - iApply bin_log_related_CAS;
        [done|iApply binary_fundamental| |iApply binary_fundamental]; done.
    - iApply bin_log_related_CAS;
        [done|iApply binary_fundamental|iApply binary_fundamental|]; done.
  Qed.
End bin_log_related_under_typed_ctx.
