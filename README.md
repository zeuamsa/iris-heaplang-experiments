# IRIS EXAMPLES

Some example verification demonstrating the use of Iris.

## Prerequisites

This version is known to compile with:

 - Coq 8.6.1 / 8.7.0
 - Ssreflect 1.6.4
 - A development version of [Iris](https://gitlab.mpi-sws.org/FP/iris-coq/)
 - The coq86-devel branch of [Autosubst](https://github.com/uds-psl/autosubst)

The easiest way to install the correct versions of the dependencies is through
opam.  You will need the Coq and Iris opam repositories:

    opam repo add coq-released https://coq.inria.fr/opam/released
    opam repo add iris-dev https://gitlab.mpi-sws.org/FP/opam-dev.git

Once you got opam set up, run `make build-dep` to install the right versions
of the dependencies.

## Building

Run `make` to build the full development.

## Case Studies

This repository contains the following case studies:

* [barrier](theories/barrier): The implementation and proof of a barrier as
  described in "Higher-Order Ghost State" <http://doi.acm.org/10.1145/2818638>.
* [logrel](theories/logrel): the following logical relations from the paper <http://doi.acm.org/10.1145/3093333.3009855>:
  * STLC
      * Unary logical relations proving type safety
  * F_mu (System F with recursive types)
      * Unary logical relations proving type safety
  * F_mu_ref (System F with recursive types and references)
      * Unary logical relations proving type safety
	  * Binary logical relations for proving contextual refinements
  * F_mu_ref_conc (System F with recursive types, references and concurrency)
      * Unary logical relations proving type safety
	  * Binary logical relations for proving contextual refinements
	      * Proof of refinement for a pair of fine-grained/coarse-grained concurrent counter implementations
		  * Proof of refinement for a pair of fine-grained/coarse-grained concurrent stack implementations

## For Developers: How to update the Iris dependency

* Do the change in Iris, push it.
* Wait for CI to publish a new Iris version on the opam archive, then run
  `opam update iris-dev`.
* In iris-examples, change the `opam` file to depend on the new version.
* Run `make build-dep` (in iris-examples) to install the new version of Iris.
  You may have to do `make clean` as Coq will likely complain about .vo file
  mismatches.
