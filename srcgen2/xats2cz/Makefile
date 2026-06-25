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
.PHONY: all bundle clean cleanall help dirs
.DEFAULT_GOAL := bundle
.SECONDARY:
.PRECIOUS: $(OUT0) $(NSJS)

all: bundle

help:
	@echo "xats2cz targets: bundle | dump/NAME | run/NAME | clean | cleanall"

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
clean:
	@echo ">> clean emitter artifacts (keep cached fixed libs)"
	@rm -f $(OUT0) $(NSJS) $(LIB2CZ) $(DRV_CZ) $(CZBUNDLE) $(JSDIR)/*.err $(BUILD)/transpile_*.err

cleanall: clean
	@echo ">> cleanall (also cached fixed libs)"
	@rm -f $(OPT_JS1) $(JS_JS2)
