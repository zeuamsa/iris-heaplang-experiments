From stdpp Require Import namespaces.
From iris.heap_lang Require Export lifting notation.
From iris.program_logic Require Export atomic.
From iris_examples.logatom.rdcss Require Export gc.
Set Default Proof Using "Type".

(** A general logically atomic interface for conditional increment. *)
Record atomic_rdcss {Σ} `{!heapG Σ, !gcG Σ} := AtomicRdcss {
  (* -- operations -- *)
  new_rdcss : val;
  rdcss: val;
  get : val;
  (* -- other data -- *)
  name : Type;
  name_eqdec : EqDecision name;
  name_countable : Countable name;
  (* -- predicates -- *)
  is_rdcss (N : namespace) (γ : name) (v : val) : iProp Σ;
  rdcss_content (γ : name) (n : Z) : iProp Σ;
  (* -- predicate properties -- *)
  is_rdcss_persistent N γ v : Persistent (is_rdcss N γ v);
  rdcss_content_timeless γ n : Timeless (rdcss_content γ n);
  rdcss_content_exclusive γ n1 n2 : rdcss_content γ n1 -∗ rdcss_content γ n2 -∗ False;
  (* -- operation specs -- *)
  new_rdcss_spec N :
    N ## gcN → gc_inv -∗
    {{{ True }}}
        new_rdcss #()
    {{{ lln γ, RET lln ; is_rdcss N γ lln ∗ rdcss_content γ 0 }}};
  rdcss_spec N γ v lm (m1 n1 n2 : Z):
    is_rdcss N γ v -∗ is_gc_loc lm -∗
    <<< ∀ (m n: Z), gc_mapsto lm #m ∗ rdcss_content γ n >>>
        rdcss #lm v #m1 #n1 #n2 @((⊤∖↑N)∖↑gcN)
    <<< gc_mapsto lm #m ∗ rdcss_content γ (if decide (m = m1 ∧ n = n1) then n2 else n), RET #n >>>;
  get_spec N γ v:
    is_rdcss N γ v -∗
    <<< ∀ (n : Z), rdcss_content γ n >>>
        get v @(⊤∖↑N)
    <<< rdcss_content γ n, RET #n >>>;
}.
Arguments atomic_rdcss _ {_} {_}.


Existing Instances
  is_rdcss_persistent rdcss_content_timeless
  name_countable name_eqdec.

