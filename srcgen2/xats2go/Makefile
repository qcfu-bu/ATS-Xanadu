########################################################################
# xats2go — INCREMENTAL / SEPARATE-COMPILATION BUILD  (milestone M2.2)
#
# Fast dev cycle for the Go backend emitter.  Across an edit cycle the ONLY
# things that change are our srcgen2/DATS/*.dats emitter sources (usually ONE
# at a time).  Everything else is FIXED and built/cached ONCE:
#
#   lib2xatsopt.js  — 171MB prebuilt frontend lib.  NEVER rebuilt here.
#   lib2xats2cc.js  — reused from frontend/BUILD (intrep0 + trxd3i0/tryd3i0).
#   lib2xats2js.js  — the JS-oracle backend, reused from frontend/BUILD
#                     (built once from xats2js sources if absent), then cached.
#   i0varfst+tokenfpr JS shim — regenerated only when the bundle changes.
#
# So the per-edit cost is:  re-transpile JUST the changed .dats  ->
# re-namespace it  ->  re-concat lib2xats2go.js  ->  re-link the emitter
# bundle  ->  run the test(s).  NOT re-transpiling 18 files; NOT rebuilding
# any fixed lib.
#
# This Makefile is the new FAST PATH; build-go.sh / run-suite.sh are kept as
# thin wrappers over it (legacy entry points still work).
#
# GNU make 3.81 compatible (macOS system make).  `make -j` is supported for
# the per-file transpile step.
#
#   make            # build the emitter bundle (incremental)
#   make -j         # cold build, parallel transpiles
#   make suite      # run the 10-test differential-vs-JS oracle, summarize
#   make run/NAME   # one test through the oracle (e.g. make run/test01_xats2go)
#   make TEST=path test   # one test by path
#   make clean      # remove emitter artifacts (keep cached fixed libs)
#   make cleanall   # also remove the cached fixed libs (NEVER lib2xatsopt.js)
########################################################################

SHELL := /bin/bash

########################################################################
# Toolchain paths (all verified present; see BUILD-NOTES.md).
########################################################################
XATSHOME  ?= /Users/qcfu/Projects/ATS-Xanadu
export XATSHOME   # jsemit00 reads XATSHOME from the ENV to resolve /prelude/*
SRCGEN1   := $(XATSHOME)/srcgen1
SRCGEN2   := $(XATSHOME)/srcgen2
FRONTEND  := $(XATSHOME)/frontend
XATS2GO   := $(SRCGEN2)/xats2go/srcgen2
RUNTIMEGO := $(SRCGEN2)/xats2go/runtime/xatsgo
JSSHIM    := $(SRCGEN2)/xats2go/runtime/jsshim/gen-i0varfst-shim.sh

# ATS3 -> JS transpiler (jsemit00, same one lib2xatsopt.js was built with).
JSEMIT  := $(XATSHOME)/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js
LIB2OPT := $(SRCGEN2)/lib/lib2xatsopt.js
LIB2CC  := $(FRONTEND)/BUILD/lib2xats2cc.js
# LIB2JS: the JS differential oracle (reused).  NB: no inline `# comment` here —
# a trailing comment leaves trailing SPACES in the value, which break the
# `[ -f "$(LIB2JS)" ]` shell test below (the path would carry the spaces).
LIB2JS  := $(FRONTEND)/BUILD/lib2xats2js.js

NODE := node --stack-size=8801

# Build areas.  Shared/cached libs live in BUILD/; the per-`.dats` transpiles
# live in BUILD/JS/ (mirrors the stock Makefile_xjsemit layout); per-test
# scratch lives under BUILD/<name>/.
BUILD   := $(XATS2GO)/BUILD
JSDIR   := $(BUILD)/JS

# NODE_COMPILE_CACHE (Node 22+/26): cache the V8 bytecode of the ~200MB bundle
# so repeated `node bundle.js` runs skip parse/compile.  Exported on the ENV so
# every node invocation that runs a large bundle (emitter + JS oracle) reuses
# the compiled bytecode.  Pure performance; does not change any emitted byte.
V8CACHE := $(BUILD)/.v8cache
export NODE_COMPILE_CACHE := $(V8CACHE)

DATSDIR := $(XATS2GO)/DATS
UTILDIR := $(XATS2GO)/UTIL
TESTDIR := $(XATS2GO)/TEST

# Minimum line count below which a transpile is considered FAILED (a `.dats`
# with a syntax error silently produces tiny output).
MINLINES := 3

########################################################################
# THE EMITTER SOURCE LIST  (ONE obvious place — add a new go1emit_*.dats
# here in dependency / concat order; emitter files go AFTER the env
# [xats2go_myenv0] and BEFORE the tmplib [xats2go_tmplib], which MUST be
# last).  Mirrors build-go.sh's GO_DATS exactly.
#
# The ORDER of this list is load-bearing TWICE:
#   (1) it is the concat order of lib2xats2go.js, and
#   (2) it FIXES the per-file namespace index (100,101,... by position).
# So a file's namespace index is a pure function of its NAME's position in
# this list — independent of build order (`make -j` safe) and stable across
# edits (only appending changes nothing already assigned).
########################################################################
GO_DATS := \
  intrep1.dats \
  intrep1_print0.dats \
  intrep1_utils0.dats \
  go1emit_tytab0.dats \
  go1emit_byref0.dats \
  trxi0i1.dats \
  trxi0i1_myenv0.dats \
  trxi0i1_dynexp.dats \
  trxi0i1_decl00.dats \
  xats2go_myenv0.dats \
  go1emit_styp0.dats \
  go1emit_utils0.dats \
  go1emit_dynexp.dats \
  go1emit_decl00.dats \
  go1emit.dats \
  xats2go_tmplib.dats

DRIVER := $(UTILDIR)/xats2go_goemit01.dats

# xats2js source set — used ONLY for the from-source fallback that builds the
# JS-oracle lib2xats2js.js when frontend/BUILD/lib2xats2js.js is absent (it is
# present here, so this is a rarely-taken safety net).  From build-m0b.sh.
XATS2JS_DATS := \
  intrep1.dats intrep1_print0.dats intrep1_utils0.dats \
  trxi0i1.dats trxi0i1_myenv0.dats trxi0i1_dynexp.dats trxi0i1_decl00.dats \
  xats2js.dats xats2js_myenv0.dats xats2js_utils0.dats xats2js_dynexp.dats \
  xats2js_decl00.dats \
  js1emit.dats js1emit_utils0.dats js1emit_dynexp.dats js1emit_decl00.dats \
  xats2js_tmplib.dats

