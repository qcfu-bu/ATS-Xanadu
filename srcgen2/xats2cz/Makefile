########################################################################
# xats2cz — Chez Scheme backend for ATS3 (3rd attempt).  Build harness.
#
# Emits Chez Scheme DIRECTLY from the expression-shaped intrep0 (no
# intrep1/ANF), consuming the COMPLETE xats2js backend's intrep0+trxd3i0
# (lib2xats2js.js) — NOT the incomplete xats2cc.  The emitter is ATS3 source
# transpiled to JS by the prebuilt seed and run on Node; it emits Scheme that
# runs on Chez.  Template instances are inlined as nested closures (no
# hoist/lift/seed); see docs/.
#
#   make / make -j8     build the emitter bundle
#   make dump/NAME      run emitter on TEST/NAME.dats; show emitted Scheme
#   make run/NAME       emit Scheme for TEST/NAME.dats and run on Chez
#   make clean / cleanall
########################################################################
SHELL := /bin/bash

########################################################################
# Toolchain
########################################################################
XATSHOME  ?= /Users/qcfu/Projects/ATS-Xanadu
export XATSHOME                       # the seed resolves /prelude/* against it
SRCGEN1   := $(XATSHOME)/srcgen1
SRCGEN2   := $(XATSHOME)/srcgen2
XATS2CZ   := $(SRCGEN2)/xats2cz

JSEMIT  := $(XATSHOME)/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js
LIB2OPT := $(SRCGEN2)/lib/lib2xatsopt.js                          # frontend (js1)
LIB2JS  := $(SRCGEN2)/xats2js/srcgen1/lib/lib2xats2js.js          # intrep0+trxd3i0 (js2)

NODE  := node --stack-size=8801
# Compiling the full COMPILER source (the self-host fragments, in parallel) needs two
# things the single-file path doesn't: (1) deep recursion — the JS-compiled emitter has
# no loops, and V8's --stack-size MUST stay under the OS thread stack or it faults past
# the guard page (SIGSEGV) instead of throwing; so raise the OS stack, then give V8 a big
# stack inside it.  (2) NO shared V8 compile cache — parallel procs racing one cache file
# corrupt it and SIGSEGV; disable it per-proc (the sequential bundle build keeps the cache).
NODE_DEEP := ulimit -s 65520 2>/dev/null; NODE_COMPILE_CACHE= node --stack-size=60000
CHEZ  ?= chez --script
# cache V8 bytecode so repeated runs of the ~200MB bundle parse fast (sequential
# use only — parallel procs racing the cache is unsafe).
export NODE_COMPILE_CACHE = $(BUILD)/.v8cache

BUILD   := $(XATS2CZ)/BUILD
JSDIR   := $(BUILD)/JS
DATSDIR := $(XATS2CZ)/DATS
UTILDIR := $(XATS2CZ)/UTIL
TESTDIR := $(XATS2CZ)/TEST
CZRT    := $(XATS2CZ)/runtime

MINLINES := 3

########################################################################
# Emitter source list — concat/namespace order; index = 100 + position
# (a 3-digit pure function of position; parallel-safe, reproducible).
########################################################################
CZ_DATS := \
  cz0emit.dats

DRIVER := $(UTILDIR)/xats2cz_czemit01.dats

########################################################################
# Runtime prefix to RUN the emitter bundle on Node (the JS runtime the
# JS-compiled emitter itself needs; NOT the Chez runtime for emitted code).
########################################################################
S2R := $(SRCGEN2)/xats2js/srcgenx/xshared/runtime
S1R := $(SRCGEN1)/xats2js/srcgenx/xshared/runtime
RUNTIME := \
  $(S2R)/xats2js_js1emit.js \
  $(S2R)/srcgen2_precats.js \
  $(S1R)/srcgen1_prelude.js \
  $(S1R)/srcgen1_prelude_node.js \
  $(S1R)/srcgen1_xatslib_node.js

########################################################################
# CHEZ runtime for emitted programs (M0: minimal & clean; grows per
# milestone — each primitive faithful to the JS contract, NOT inherited
# from the prior attempt's CATS/CHEZ).
########################################################################
CZRT_FILES := \
  $(CZRT)/xats2cz_runtime.scm

########################################################################
# Derived file lists
########################################################################
OUT0  := $(patsubst %.dats,$(JSDIR)/%_dats_out0.js,$(CZ_DATS))
NSJS  := $(patsubst %.dats,$(JSDIR)/%_dats_ns.js,$(CZ_DATS))

