(*
** MISC (Cluster E) — D0Cmacdef DEFERRAL fixture (NOT a faithful round-trip).
**
** The ATS `#macdef NAME = body` macro-definition is DEFERRED: the DEPLOYED stock
** parser (srcgen2/DATS/parsing_decl00.dats + the tread01 reader the trans02_from_fpath
** pipeline uses) has NO `#macdef` case — `D0Cmacdef` is BUILT only in the alternate
** `pread00_decl00.dats` reader, which is NOT wired into the deployed compiler. So a
** `#macdef` decl does not parse in deployed ATS3: it falls into error recovery and the
** stock L2 is a chain of poison nodes (D0Ctkerr/D0Ctkskp over `#macdef`/NAME/`=`/body),
** NOT a real D2Cmacdef. There is therefore NO faithful stock L2 to round-trip against.
**
** Even where macdef DOES parse (the pread00 path), it lowers to D2Cd1ecl(D1Cmacdef(...,
** dedf)) where `dedf` is a D1Cexp — a level-1 MACRO TREE (trans01_d0exp of the body).
** The pyfront's L0->L2-direct lowering builds L2 (d2exp) nodes, not L1 macro trees, so
** it cannot reconstruct the D1Cexp body (the SAME L1-machinery gap that defers
** `datasort`, whose raw L2 also embeds a D1Cdatasort node).
**
** This file is kept as a DEFERRAL MARKER only; it is NOT run through build-l2diff.
*)
(* #macdef m1 = 1 *)