########################################################################
# xats2go MIGRATION (exceptions): the LOCAL, SELF-OWNED copy of the xats2cc
# D3->intrep0 stage, EXTENDED with [I0Etry0] + the D3Etry0/D3Eraise lowering
# (trxd3i0) + the tryd3i0 pass-throughs.  We BUILD lib2xats2cc.js from THIS set
# (instead of reusing the INCOMPLETE frontend/BUILD/lib2xats2cc.js, whose
# intrep0 has no I0Etry0 and whose trxd3i0 never lowers try/raise).  [I0Etry0]
# is APPENDED as the last i0exp_node constructor, so every pre-existing datacon
# stamp (the JS XATSCTAG tags) is preserved -> the JS-oracle lib2xats2js.js
# (compiled against the old tags) stays tag-compatible.  Source order mirrors
# xats2cc/srcgen1/Makefile_xjsemit SRCDATS (build-m0b.sh's build_backend_lib).
########################################################################
# NB: the local stage lives at srcgen2/xats2go/xats2cc/ (a sibling of the inner
# "srcgen2" dir, NOT under it), so it is $(SRCGEN2)/xats2go/xats2cc — do NOT use
# $(XATS2GO) here ($(XATS2GO) = $(SRCGEN2)/xats2go/srcgen2, one level too deep).
XATS2CC_ROOT  := $(SRCGEN2)/xats2go/xats2cc/srcgen1
XATS2CC_LOCAL := $(XATS2CC_ROOT)/DATS
XATS2CC_DATS := \
  intrep0.dats \
  intrep0_print0.dats \
  intrep0_utils0.dats \
  trxd3i0.dats \
  trxd3i0_print0.dats \
  trxd3i0_myenv0.dats \
  trxd3i0_statyp.dats \
  trxd3i0_dynexp.dats \
  trxd3i0_decl00.dats \
  tryd3i0.dats \
  tryd3i0_myenv0.dats \
  tryd3i0_dynexp.dats \
  tryd3i0_decl00.dats \
  xats2cc_tmplib.dats