LIB2CZ   := $(BUILD)/lib2xats2cz.js
DRV_CZ   := $(BUILD)/xats2cz_czemit01_dats.js
OPT_JS1  := $(BUILD)/opt.js1.js
JS_JS2   := $(BUILD)/js.js2.js
CZBUNDLE := $(BUILD)/xats2cz-bundle.js

########################################################################
.PHONY: all bundle clean cleanall distclean help dirs
.DEFAULT_GOAL := bundle
.SECONDARY:
.PRECIOUS: $(OUT0) $(NSJS) $(SH_FRAGS)

all: bundle

help:
	@echo "xats2cz — Chez backend for ATS3.  Targets:"
	@echo "  SEED compiler (ATS3 -> Scheme, runs on Node):"
	@echo "    make bundle          build the emitter bundle (default)"
	@echo "    make dump/NAME       emit Scheme for TEST/NAME.dats"
	@echo "    make run/NAME        emit + run on Chez"
	@echo "    make cmp/NAME        differential test (Chez stdout == JS stdout)"
	@echo "    make suite           run cmp on all TEST/*.dats"
	@echo "  SELF-HOSTED compiler (the same emitter, running on Chez):"
	@echo "    make -j8 fragments   seed-compile all compiler source -> fragments"
	@echo "    make selfhost        assemble -> chez_selfhost.scm"
	@echo "    make native          precompile -> native chez_selfhost.so"
	@echo "    make selfrun/NAME    run the self-hosted compiler on TEST/NAME.dats"
	@echo "    make selfcompile     FIXPOINT: Chez compiler recompiles its own source"
	@echo "  clean | cleanall | distclean"

dirs:
	@mkdir -p $(JSDIR)

########################################################################
# STEP A — per-.dats transpile (seed), FAIL LOUD on empty or on F3PERR0
# (a dropped function is an upstream resolution failure — never ship it).
########################################################################
$(JSDIR)/%_dats_out0.js: $(DATSDIR)/%.dats | dirs
	@echo ">> transpile $*.dats"
	@$(NODE) $(JSEMIT) $< > $@ 2> $@.err; \
	if [ "$$(wc -l < $@)" -lt $(MINLINES) ]; then \
	  echo "!! transpile FAILED for $< (see $@.err)" >&2; tail -40 $@.err >&2; rm -f $@; exit 1; \
	fi; \
	if grep -qE "F3PERR0-ERROR.*$*\.dats|PREAD00-ERROR.*$*\.dats" $@.err; then \
	  echo "!! parse/typecheck ERROR in $*.dats (see $@.err):" >&2; \
	  grep -E "ERROR.*$*\.dats" $@.err | head -12 >&2; rm -f $@; exit 1; \
	fi

########################################################################
# STEP B — namespace-sed jsxtnm -> jsx<NNN>tnm (3-digit, idx = 100 + pos).
########################################################################
$(JSDIR)/%_dats_ns.js: $(JSDIR)/%_dats_out0.js
	@idx=$$(i=100; for f in $(CZ_DATS); do \
	          if [ "$$f" = "$*.dats" ]; then echo $$i; break; fi; i=$$((i+1)); \
	        done); \
	sed -e "s/jsxtnm/jsx$${idx}tnm/g" $< > $@

########################################################################
# STEP C — lib2xats2cz.js : concat namespaced fragments in CZ_DATS order.
########################################################################
$(LIB2CZ): $(NSJS)
	@echo ">> concat lib2xats2cz.js ($(words $(CZ_DATS)) files)"
	@cat $(NSJS) > $@
	@echo "   -> $@ ($$(wc -l < $@) lines)"

########################################################################
# STEP D — the driver transpile (FAIL LOUD).
########################################################################
$(DRV_CZ): $(DRIVER) | dirs
	@echo ">> transpile cz driver"
	@$(NODE) $(JSEMIT) $< > $@ 2> $(BUILD)/transpile_drv.err; \
	if [ "$$(wc -l < $@)" -lt 5 ]; then \
	  echo "!! driver transpile too small" >&2; tail -40 $(BUILD)/transpile_drv.err >&2; rm -f $@; exit 1; \
	fi

########################################################################
# CACHED namespace-sed'd FIXED libs (pure function of FIXED input).
########################################################################
$(OPT_JS1): $(LIB2OPT) | dirs
	@echo ">> cache js1.lib2xatsopt.js (one-time ~177MB sed)"
	@sed -E 's/jsx(...)tnm/js1\1tnm/g' $(LIB2OPT) > $@

$(JS_JS2): $(LIB2JS) | dirs
	@echo ">> cache js2.lib2xats2js.js (intrep0+trxd3i0)"
	@sed -E 's/jsx(...)tnm/js2\1tnm/g' $(LIB2JS) > $@

########################################################################
# THE EMITTER BUNDLE — runtime ++ js1.opt ++ js2.js ++ js3.cz ++ driver.
########################################################################
$(CZBUNDLE): $(OPT_JS1) $(JS_JS2) $(LIB2CZ) $(DRV_CZ) | dirs
	@echo ">> link xats2cz bundle (runtime + js1.opt + js2.js + js3.cz + driver)"
	@cat $(RUNTIME) $(OPT_JS1) $(JS_JS2) \
	     <(sed -E 's/jsx(...)tnm/js3\1tnm/g' $(LIB2CZ)) \
	     $(DRV_CZ) > $@
	@echo "   -> $@"

bundle: $(CZBUNDLE)
	@echo ">> emitter bundle up to date: $(CZBUNDLE)"

########################################################################
# dump/NAME — run the emitter on a test; show the emitted Scheme.
########################################################################
dump/%: $(CZBUNDLE)
	@set -uo pipefail; \
	SRC="$(TESTDIR)/$*.dats"; \
	[ -f "$$SRC" ] || { echo "!! not found: $$SRC" >&2; exit 2; }; \
	WORK="$(BUILD)/$*"; mkdir -p "$$WORK"; \
	$(NODE) $(CZBUNDLE) "$$SRC" > "$$WORK/stdout.txt" 2>"$$WORK/stderr.txt"; RC=$$?; \
	if [ "$$RC" -ne 0 ]; then echo "!! emitter exit $$RC" >&2; tail -40 "$$WORK/stderr.txt" >&2; exit "$$RC"; fi; \
	awk '/^;;==XATS2CZ-BEGIN==/{f=1;next} /^;;==XATS2CZ-END==/{f=0} f' "$$WORK/stdout.txt" > "$$WORK/$*.scm"; \
	echo "--- emitted Scheme: $$WORK/$*.scm ---"; cat "$$WORK/$*.scm"

########################################################################
# run/NAME — emit Scheme and run it on Chez (runtime ++ body).
########################################################################
run/%: $(CZBUNDLE)
	@set -uo pipefail; \
	SRC="$(TESTDIR)/$*.dats"; \
	[ -f "$$SRC" ] || { echo "!! not found: $$SRC" >&2; exit 2; }; \
	WORK="$(BUILD)/$*"; mkdir -p "$$WORK"; \
	$(NODE) $(CZBUNDLE) "$$SRC" > "$$WORK/stdout.txt" 2>"$$WORK/stderr.txt"; RC=$$?; \
	if [ "$$RC" -ne 0 ]; then echo "!! emitter exit $$RC" >&2; tail -40 "$$WORK/stderr.txt" >&2; exit "$$RC"; fi; \
	awk '/^;;==XATS2CZ-BEGIN==/{f=1;next} /^;;==XATS2CZ-END==/{f=0} f' "$$WORK/stdout.txt" > "$$WORK/$*.body.scm"; \
	cat $(CZRT_FILES) "$$WORK/$*.body.scm" > "$$WORK/$*.scm"; \
	echo ">> run on Chez: $$WORK/$*.scm" >&2; \
	$(CHEZ) "$$WORK/$*.scm"

########################################################################
# DIFFERENTIAL ORACLE — assert Chez stdout == xats2js (JS) stdout, byte-equal.
# The JS reference compiles the SAME source with the seed and runs the emitted
# JS under the Node prelude runtime.
########################################################################
NODEPRE := \
  $(S2R)/srcgen2_prelude.js $(S2R)/srcgen2_prelude_node.js \
  $(S2R)/srcgen2_precats.js $(S2R)/srcgen2_xatslib.js $(S2R)/xats2js_js1emit.js