# All .sats/.dats/.hats in the local stage — prerequisites so an edit to ANY of
# them rebuilds lib2xats2cc.js (and thus the bundle).
XATS2CC_SRCALL := $(wildcard $(XATS2CC_ROOT)/SATS/*.sats) \
                  $(wildcard $(XATS2CC_ROOT)/DATS/*.dats) \
                  $(wildcard $(XATS2CC_ROOT)/HATS/*.hats)

# Per-file transpile (out0) and per-file namespaced fragment (ns) targets.
OUT0 := $(patsubst %.dats, $(JSDIR)/%_dats_out0.js, $(GO_DATS))
NSJS := $(patsubst %.dats, $(JSDIR)/%_dats_ns.js,   $(GO_DATS))

# The built/cached artifacts.
LIB2GO  := $(BUILD)/lib2xats2go.js
DRV_GO  := $(BUILD)/xats2go_goemit01_dats.js
JDRV    := $(BUILD)/xats2js_jsemit01_dats.js
# Cached reuse of the prebuilt frontend libs (symlink/copy targets).
# No inline comments here either — keep these values whitespace-clean.
LIB2CC_C := $(BUILD)/lib2xats2cc.js
LIB2JS_C := $(BUILD)/lib2xats2js.js

# The reusable, NON-test-specific part of the emitter bundle (runtime +
# js1·opt + js2·cc + js3·go + driver), shim prepended.  Linked once, reused
# for every test run.
GOPATCHED := $(BUILD)/xats2go-bundle.patched.js
# The JS-oracle reference bundle (runtime + js1·opt + js2·cc + js3·JS + JS
# driver), shim prepended.  Test-INDEPENDENT (the source is passed as argv), so
# it is linked ONCE and reused for every oracle run.
JSPATCHED := $(BUILD)/xats2js-ref.patched.js

# CACHED namespace-sed'd FIXED libs — pure functions of FIXED inputs, so caching
# is semantically identical to the inline sed (the sed only rewrites `jsx<NNN>tnm`
# tokens; the inputs never change → built ONCE, reused on every relink/oracle).
OPT_JS1 := $(BUILD)/lib2xatsopt.js1.js
CC_JS2  := $(BUILD)/lib2xats2cc.js2.js

# xats2go MIGRATION (JS-oracle stamp coordination): adding [I0Etry0] to intrep0
# shifts the GLOBAL declaration-stamp counter, so EVERY function in the NEW
# lib2xats2cc gets a +N stamp (e.g. i0parsed_of_trxd3i0 1598 -> 1601).  The Go
# bundle is fully consistent (its driver + lib2xats2go are RE-transpiled against
# the local extended intrep0, so they reference the new stamps).  But the
# JS-oracle's driver (JDRV, from xats2js/srcgen2 -> global xats2cc) and its
# lib2xats2js were built against the OLD stamps -> they would crash against the
# new lib2xats2cc ("i0parsed_of_trxd3i0_1598 is not defined").
#
# RESOLUTION: the two bundles are INDEPENDENT, so the js2 slot need not be
# shared.  The Go bundle uses the NEW local cc ($(CC_JS2)); the JS-oracle bundle
# uses the OLD frontend cc ($(CC_JS2_OLD)) — internally consistent with the OLD
# JS driver + lib2xats2js (all stamp-1598).  The 58 conformance tests use no
# try/raise, so the JS reference is byte-identical to before; the differential
# oracle stays valid.  (try/raise lowering is a GO-only concern this chunk.)
LIB2CC_OLD := $(FRONTEND)/BUILD/lib2xats2cc.js
CC_JS2_OLD := $(BUILD)/lib2xats2cc.old.js2.js

# CACHED i0varfst(+tokenfpr) shims.  The shim resolves ONLY names from FIXED libs
# (the 6 i0varfst_* + i0var_dvar$get/d2var_get_stmp/stamp_get_uint from
# lib2xats2cc; tokenfpr from lib2xats2js for the JS oracle).  None of those names
# contain a `jsx<NNN>tnm` token, so the namespace-sed never rewrites them and the
# stamped names are identical in the raw lib and in the linked bundle — hence the
# shim can be generated ONCE from the cached fixed libs and reused.
#   GO_SHIM : scans cc.js2 only (the Go bundle never references tokenfpr).
#   JS_SHIM : scans cc.js2 + the JS-oracle lib (so the tokenfpr block is emitted).
GO_SHIM := $(BUILD)/i0varfst-shim.go.js
JS_SHIM := $(BUILD)/i0varfst-shim.js.js

########################################################################
# Per-file NAMESPACE INDEX:  position of a file in $(GO_DATS), starting at 100.
#   index("intrep1.dats") = 100, index("intrep1_print0.dats") = 101, ...
# Pure function of the NAME's position -> stable + build-order-independent.
# 3-digit is mandatory (the link sed matches exactly `jsx(...)tnm`); the list
# has 14 entries (100..113), all 3 digits, so this holds.  The index is
# computed inline in the `%_dats_ns.js` recipe below (STEP B), which walks
# $(GO_DATS) for the target's own name -- so a `make -j` parallel build assigns
# the SAME index as a sequential one (verified: byte-identical lib2xats2go.js).
########################################################################

########################################################################
# RUNTIME prefix for the emitter bundle (verbatim from build-m0b.sh /
# build-go.sh's RUNTIME=(...)).
########################################################################
S2R := $(SRCGEN2)/xats2js/srcgenx/xshared/runtime
S1R := $(SRCGEN1)/xats2js/srcgenx/xshared/runtime
RUNTIME := \
  $(S2R)/xats2js_js1emit.js \
  $(S2R)/srcgen2_precats.js \
  $(S1R)/srcgen1_prelude.js \
  $(S1R)/srcgen1_prelude_node.js \
  $(S1R)/srcgen1_xatslib_node.js

# Node-side prelude runtime used to RUN the emitted JS reference program.
NS2R := $(SRCGEN2)/xats2js/srcgen1/xshared/runtime

########################################################################
.PHONY: all bundle suite psuite clean cleanall test help dirs check-go selfhost-smoke selfhost-strict smoke-selfhost
.DEFAULT_GOAL := bundle

# The per-file transpiles and namespaced fragments are the WHOLE POINT of
# incremental builds — they MUST survive between runs (otherwise make would
# treat them as throwaway intermediates in the .dats -> ns -> lib chain and
# delete them, forcing a full re-transpile every time).  .SECONDARY with no
# prerequisites disables intermediate-file deletion for ALL targets; we also
# list them under .PRECIOUS to be explicit/robust.
.SECONDARY:
.PRECIOUS: $(OUT0) $(NSJS)

all: bundle

help:
	@echo "xats2go Makefile targets:"
	@echo "  make            build the emitter bundle (incremental)"
	@echo "  make -j         cold/parallel transpile + bundle"
	@echo "  make suite      differential-vs-JS oracle (sequential) + summary"
	@echo "  make -jN psuite differential-vs-JS oracle (PARALLEL) + summary"
	@echo "  make selfhost-smoke   structural guard for backend-source emission"
	@echo "  make selfhost-strict  stricter self-hosting gate for unhandled/internal routing"
	@echo "  make run/NAME   one test through the oracle"
	@echo "  make TEST=path test   one test by path"
	@echo "  make clean      remove emitter artifacts (keep cached fixed libs)"
	@echo "  make cleanall   also remove cached fixed libs (NEVER lib2xatsopt.js)"

dirs:
	@mkdir -p $(JSDIR)

########################################################################
# STEP A — per-`.dats` transpile (the INCREMENTAL, parallel-safe step).
#   BUILD/JS/%_dats_out0.js : DATS/%.dats
# fail-loud-on-empty guard + OUR-source parse-error guard (mirrors
# build-go.sh transpile_one / build-m0b.sh).
########################################################################
$(JSDIR)/%_dats_out0.js: $(DATSDIR)/%.dats | dirs
	@echo ">> transpile $*.dats"
	@$(NODE) $(JSEMIT) $< > $@ 2> $@.err; \
	if [ "$$(wc -l < $@)" -lt $(MINLINES) ]; then \
	  echo "!! transpile FAILED for $< (see $@.err)" >&2; \
	  tail -30 $@.err >&2; rm -f $@; exit 1; \
	fi; \
	case "$*" in \
	  go1emit*|xats2go_*) \
	    if grep -qE "F3PERR0-ERROR.*$*\.dats|PREAD00-ERROR.*$*\.dats" $@.err; then \
	      echo "!! parse/typecheck ERROR in $*.dats (see $@.err):" >&2; \
	      grep -E "ERROR.*$*\.dats" $@.err | head -8 >&2; rm -f $@; exit 1; \
	    fi ;; \
	esac

########################################################################
# STEP B — per-file NAMESPACE fragment:  sed jsxtnm -> jsx<NNN>tnm with the
# STABLE index from $(GO_DATS) position.  This isolates the namespacing from
# concat, so the index never depends on build order.
########################################################################
$(JSDIR)/%_dats_ns.js: $(JSDIR)/%_dats_out0.js
	@idx=$$(i=100; for f in $(GO_DATS); do \
	          if [ "$$f" = "$*.dats" ]; then echo $$i; break; fi; i=$$((i+1)); \
	        done); \
	sed -e "s/jsxtnm/jsx$${idx}tnm/g" $< > $@

########################################################################
# STEP C — lib2xats2go.js : concat the namespaced fragments in $(GO_DATS)
# order.  Only re-runs when an _ns.js changed (i.e. when its _out0 changed,
# i.e. when its .dats changed).
########################################################################
$(LIB2GO): $(NSJS)
	@echo ">> concat lib2xats2go.js ($(words $(GO_DATS)) files)"
	@cat $(NSJS) > $@
	@echo "   -> $@ ($$(wc -l < $@) lines)"

########################################################################
# STEP D — the Go emitter driver transpile (separate from the lib).
########################################################################
$(DRV_GO): $(DRIVER) | dirs
	@echo ">> transpile go driver"
	@$(NODE) $(JSEMIT) $< > $@ 2> $(BUILD)/transpile_godrv.err; \
	if [ "$$(wc -l < $@)" -lt 5 ]; then \
	  echo "!! go driver transpile too small" >&2; \
	  tail -40 $(BUILD)/transpile_godrv.err >&2; rm -f $@; exit 1; \
	fi

########################################################################
# FIXED LIBS — reuse-or-symlink the prebuilt frontend libs.  Rebuild ONLY if
# the cached copy is missing/stale vs the prebuilt source.  NEVER rebuilt on a
# normal emitter edit (the emitter `.dats` are not prerequisites here).
########################################################################
# lib2xats2cc.js: BUILD from the LOCAL extended D3->intrep0 stage (with I0Etry0
# + try/raise lowering).  This REPLACES the old "reuse frontend/BUILD" recipe:
# the prebuilt frontend lib2xats2cc.js is INCOMPLETE (no I0Etry0, no try/raise
# lowering) so a $raise/try program never reaches the emitter.  Mirrors the
# build-m0b.sh build_backend_lib: transpile each .dats via jsemit00, sed the
# per-file namespace jsxtnm -> jsx<NNN>tnm (3-digit, from 100), then concat.
# Real cached target: rebuilds only when a local-stage source changes.
$(LIB2CC_C): $(XATS2CC_SRCALL) | dirs
	@echo ">> build lib2xats2cc.js from LOCAL extended stage ($(words $(XATS2CC_DATS)) files; +I0Etry0/try-raise)"
	@: > $@; idx=100; \
	for f in $(XATS2CC_DATS); do \
	  t="$(BUILD)/xcc__$${f%.dats}_dats_out0.js"; \
	  $(NODE) $(JSEMIT) "$(XATS2CC_LOCAL)/$$f" > "$$t" 2>"$$t.err"; \
	  if [ "$$(wc -l < "$$t")" -lt $(MINLINES) ]; then \
	    echo "!! xats2cc(local) transpile FAILED for $$f (see $$t.err)" >&2; tail -30 "$$t.err" >&2; rm -f $@; exit 1; \
	  fi; \
	  sed -e "s/jsxtnm/jsx$${idx}tnm/g" "$$t" >> $@; idx=$$((idx+1)); \
	done; \
	echo "   -> $@ ($$(wc -l < $@) lines, built from local stage)"

# lib2xats2js.js: reuse the prebuilt frontend/BUILD JS-oracle lib.  If the
# prebuilt is absent the recipe falls back to building it once from the
# xats2js source set (the build-m0b.sh recipe) — but here it exists.
$(LIB2JS_C): | dirs
	@echo ">> cache lib2xats2js.js (JS oracle)"
	@if [ -f "$(LIB2JS)" ]; then \
	  ln -sf $(LIB2JS) $@ 2>/dev/null || cp $(LIB2JS) $@; \
	else \
	  echo "!! $(LIB2JS) absent — building lib2xats2js.js from xats2js source once" >&2; \
	  : > $@; idx=100; \
	  for f in $(XATS2JS_DATS); do \
	    t="$(BUILD)/xjs__$${f%.dats}_dats_out0.js"; \
	    $(NODE) $(JSEMIT) "$(SRCGEN2)/xats2js/srcgen2/DATS/$$f" > "$$t" 2>"$$t.err"; \
	    if [ "$$(wc -l < "$$t")" -lt $(MINLINES) ]; then \
	      echo "!! xats2js transpile FAILED for $$f (see $$t.err)" >&2; tail -30 "$$t.err" >&2; rm -f $@; exit 1; \
	    fi; \
	    sed -e "s/jsxtnm/jsx$${idx}tnm/g" "$$t" >> $@; idx=$$((idx+1)); \
	  done; \
	  echo "   -> $@ (built once from source)"; \
	fi

########################################################################
# CACHED NAMESPACE-SED'd FIXED LIBS — built ONCE.  The namespace-sed
# (s/jsx(...)tnm/jsN\1tnm/g) is a PURE function of its FIXED input, so caching
# its output is byte-identical to running it inline on every relink.  These are
# the ~200 MB worth of sed work that the old per-relink / per-test recipes
# repeated; now they run exactly once (≈10s one-time) and every consumer just
# `cat`s the cached result.  Prereq is the FIXED source ONLY (never an emitter
# .dats), so an emitter edit NEVER rebuilds these.
########################################################################
# js1 · lib2xatsopt.js  (171 MB → cached once).  Source: the prebuilt
# lib2xatsopt.js (NEVER rebuilt; not a target here, only read).
$(OPT_JS1): $(LIB2OPT) | dirs
	@echo ">> cache js1·lib2xatsopt.js (one-time ~171MB sed)"
	@sed -E 's/jsx(...)tnm/js1\1tnm/g' $(LIB2OPT) > $@
	@echo "   -> $@"

# js2 · lib2xats2cc.js  (16 MB → cached once).  Source: the NEW LOCAL cc (with
# I0Etry0) — used by the GO bundle.
$(CC_JS2): $(LIB2CC_C) | dirs
	@echo ">> cache js2·lib2xats2cc.js (NEW local, one-time sed)"
	@sed -E 's/jsx(...)tnm/js2\1tnm/g' $(LIB2CC_C) > $@
	@echo "   -> $@"

# js2 · OLD lib2xats2cc.js — used by the JS-ORACLE bundle (stamp-matched to the
# OLD JS driver + lib2xats2js).  Source: the prebuilt frontend lib (NOT the
# local one).  See the CC_JS2_OLD note above for why the JS oracle must use the
# OLD cc.
$(CC_JS2_OLD): $(LIB2CC_OLD) | dirs
	@echo ">> cache js2·lib2xats2cc.OLD.js (frontend prebuilt, for JS oracle)"
	@sed -E 's/jsx(...)tnm/js2\1tnm/g' $(LIB2CC_OLD) > $@
	@echo "   -> $@"

########################################################################
# CACHED i0varfst(+tokenfpr) SHIMS — generated ONCE.  Verified that the shim
# resolves ONLY names from FIXED libs and that the namespace-sed never rewrites
# those names (none contain a `jsx<NNN>tnm` token), so the stamped names are
# identical in the raw fixed lib, the cached js1/js2/js3 lib, and the final
# bundle.  Therefore the shim is a pure function of FIXED inputs and is cached.
#
# The shim's grep targets split across TWO fixed libs (verified against the
# golden shim):
#   i0varfst_mknil/mklst/addvar/addlst/listize/strmize, i0var_dvar$get  → cc
#   d2var_get_stmp, stamp_get_uint                                      → opt
#   tokenfpr (JS-oracle only)                                          → lib2xats2js
# gen-i0varfst-shim.sh scans ONE file, so we build a tiny SHIMNAMES extract that
# contains exactly the lines mentioning the opt-resident helper names (grepped
# ONCE from the 171 MB opt — fixed), then concat it with cc.js2 (+ the JS lib for
# the JS shim) as the scan input.  None of this depends on the CHANGING
# lib2xats2go, so an emitter edit never regenerates a shim.
########################################################################
# The two helper names that live in opt (not cc): extracted once into a tiny file.
SHIMNAMES := $(BUILD)/i0varfst-shim.optnames.js
$(SHIMNAMES): $(OPT_JS1) | dirs
	@echo ">> extract opt-resident shim helper names (one-time grep over opt.js1)"
	@grep -oE 'd2var_get_stmp_[0-9]+|stamp_get_uint_[0-9]+' $(OPT_JS1) \
	  | sort -u > $@

# GO shim: scan cc.js2 + the opt-name extract (the Go bundle has no tokenfpr, so
# the generator's tokenfpr block is gated OFF — byte-identical to the golden).
$(GO_SHIM): $(CC_JS2) $(SHIMNAMES) $(JSSHIM) | dirs
	@echo ">> cache i0varfst shim (GO; scans cc.js2 + opt-names)"
	@cat $(CC_JS2) $(SHIMNAMES) > $@.scan.tmp
	@bash $(JSSHIM) $@.scan.tmp $@ >/dev/null \
	  || { echo "!! GO shim gen failed" >&2; rm -f $@.scan.tmp; exit 1; }
	@rm -f $@.scan.tmp

# JS shim: same scan plus the JS-oracle lib so the tokenfpr no-op block is
# emitted (the JS reference references tokenfpr).  Scans the OLD cc ($(CC_JS2_OLD))
# because the JS-oracle bundle uses the OLD cc (stamp-matched).
$(JS_SHIM): $(CC_JS2_OLD) $(SHIMNAMES) $(LIB2JS_C) $(JSSHIM) | dirs
	@echo ">> cache i0varfst shim (JS oracle; scans cc.OLD.js2 + opt-names + lib2xats2js)"
	@cat $(CC_JS2_OLD) $(SHIMNAMES) $(LIB2JS_C) > $@.scan.tmp
	@bash $(JSSHIM) $@.scan.tmp $@ >/dev/null \
	  || { echo "!! JS shim gen failed" >&2; rm -f $@.scan.tmp; exit 1; }
	@rm -f $@.scan.tmp

########################################################################
# THE EMITTER BUNDLE — runtime + js1·opt + js2·cc + js3·go + driver, with the
# i0varfst+tokenfpr shim prepended.  Re-links only when the lib/driver/cc
# changed.  (lib2xatsopt.js itself is a content prereq but it never changes.)
########################################################################
# SINGLE-PASS relink.  The final bundle is assembled in ONE write from CACHED
# pieces — only lib2xats2go.js (14 MB) is re-sed'd per edit; the 171 MB opt and
# 16 MB cc are plain `cat`s of the once-built OPT_JS1/CC_JS2, and the shim is the
# once-built GO_SHIM.  No intermediate 200 MB GOBUNDLE double-write.
# Byte-order is IDENTICAL to the old recipe:
#   shim ++ RUNTIME ++ js1·opt ++ js2·cc ++ js3·go ++ driver.
$(GOPATCHED): $(GO_SHIM) $(OPT_JS1) $(CC_JS2) $(LIB2GO) $(DRV_GO) | dirs
	@echo ">> link go-emitter bundle (single-pass: shim + runtime + js1·opt + js2·cc + js3·go + driver)"
	@cat $(GO_SHIM) $(RUNTIME) $(OPT_JS1) $(CC_JS2) \
	     <(sed -E 's/jsx(...)tnm/js3\1tnm/g' $(LIB2GO)) \
	     $(DRV_GO) > $@
	@echo "   -> $@"

# JS-ORACLE reference bundle — runtime + js1·opt + js2·cc + js3·JS + JS driver,
# JS shim prepended.  Test-INDEPENDENT (the source is passed as argv to the
# bundle), so it is linked ONCE here and reused by every `_oracle` run instead of
# being rebuilt per test.  Same cached pieces as the Go bundle except js3 (the JS
# oracle lib) and the driver; only lib2xats2js.js is re-sed'd, and that too only
# when the (FIXED) oracle lib changes.  Byte-order:
#   js-shim ++ RUNTIME ++ js1·opt ++ js2·cc(OLD) ++ js3·JS ++ JS-driver.
# Uses $(CC_JS2_OLD) (the OLD frontend cc) so its stamps match the OLD JS driver
# + lib2xats2js — see the CC_JS2_OLD note.  The GO bundle ($(GOPATCHED)) uses the
# NEW local cc; the two bundles are independent.
$(JSPATCHED): $(JS_SHIM) $(OPT_JS1) $(CC_JS2_OLD) $(LIB2JS_C) $(JDRV) | dirs
	@echo ">> link JS-oracle reference bundle (single-pass; cached, test-independent; OLD cc)"
	@cat $(JS_SHIM) $(RUNTIME) $(OPT_JS1) $(CC_JS2_OLD) \
	     <(sed -E 's/jsx(...)tnm/js3\1tnm/g' $(LIB2JS_C)) \
	     $(JDRV) > $@
	@echo "   -> $@"

bundle: $(GOPATCHED)
	@echo ">> emitter bundle up to date: $(GOPATCHED)"

check-go:
	@command -v go >/dev/null 2>&1 || { echo "!! 'go' not on PATH" >&2; exit 1; }

########################################################################
# SELF-HOSTING SMOKE — structural guard for backend-source probes.
# Runs the Go emitter on one backend source and rejects vacuous generated Go
# that only contains skip-comments + func main.  This is intentionally separate
# from the conformance suite because stdout equality can be empty/empty here.
########################################################################
SELFHOST_SMOKE_SRC ?= $(DATSDIR)/go1emit_utils0.dats
SELFHOST_SMOKE_MIN_FUNCS ?= 1
SELFHOST_STRICT_EXPECT_FUNCS ?= i0s00go1 i0c00go1
SELFHOST_STRICT_INTERNAL_ROUTE_RE ?= xatsgo\.Xats_(d2cst|d2var|token_get_node|fprint_loctn_as_stamp)

selfhost-smoke: $(GOPATCHED)
	@set -uo pipefail; \
	SRC="$(SELFHOST_SMOKE_SRC)"; \
	[ -f "$$SRC" ] || SRC="$(DATSDIR)/$$SRC"; \
	[ -f "$$SRC" ] || { echo "!! selfhost-smoke source not found: $(SELFHOST_SMOKE_SRC)" >&2; exit 2; }; \
	SRC="$$(cd "$$(dirname "$$SRC")" && pwd)/$$(basename "$$SRC")"; \
	NAME="$$(basename "$$SRC" .dats)"; \
	WORK="$(BUILD)/selfhost-smoke"; \
	mkdir -p "$$WORK"; \
	RAWOUT="$$WORK/$$NAME.stdout.txt"; \
	STDERR="$$WORK/$$NAME.stderr.txt"; \
	EMIT="$$WORK/$$NAME.go"; \
	echo "======================================================================"; \
	echo ">> SELFHOST-SMOKE: $$SRC"; \
	echo "======================================================================"; \
	echo ">> run go-emitter -> $$EMIT"; \
	$(NODE) $(GOPATCHED) "$$SRC" > "$$RAWOUT" 2>"$$STDERR"; RC=$$?; \
	if [ "$$RC" -ne 0 ]; then echo "!! go-emitter exit $$RC" >&2; tail -40 "$$STDERR" >&2; exit "$$RC"; fi; \
	awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$$RAWOUT" > "$$EMIT"; \
	[ "$$(wc -c < "$$EMIT")" -ge 2 ] || { echo "!! selfhost-smoke: no emitted Go captured" >&2; cat "$$RAWOUT" >&2; exit 1; }; \
	funcs="$$(awk '/^func[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ && $$0 !~ /^func[ \t]+main[ \t]*\(/ { n++ } END { print n+0 }' "$$EMIT")"; \
	skips="$$(grep -c 'skipped non-val dcl' "$$EMIT" || true)"; \
	echo "   emitted Go: $$EMIT ($$(wc -l < "$$EMIT") lines, $$funcs package-level func(s) excluding main, $$skips skip-comment(s))"; \
	if [ "$$funcs" -lt "$(SELFHOST_SMOKE_MIN_FUNCS)" ]; then \
	  echo "!! selfhost-smoke: vacuous backend-source emission" >&2; \
	  echo "!! expected at least $(SELFHOST_SMOKE_MIN_FUNCS) package-level func declaration(s) other than main in $$EMIT" >&2; \
	  echo "!! found $$funcs; this source can otherwise pass by empty stdout while real declarations are skipped" >&2; \
	  echo "!! inspect $$EMIT and $$STDERR" >&2; \
	  exit 1; \
	fi; \
	echo ">> SELFHOST-SMOKE PASS"

selfhost-strict: selfhost-smoke
	@set -uo pipefail; \
	SRC="$(SELFHOST_SMOKE_SRC)"; \
	[ -f "$$SRC" ] || SRC="$(DATSDIR)/$$SRC"; \
	[ -f "$$SRC" ] || { echo "!! selfhost-strict source not found: $(SELFHOST_SMOKE_SRC)" >&2; exit 2; }; \
	NAME="$$(basename "$$SRC" .dats)"; \
	WORK="$(BUILD)/selfhost-smoke"; \
	EMIT="$$WORK/$$NAME.go"; \
	[ -f "$$EMIT" ] || { echo "!! selfhost-strict emitted Go not found: $$EMIT" >&2; exit 2; }; \
	echo "======================================================================"; \
	echo ">> SELFHOST-STRICT: $$EMIT"; \
	echo "======================================================================"; \
	bad=0; \
	if grep -n -E '/\*[[:space:]]*UNHANDLED:|^[[:space:]]*//[[:space:]]*UNHANDLED:' "$$EMIT" > "$$WORK/$$NAME.strict-unhandled.txt"; then \
	  echo "!! selfhost-strict: generated Go contains UNHANDLED markers" >&2; \
	  sed -n '1,20p' "$$WORK/$$NAME.strict-unhandled.txt" >&2; \
	  bad=1; \
	fi; \
	if grep -n -E '$(SELFHOST_STRICT_INTERNAL_ROUTE_RE)' "$$EMIT" > "$$WORK/$$NAME.strict-internal-routing.txt"; then \
	  echo "!! selfhost-strict: generated Go routes compiler-internal names through xatsgo" >&2; \
	  sed -n '1,20p' "$$WORK/$$NAME.strict-internal-routing.txt" >&2; \
	  bad=1; \
	fi; \
	for f in $(SELFHOST_STRICT_EXPECT_FUNCS); do \
	  if ! grep -n -E "^func[[:space:]]+$${f}_[A-Za-z0-9_]*[[:space:]]*\\(" "$$EMIT" > "$$WORK/$$NAME.strict-func-$$f.txt"; then \
	    echo "!! selfhost-strict: expected package-level function $$f is missing" >&2; \
	    bad=1; \
	  fi; \
	done; \
	if [ "$$bad" -ne 0 ]; then \
	  echo "!! inspect $$EMIT" >&2; \
	  exit 1; \
	fi; \
	echo ">> SELFHOST-STRICT PASS"

smoke-selfhost: selfhost-smoke

########################################################################
# ONE TEST through the differential-vs-JS oracle.
#   make TEST=<path> test          (path abs or rel to TEST dir)
#   make run/<name>                (name without .dats)
# Depends on the emitter bundle + the cached JS-oracle lib + the JS driver.
# The recipe mirrors build-go.sh steps [3]..[7] exactly.
########################################################################
TEST ?=
test: $(GOPATCHED) $(JSPATCHED) check-go
	@if [ -z "$(TEST)" ]; then echo "usage: make TEST=<path> test" >&2; exit 2; fi; \
	$(MAKE) --no-print-directory _oracle SRC="$(TEST)"

# run/<name> — resolve <name>.dats under the TEST dir.
run/%: $(GOPATCHED) $(JSPATCHED) check-go
	@$(MAKE) --no-print-directory _oracle SRC="$(TESTDIR)/$*.dats"

# JS-oracle driver transpile (cached; only when missing or driver newer).
$(JDRV): $(SRCGEN2)/xats2js/srcgen2/UTIL/xats2js_jsemit01.dats | dirs
	@echo ">> transpile js-oracle driver"
	@$(NODE) $(JSEMIT) $< > $@ 2> $(BUILD)/transpile_jsdrv.err; \
	if [ "$$(wc -l < $@)" -lt 5 ]; then \
	  echo "!! js driver transpile too small" >&2; \
	  tail -40 $(BUILD)/transpile_jsdrv.err >&2; rm -f $@; exit 1; \
	fi

########################################################################
# _oracle — the differential engine.  Internal (invoke via `test` / `run/%`).
# SRC must be set.  Reuses the prebuilt emitter bundle (already linked); links
# only the test-specific JS-reference bundle.  Asserts Go stdout == JS stdout
# byte-equal (xxd diff on mismatch); refreshes the golden.
########################################################################
.PHONY: _oracle
_oracle:
	@set -uo pipefail; \
	SRC="$(SRC)"; \
	[ -f "$$SRC" ] || SRC="$(TESTDIR)/$$SRC"; \
	[ -f "$$SRC" ] || { echo "!! source not found: $(SRC)" >&2; exit 2; }; \
	SRC="$$(cd "$$(dirname "$$SRC")" && pwd)/$$(basename "$$SRC")"; \
	NAME="$$(basename "$$SRC" .dats)"; \
	WORK="$(BUILD)/$$NAME"; GOOUT="$$WORK/GO"; GOMOD="$$WORK/GOMOD"; \
	mkdir -p "$$WORK" "$$GOOUT" "$$GOMOD"; \
	echo "======================================================================"; \
	echo ">> ORACLE: $$NAME"; \
	echo "======================================================================"; \
	echo ">> [1/5] run go-emitter on $$NAME -> emit Go"; \
	RAWOUT="$$WORK/go-stdout.txt"; \
	$(NODE) $(GOPATCHED) "$$SRC" > "$$RAWOUT" 2>"$$WORK/go-stderr.txt"; RC=$$?; \
	if [ "$$RC" -ne 0 ]; then echo "!! go-emitter exit $$RC" >&2; tail -40 "$$WORK/go-stderr.txt" >&2; exit "$$RC"; fi; \
	EMIT="$$GOOUT/$$NAME.go"; \
	awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$$RAWOUT" > "$$EMIT"; \
	[ "$$(wc -c < "$$EMIT")" -ge 2 ] || { echo "!! no emitted Go captured" >&2; cat "$$RAWOUT" >&2; exit 1; }; \
	echo "   -> $$EMIT ($$(wc -l < "$$EMIT") lines)"; \
	echo ">> [2/5] assemble Go module + gofmt/vet/build/run"; \
	printf 'module xats2go_%s\n\ngo 1.26\n\nrequire xatsgo v0.0.0\nreplace xatsgo => %s\n' "$$NAME" "$(RUNTIMEGO)" > "$$GOMOD/go.mod"; \
	cp "$$EMIT" "$$GOMOD/$$NAME.go"; \
	( cd "$$GOMOD" && go mod tidy >/dev/null 2>&1 || true ); \
	gofmt -w "$$GOMOD/$$NAME.go" 2>/dev/null || true; \
	if [ -z "$$(gofmt -l "$$GOMOD/$$NAME.go")" ]; then echo "   gofmt: clean"; \
	  else echo "!! gofmt would reformat $$NAME.go:" >&2; gofmt -d "$$GOMOD/$$NAME.go" >&2; echo "   (cosmetic; continuing)"; fi; \
	( cd "$$GOMOD" && go vet ./... ) && echo "   go vet: OK" || { echo "!! go vet FAILED" >&2; exit 1; }; \
	( cd "$$GOMOD" && go build -o "$$WORK/$$NAME.bin" . ) && echo "   go build: OK" || { echo "!! go build FAILED" >&2; exit 1; }; \
	GO_STDOUT="$$WORK/$$NAME.go.stdout"; \
	"$$WORK/$$NAME.bin" > "$$GO_STDOUT" 2>"$$WORK/$$NAME.go.stderr"; GRC=$$?; \
	[ "$$GRC" -eq 0 ] || { echo "!! program exit $$GRC" >&2; cat "$$WORK/$$NAME.go.stderr" >&2; exit 1; }; \
	echo ">> [3/5] build JS-backend reference (cached bundle, test-independent)"; \
	JS_STDOUT="$$WORK/$$NAME.js.stdout"; : > "$$JS_STDOUT"; \
	$(NODE) $(JSPATCHED) "$$SRC" > "$$WORK/$$NAME.emit.js" 2>"$$WORK/jsemit.err"; \
	awk -v n="$$NAME" 'f||$$0 ~ ("^// LCSRCsome1.*"n){f=1; print}' "$$WORK/$$NAME.emit.js" > "$$WORK/$$NAME.user.js"; \
	RUNJS="$$WORK/$$NAME.run.js"; \
	cat "$(NS2R)/srcgen2_prelude.js" "$(NS2R)/srcgen2_prelude_node.js" \
	    "$(NS2R)/srcgen2_precats.js" "$(NS2R)/srcgen2_xatslib.js" \
	    "$(S2R)/xats2js_js1emit.js" "$$WORK/$$NAME.user.js" > "$$RUNJS"; \
	node "$$RUNJS" > "$$JS_STDOUT" 2>"$$WORK/$$NAME.js.stderr"; \
	echo ">> [4/5] ORACLE: assert Go stdout == JS stdout (byte-equal)"; \
	EXPECT_DIR="$(TESTDIR)/OUTS"; mkdir -p "$$EXPECT_DIR"; EXPECT="$$EXPECT_DIR/$$NAME.expected"; \
	ok=0; \
	if cmp -s "$$GO_STDOUT" "$$JS_STDOUT"; then \
	  echo "   BYTE-EQUAL to JS backend."; cp "$$GO_STDOUT" "$$EXPECT"; ok=1; \
	elif [ -s "$$JS_STDOUT" ]; then \
	  echo "!! DIFFERENTIAL-vs-JS MISMATCH:" >&2; \
	  echo "--- go ---" >&2; xxd "$$GO_STDOUT" >&2; \
	  echo "--- js ---" >&2; xxd "$$JS_STDOUT" >&2; \
	  diff <(xxd "$$GO_STDOUT") <(xxd "$$JS_STDOUT") >&2 || true; exit 1; \
	fi; \
	if [ "$$ok" -eq 0 ]; then \
	  if [ -s "$$EXPECT" ] && cmp -s "$$GO_STDOUT" "$$EXPECT"; then \
	    echo "   GOLDEN match (JS oracle deferred)."; ok=1; \
	  else echo "!! no oracle matched" >&2; xxd "$$GO_STDOUT" >&2; exit 1; fi; \
	fi; \
	echo ">> [5/5] PASS: $$NAME  ($$(tr -d '\n' < "$$GO_STDOUT" | head -c 60))"

########################################################################
# SUITE — run the oracle over the conformance list (reuse run-suite.sh's
# DEFAULT_SUITE), summarize pass/fail.  Bundle/libs are built ONCE up front.
########################################################################
SUITE_NAMES := \
  test01_xats2go \
  test02_arith_xats2go \
  test03_compare_xats2go \
  test04_logic_xats2go \
  test05_float_xats2go \
  test06_char_xats2go \
  test07_fun1_xats2go \
  test08_fun_multi_xats2go \
  test09_fun_call_fun_xats2go \
  test10_fun_args_xats2go \
  test11_fun_rec_xats2go \
  test12_if_ret_xats2go \
  test13_if_val_xats2go \
  test14_fact_xats2go \
  test15_case_lit_xats2go \
  test16_case_guard_xats2go \
  test17_let_xats2go \
  test18_tail_loop_xats2go \
  test19_tail_acc_xats2go \
  test20_lam_apply_xats2go \
  test21_closure_cap_xats2go \
  test22_fix_local_xats2go \
  test23_lam_store_xats2go \
  test30_nested_cap_xats2go \
  test31_shadow_xats2go \
  test32_multi_clos_xats2go \
  test33_fix_multi_xats2go \
  test34_cap_timing_xats2go \
  test35_const_xats2go \
  test36_cap_float_xats2go \
  test37_nest3_xats2go \
  test38_tytab_xats2go \
  test39_tytab_float_xats2go \
  test40_tytab_bool_xats2go \
  test41_let_case_xats2go \
  test42_tup_flat_xats2go \
  test43_tup_boxed_xats2go \
  test44_rec_flat_xats2go \
  test45_rec_boxed_xats2go \
  test46_nested_xats2go \
  test47_tup_fun_xats2go \
  test48_tup_float_xats2go \
  test49_tup_mixed_xats2go \
  test50_var_flat_xats2go \
  test51_var_boxed_alias_xats2go \
  test52_var_rec_xats2go \
  test53_var_seq_xats2go \
  test60_option_xats2go \
  test61_list_sum_xats2go \
  test62_tree_xats2go \
  test63_con_guard_xats2go \
  test64_guard_order_xats2go \
  test73_strescape_xats2go \
  test74_localfun_xats2go \
  test75_annot_xats2go \
  test70_jsbk01_xats2go \
  test71_jsbk02_xats2go \
  test72_jsbk03_xats2go \
  test76_listlen_xats2go \
  test78_toplevelval_xats2go \
  test79_listops_xats2go \
  test80_try_catch_xats2go \
  test81_try_normal_xats2go \
  test82_try_typed_xats2go \
  test83_reraise_xats2go \
  test84_poly_avl_xats2go \
  test85_list_vt_mut_xats2go \
  test86_autoflush_tpl_xats2go \
  test87_xats2js03_full_xats2go \
  test90_top_xats2go

# Self-hosting forcing-function rungs (copies of the JS backend's own test
# programs).  test73/test74 are the FOCUSED green proofs of two earlier
# self-hosting gaps (GAP-2 string escaping, GAP-1 local closures).  Chunk A
# made test75 (`(e : T)` type annotations/casts survive trxd3i0 + tryd3i0 and
# erase to the inner runtime value), test70 (`&sint` by-REFERENCE params -> Go
# pointers; GAP A1), test71 (tuple/record-PATTERN function params `loop@(x,r)`
# -> tuple-projection value nodes I1Vp0rj/I1Vp1rj; GAP A2), and test72
# (prelude list fold runtime, polymorphic datacon-pattern unwrap,
# uninitialized aggregate vars + tuple lvalues) green -- all three JS-backend
# copies are now in the suite above.  test84 adds a focused polymorphic
# user-template body instantiation from the xats2js AVL test; test85 adds
# linear list_vt datacon-field mutation from the xats2js list_vt test; test86
# adds xats2js-style program-exit flushing for pending top-level `prints`;
# test87 promotes the broader xats2js test03 fact/fibo/by-ref program.
# See BUILD-NOTES "Self-hosting gap-fix" for the precise remaining-blocker list.

# SEQUENTIAL suite — unchanged behavior.  Bundles are built ONCE up front (the
# GOPATCHED + JSPATCHED prereqs), then each test reuses them.
suite: $(GOPATCHED) $(JSPATCHED) check-go
	@echo "======================================================================"; \
	echo ">> xats2go conformance suite: $(words $(SUITE_NAMES)) test(s)"; \
	echo "======================================================================"; \
	pass=0; fail=0; failed=""; \
	for n in $(SUITE_NAMES); do \
	  printf '>> %-32s ... ' "$$n"; \
	  log="$(BUILD)/$$n.suite.log"; \
	  if $(MAKE) --no-print-directory _oracle SRC="$(TESTDIR)/$$n.dats" > "$$log" 2>&1; then \
	    echo "PASS"; pass=$$((pass+1)); \
	  else \
	    echo "FAIL  (see $$log)"; fail=$$((fail+1)); failed="$$failed $$n"; \
	    tail -8 "$$log" | sed 's/^/      | /'; \
	  fi; \
	done; \
	echo "======================================================================"; \
	echo ">> SUMMARY: $$pass passed, $$fail failed (of $(words $(SUITE_NAMES)))"; \
	if [ "$$fail" -ne 0 ]; then echo ">> FAILED:$$failed"; echo "======================================================================"; exit 1; fi; \
	echo ">> ALL GREEN"; \
	echo "======================================================================"

########################################################################
# PARALLEL suite — `make -j[N] psuite`.  Once the (shared) GOPATCHED+JSPATCHED
# bundles are built, each test's _oracle work is INDEPENDENT (its own
# BUILD/<name>/ scratch + its own go module), so they run concurrently.  Each
# per-test target writes a PASS/FAIL stamp + a log; the `psuite` aggregator
# prints a clean summary and exits nonzero on any failure.  The sequential
# `make suite` above is untouched.
########################################################################
SUITE_STAMPS := $(patsubst %,$(BUILD)/%.suite.stamp,$(SUITE_NAMES))
.PHONY: psuite FORCE
FORCE:

# Per-test concurrent runner.  Depends on both bundles (built once, shared) so a
# cold `make -j psuite` links them BEFORE fanning out, plus FORCE so each run
# actually re-executes the test (a stamp is a result, not a cache).  Writes
# PASS/FAIL to the stamp; never fails the build itself (the aggregator decides),
# so one red test doesn't abort the others under -j.
$(BUILD)/%.suite.stamp: $(GOPATCHED) $(JSPATCHED) check-go FORCE
	@n="$*"; log="$(BUILD)/$$n.suite.log"; \
	if $(MAKE) --no-print-directory _oracle SRC="$(TESTDIR)/$$n.dats" > "$$log" 2>&1; then \
	  echo PASS > $@; printf '>> %-32s ... PASS\n' "$$n"; \
	else \
	  echo FAIL > $@; printf '>> %-32s ... FAIL  (see %s)\n' "$$n" "$$log"; \
	  tail -8 "$$log" | sed 's/^/      | /'; \
	fi

# Aggregator.  Run as `make -jN psuite` for concurrency (N = parallelism).
psuite: $(SUITE_STAMPS)
	@pass=0; fail=0; failed=""; \
	for n in $(SUITE_NAMES); do \
	  s="$$(cat $(BUILD)/$$n.suite.stamp 2>/dev/null)"; \
	  if [ "$$s" = PASS ]; then pass=$$((pass+1)); else fail=$$((fail+1)); failed="$$failed $$n"; fi; \
	done; \
	echo "======================================================================"; \
	echo ">> SUMMARY: $$pass passed, $$fail failed (of $(words $(SUITE_NAMES)))"; \
	if [ "$$fail" -ne 0 ]; then echo ">> FAILED:$$failed"; echo "======================================================================"; exit 1; fi; \
	echo ">> ALL GREEN"; \
	echo "======================================================================"

########################################################################
# CLEAN — emitter artifacts only (keep the cached fixed libs).
# CLEANALL — also remove the cached fixed libs.  NEVER lib2xatsopt.js.
########################################################################
clean:
	@echo ">> clean: emitter artifacts (keeping cached fixed libs)"
	@rm -f $(OUT0) $(addsuffix .err,$(OUT0)) $(NSJS) \
	       $(LIB2GO) $(DRV_GO) \
	       $(GOPATCHED) $(JSPATCHED) \
	       $(BUILD)/xats2go-bundle.js $(BUILD)/xats2go-bundle.shim.js \
	       $(BUILD)/xats2js-ref.js $(BUILD)/xats2js-ref.shim.js \
	       $(BUILD)/xats2go-m*.js $(BUILD)/xats2go-m*.shim.js \
	       $(SUITE_STAMPS) $(BUILD)/*.suite.log
	@# remove ALL per-test/scratch work dirs (every BUILD subdir EXCEPT JS/) so
	@# arbitrarily-named dev scratch (e.g. tcase, tguard, tif_inval) cannot
	@# accumulate — the old `test*_xats2go` glob missed those and let ~6 GB pile up.
	@find $(BUILD) -mindepth 1 -maxdepth 1 -type d ! -name JS ! -name .v8cache -exec rm -rf {} + 2>/dev/null || true

# CLEANALL — also remove the CACHED FIXED artifacts (the namespace-sed'd opt/cc
# and the i0varfst shims).  These are pure functions of the prebuilt fixed libs
# and rebuild in ~10s; removing them forces a one-time re-cache.  NEVER touches
# lib2xatsopt.js (the 171 MB prebuilt source).
cleanall: clean
	@echo ">> cleanall: also removing cached fixed libs + namespaced caches + shims (NOT lib2xatsopt.js)"
	@rm -f $(LIB2CC_C) $(LIB2JS_C) $(JDRV) \
	       $(OPT_JS1) $(CC_JS2) $(CC_JS2_OLD) $(GO_SHIM) $(JS_SHIM) $(SHIMNAMES) \
	       $(BUILD)/xcc__*_dats_out0.js $(BUILD)/xcc__*_dats_out0.js.err \
	       $(BUILD)/transpile_godrv.err $(BUILD)/transpile_jsdrv.err