.PHONY: suite
cmp/%: $(CZBUNDLE)
	@set -uo pipefail; \
	SRC="$(TESTDIR)/$*.dats"; \
	[ -f "$$SRC" ] || { echo "!! not found: $$SRC" >&2; exit 2; }; \
	WORK="$(BUILD)/$*"; mkdir -p "$$WORK"; \
	$(NODE) $(CZBUNDLE) "$$SRC" > "$$WORK/cz.out" 2>"$$WORK/cz.err" \
	  || { echo "FAIL  $*  (cz-emit crashed)"; tail -20 "$$WORK/cz.err" >&2; exit 1; }; \
	awk '/^;;==XATS2CZ-BEGIN==/{f=1;next} /^;;==XATS2CZ-END==/{f=0} f' "$$WORK/cz.out" > "$$WORK/$*.body.scm"; \
	if grep -q 'UNHANDLED\|BODILESS' "$$WORK/$*.body.scm"; then echo "FAIL  $*  (emitter UNHANDLED/BODILESS)"; exit 1; fi; \
	cat $(CZRT_FILES) "$$WORK/$*.body.scm" > "$$WORK/$*.scm"; \
	$(CHEZ) "$$WORK/$*.scm" > "$$WORK/chez.stdout" 2>"$$WORK/chez.runerr" \
	  || { echo "FAIL  $*  (chez run crashed)"; tail -20 "$$WORK/chez.runerr" >&2; exit 1; }; \
	GOLD="$(TESTDIR)/OUTS/$*.expected"; jsok=1; \
	$(NODE) $(JSEMIT) "$$SRC" > "$$WORK/$*.emit.js" 2>"$$WORK/jsemit.err"; \
	cat $(NODEPRE) "$$WORK/$*.emit.js" > "$$WORK/$*.run.js"; \
	node "$$WORK/$*.run.js" > "$$WORK/js.stdout" 2>"$$WORK/js.runerr" || jsok=0; \
	if [ "$$jsok" = 1 ]; then \
	  if cmp -s "$$WORK/chez.stdout" "$$WORK/js.stdout"; then \
	    mkdir -p "$(TESTDIR)/OUTS"; cp "$$WORK/chez.stdout" "$$GOLD"; \
	    echo "PASS  $*  ($$(wc -c < "$$WORK/chez.stdout") bytes, vs JS)"; \
	  else echo "FAIL  $*  (chez != js)"; diff <(xxd "$$WORK/chez.stdout") <(xxd "$$WORK/js.stdout") | head -20; exit 1; fi; \
	else \
	  if [ -f "$$GOLD" ]; then \
	    if cmp -s "$$WORK/chez.stdout" "$$GOLD"; then \
	      echo "PASS  $*  ($$(wc -c < "$$WORK/chez.stdout") bytes, vs golden; JS oracle broken)"; \
	    else echo "FAIL  $*  (chez != golden)"; diff <(xxd "$$WORK/chez.stdout") <(xxd "$$GOLD") | head -20; exit 1; fi; \
	  else echo "NOGOLD  $*  (JS oracle broken, no golden — 'make gold/$*' after verifying)"; exit 1; fi; \
	fi

# gold/NAME — record the current Chez stdout as the golden (only after manually
# verifying it, for programs the JS oracle can't run — e.g. deep TCO loops).
gold/%: $(CZBUNDLE)
	@set -uo pipefail; \
	SRC="$(TESTDIR)/$*.dats"; WORK="$(BUILD)/$*"; mkdir -p "$$WORK" "$(TESTDIR)/OUTS"; \
	$(NODE) $(CZBUNDLE) "$$SRC" > "$$WORK/cz.out" 2>"$$WORK/cz.err"; \
	awk '/^;;==XATS2CZ-BEGIN==/{f=1;next} /^;;==XATS2CZ-END==/{f=0} f' "$$WORK/cz.out" > "$$WORK/$*.body.scm"; \
	cat $(CZRT_FILES) "$$WORK/$*.body.scm" > "$$WORK/$*.scm"; \
	$(CHEZ) "$$WORK/$*.scm" > "$(TESTDIR)/OUTS/$*.expected" 2>"$$WORK/chez.runerr" \
	  || { echo "!! chez run failed" >&2; cat "$$WORK/chez.runerr" >&2; exit 1; }; \
	echo ">> golden saved: $(TESTDIR)/OUTS/$*.expected"; cat "$(TESTDIR)/OUTS/$*.expected"

suite: $(CZBUNDLE)
	@set -uo pipefail; pass=0; fail=0; fails=""; \
	for f in $(TESTDIR)/*.dats; do \
	  n=$$(basename "$$f" .dats); \
	  if $(MAKE) --no-print-directory cmp/$$n >"$(BUILD)/$$n.cmplog" 2>&1; then \
	    echo "$$(tail -1 "$(BUILD)/$$n.cmplog")"; pass=$$((pass+1)); \
	  else echo "FAIL  $$n"; fail=$$((fail+1)); fails="$$fails $$n"; fi; \
	done; \
	echo "====================================================="; \
	echo ">> SUITE: $$pass passed, $$fail failed$${fails:+ (failed:$$fails)}"; \
	[ "$$fail" -eq 0 ]

########################################################################
# SELF-HOST — build the Chez-hosted compiler and prove the fixpoint.
#
#   make fragments     seed-compile ALL compiler source -> per-file Scheme fragments
#   make selfhost      assemble fragments + runtime -> chez_selfhost.scm
#   make native        precompile that -> native chez_selfhost.so (3x faster startup)
#   make selfrun/NAME  run the self-hosted compiler on TEST/NAME.dats
#   make selfcompile   FIXPOINT: the Chez compiler recompiles its OWN source and we
#                      assert every fragment is byte-identical to the seed-built one
#
# The compiler-source set = the frontend SRCDATS (from the seed's Makefile_xjsemit),
# the xats2js backend's intrep0+trxd3i0, this emitter (cz0emit), and the driver.
########################################################################
SELFHOST     := $(BUILD)/selfhost
# SH_SCM  = gen-1 fragments (seed/Node-built);  SH_SCM2 = gen-2 (Chez-built; fixpoint).
# NOTE: no inline trailing comments on these — GNU make keeps the spaces in the value.
SH_SCM       := $(SELFHOST)/scm
SH_SCM2      := $(SELFHOST)/scm2
SELFHOST_SCM := $(SELFHOST)/chez_selfhost.scm
SELFHOST_SO  := $(SELFHOST)/chez_selfhost.so

SH_FE := $(shell awk '/^SRCDATS[ ]*:?=/{c=1} c{print; if(!/\\$$/)exit}' $(SRCGEN2)/Makefile_xjsemit | grep -oE '[a-z0-9_]+\.dats')
SH_BE := intrep0.dats intrep0_print0.dats intrep0_utils0.dats \
         trxd3i0.dats trxd3i0_myenv0.dats trxd3i0_dynexp.dats trxd3i0_decl00.dats
SH_FRAGS := $(addprefix $(SH_SCM)/fe_,$(addsuffix .scm,$(SH_FE))) \
            $(addprefix $(SH_SCM)/be_,$(addsuffix .scm,$(SH_BE))) \
            $(SH_SCM)/cz_cz0emit.dats.scm $(SH_SCM)/drv_driver.dats.scm

# gen-2 fragment list (Chez-built, one per gen-1 fragment) for the fixpoint check.
SH_FRAGS2 := $(addprefix $(SH_SCM2)/fe_,$(addsuffix .scm,$(SH_FE))) \
             $(addprefix $(SH_SCM2)/be_,$(addsuffix .scm,$(SH_BE))) \
             $(SH_SCM2)/cz_cz0emit.dats.scm $(SH_SCM2)/drv_driver.dats.scm

# cz-emit : SEED-compile one source -> gen-1 fragment (the BUNDLE is a prereq, so a
#           change to cz0emit.dats rebuilds the bundle and then every fragment).
# cz-self : CHEZ-compile one source -> gen-2 fragment (the self-hosted .so).
# Single logical line each (canned recipes; keeps GNU make 3.81 happy).
define cz-emit
@mkdir -p $(@D); echo ">> seed-emit $(<F)"; $(NODE_DEEP) $(CZBUNDLE) $< 2> $@.err | awk '/^;;==XATS2CZ-BEGIN==/{f=1;next}/^;;==XATS2CZ-END==/{f=0}f' > $@
endef
define cz-self
@mkdir -p $(@D); echo ">> chez-emit $(<F)"; chez --script $(SELFHOST_SO) $< 2>/dev/null | awk '/^;;==XATS2CZ-BEGIN==/{f=1;next}/^;;==XATS2CZ-END==/{f=0}f' > $@
endef

# gen-1 fragments (seed/Node)                       gen-2 fragments (self-hosted Chez)
$(SH_SCM)/fe_%.dats.scm: $(SRCGEN2)/DATS/%.dats $(CZBUNDLE)
	$(cz-emit)
$(SH_SCM)/be_%.dats.scm: $(SRCGEN2)/xats2js/srcgen1/DATS/%.dats $(CZBUNDLE)
	$(cz-emit)
$(SH_SCM)/cz_%.dats.scm: $(DATSDIR)/%.dats $(CZBUNDLE)
	$(cz-emit)
$(SH_SCM)/drv_driver.dats.scm: $(DRIVER) $(CZBUNDLE)
	$(cz-emit)
$(SH_SCM2)/fe_%.dats.scm: $(SRCGEN2)/DATS/%.dats $(SELFHOST_SO)
	$(cz-self)
$(SH_SCM2)/be_%.dats.scm: $(SRCGEN2)/xats2js/srcgen1/DATS/%.dats $(SELFHOST_SO)
	$(cz-self)
$(SH_SCM2)/cz_%.dats.scm: $(DATSDIR)/%.dats $(SELFHOST_SO)
	$(cz-self)
$(SH_SCM2)/drv_driver.dats.scm: $(DRIVER) $(SELFHOST_SO)
	$(cz-self)

.PHONY: fragments selfhost native selfcompile
# fragments: seed-compile all $(words $(SH_FRAGS)) source files (use `make -jN`).
fragments: $(SH_FRAGS)
	@echo ">> $(words $(SH_FRAGS)) fragments up to date in $(SH_SCM)"

# selfhost: runtime ++ fragments (in concat order) -> the Chez self-host compiler.
selfhost: $(SELFHOST_SCM)
$(SELFHOST_SCM): $(CZRT_FILES) $(SH_FRAGS)
	@echo ">> assemble chez_selfhost.scm (runtime + $(words $(SH_FRAGS)) fragments)"
	@cat $(CZRT_FILES) $(SH_FRAGS) > $@
	@echo "   -> $@ ($$(wc -l < $@) lines)"

# native: precompile the self-host compiler to a native .so (optimize-level 3).
native: $(SELFHOST_SO)
$(SELFHOST_SO): $(SELFHOST_SCM)
	@echo '(optimize-level 3)(generate-inspector-information #f)(compile-file "$(SELFHOST_SCM)" "$(SELFHOST_SO)")' | chez -q
	@echo ">> built $@  (run: make selfrun/NAME)"

# selfrun/NAME: run the self-hosted (native .so) compiler on TEST/NAME.dats.
selfrun/%: $(SELFHOST_SO)
	@chez --script $(SELFHOST_SO) $(TESTDIR)/$*.dats 2>/dev/null

# selfcompile: the FIXPOINT.  The gen-2 fragments are built by the Chez compiler
# (above pattern rules; `make -jN selfcompile` parallelizes), then we assert each
# is byte-identical to the seed-built gen-1 fragment.
selfcompile: $(SH_FRAGS) $(SH_FRAGS2)
	@id=0; df=0; em=0; bad=""; \
	for g1 in $(SH_FRAGS); do t=$$(basename $$g1); g2=$(SH_SCM2)/$$t; \
	  if diff -q $$g1 $$g2 >/dev/null 2>&1; then id=$$((id+1)); \
	  elif [ ! -s $$g2 ]; then em=$$((em+1)); bad="$$bad EMPTY:$$t"; \
	  else df=$$((df+1)); bad="$$bad DIFF:$$t"; fi; \
	done; \
	echo "=== FIXPOINT: $$id identical / $$df diff / $$em real-empty (of $(words $(SH_FRAGS))) ==="; \
	[ -z "$$bad" ] && echo "*** the Chez compiler reproduces all its own fragments byte-for-byte ***" \
	              || { echo "non-identical:$$bad"; exit 1; }

########################################################################
clean:
	@echo ">> clean emitter artifacts (keep cached fixed libs + self-host fragments)"
	@rm -f $(OUT0) $(NSJS) $(LIB2CZ) $(DRV_CZ) $(CZBUNDLE) $(JSDIR)/*.err $(BUILD)/transpile_*.err

cleanall: clean
	@echo ">> cleanall (also cached fixed libs + the assembled self-host compiler)"
	@rm -f $(OPT_JS1) $(JS_JS2)
	@rm -rf $(SELFHOST)

distclean:
	@echo ">> distclean — remove the entire BUILD/ tree (everything is regenerable)"
	@rm -rf $(BUILD)
