########################################################################
# xats2chez — Chez Scheme backend for ATS3.  Bootstrap/build/run harness.
#
# Adapted from srcgen2/xats2go/Makefile but SIMPLER: this backend emits
# Scheme from the expression-shaped intrep0, so intrep1/trxi0i1 are NOT in
# the build, and lib2xats2cc.js is reused from the prebuilt frontend/BUILD
# (no local fork yet; exceptions/I0Etry0 come in a later milestone).
#
# The emitter is ATS3 source, transpiled to JS by the prebuilt jsemit00 and
# run on Node; it emits Scheme that runs on Chez.
#
#   make            build the emitter bundle (incremental)
#   make -j8        cold/parallel transpile + bundle
#   make dump/NAME  run emitter on TEST/NAME.dats; show intrep0 dump + Scheme
#   make run/NAME   emit Scheme for TEST/NAME.dats, run it on Chez
#   make TEST=path run-path
#   make clean / cleanall
########################################################################

SHELL := /bin/bash

########################################################################
# Toolchain
########################################################################
XATSHOME  ?= /Users/qcfu/Projects/ATS-Xanadu
export XATSHOME            # jsemit00 resolves /prelude/* relative to it
SRCGEN1   := $(XATSHOME)/srcgen1
SRCGEN2   := $(XATSHOME)/srcgen2
FRONTEND  := $(XATSHOME)/frontend
XATS2CHEZ := $(SRCGEN2)/xats2chez/srcgen2
CHEZRT    := $(SRCGEN2)/xats2chez/runtime/scheme
JSSHIM    := $(SRCGEN2)/xats2chez/runtime/jsshim/gen-i0varfst-shim.sh

JSEMIT  := $(XATSHOME)/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js
LIB2OPT := $(SRCGEN2)/lib/lib2xatsopt.js
LIB2CC  := $(FRONTEND)/BUILD/lib2xats2cc.js
LIB2JS  := $(FRONTEND)/BUILD/lib2xats2js.js

NODE  := node --stack-size=8801
CHEZ  ?= chez --script

BUILD   := $(XATS2CHEZ)/BUILD
JSDIR   := $(BUILD)/JS
V8CACHE := $(BUILD)/.v8cache
export NODE_COMPILE_CACHE := $(V8CACHE)

DATSDIR := $(XATS2CHEZ)/DATS
UTILDIR := $(XATS2CHEZ)/UTIL
TESTDIR := $(XATS2CHEZ)/TEST

MINLINES := 3

########################################################################
# THE EMITTER SOURCE LIST — concat / namespace-index order (index = 100 +
# position, a 3-digit pure function of position).  The tmplib MUST be last.
# (M0 has only the stub + tmplib; M1 inserts the env + utils0/dynexp/decl00
# BEFORE chez0emit.dats and AFTER any env.)
########################################################################
CHEZ_DATS := \
  chez0emit.dats \
  xats2chez_tmplib.dats

DRIVER := $(UTILDIR)/xats2chez_czemit01.dats

########################################################################
# RUNTIME prefix needed to RUN the emitter bundle on Node (verbatim from
# xats2go).  This is the JS runtime the (JS-compiled) emitter itself needs;
# it is NOT the Chez runtime for emitted programs.
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
# Derived file lists
########################################################################
OUT0  := $(patsubst %.dats,$(JSDIR)/%_dats_out0.js,$(CHEZ_DATS))
NSJS  := $(patsubst %.dats,$(JSDIR)/%_dats_ns.js,$(CHEZ_DATS))

LIB2CHEZ := $(BUILD)/lib2xats2chez.js
DRV_CHEZ := $(BUILD)/xats2chez_czemit01_dats.js

OPT_JS1   := $(BUILD)/opt.js1.js
CC_JS2    := $(BUILD)/cc.js2.js
CHEZ_SHIM := $(BUILD)/i0varfst-shim.js
SHIMNAMES := $(BUILD)/i0varfst-shim.optnames.js

CHEZBUNDLE := $(BUILD)/xats2chez-bundle.js

########################################################################
.PHONY: all bundle clean cleanall help dirs
.DEFAULT_GOAL := bundle
.SECONDARY:
.PRECIOUS: $(OUT0) $(NSJS)

all: bundle

help:
	@echo "xats2chez targets:"
	@echo "  make / make -j8     build the emitter bundle"
	@echo "  make dump/NAME      run emitter on TEST/NAME.dats; intrep0 dump + Scheme"
	@echo "  make run/NAME       emit Scheme for TEST/NAME.dats and run on Chez"
	@echo "  make clean          remove emitter artifacts (keep cached fixed libs)"
	@echo "  make cleanall       also remove cached fixed libs (NEVER lib2xatsopt.js)"

dirs:
	@mkdir -p $(JSDIR)

########################################################################
# STEP A — per-.dats transpile (jsemit00), fail-loud-on-empty.
########################################################################
$(JSDIR)/%_dats_out0.js: $(DATSDIR)/%.dats | dirs
	@echo ">> transpile $*.dats"
	@$(NODE) $(JSEMIT) $< > $@ 2> $@.err; \
	if [ "$$(wc -l < $@)" -lt $(MINLINES) ]; then \
	  echo "!! transpile FAILED for $< (see $@.err)" >&2; \
	  tail -40 $@.err >&2; rm -f $@; exit 1; \
	fi; \
	if grep -qE "F3PERR0-ERROR.*$*\.dats|PREAD00-ERROR.*$*\.dats" $@.err; then \
	  echo "!! parse/typecheck ERROR in $*.dats (see $@.err):" >&2; \
	  grep -E "ERROR.*$*\.dats" $@.err | head -12 >&2; rm -f $@; exit 1; \
	fi

########################################################################
# STEP B — namespace-sed jsxtnm -> jsx<NNN>tnm (3-digit, idx = 100 + pos).
########################################################################
$(JSDIR)/%_dats_ns.js: $(JSDIR)/%_dats_out0.js
	@idx=$$(i=100; for f in $(CHEZ_DATS); do \
	          if [ "$$f" = "$*.dats" ]; then echo $$i; break; fi; i=$$((i+1)); \
	        done); \
	sed -e "s/jsxtnm/jsx$${idx}tnm/g" $< > $@

########################################################################
# STEP C — lib2xats2chez.js : concat namespaced fragments in CHEZ_DATS order.
########################################################################
$(LIB2CHEZ): $(NSJS)
	@echo ">> concat lib2xats2chez.js ($(words $(CHEZ_DATS)) files)"
	@cat $(NSJS) > $@
	@echo "   -> $@ ($$(wc -l < $@) lines)"

########################################################################
# STEP D — the driver transpile.
########################################################################
$(DRV_CHEZ): $(DRIVER) | dirs
	@echo ">> transpile chez driver"
	@$(NODE) $(JSEMIT) $< > $@ 2> $(BUILD)/transpile_drv.err; \
	if [ "$$(wc -l < $@)" -lt 5 ]; then \
	  echo "!! driver transpile too small" >&2; \
	  tail -40 $(BUILD)/transpile_drv.err >&2; rm -f $@; exit 1; \
	fi

########################################################################
# CACHED namespace-sed'd FIXED libs (pure function of FIXED input; built once).
########################################################################
$(OPT_JS1): $(LIB2OPT) | dirs
	@echo ">> cache js1.lib2xatsopt.js (one-time ~171MB sed)"
	@sed -E 's/jsx(...)tnm/js1\1tnm/g' $(LIB2OPT) > $@

$(CC_JS2): $(LIB2CC) | dirs
	@echo ">> cache js2.lib2xats2cc.js (prebuilt frontend cc, one-time sed)"
	@sed -E 's/jsx(...)tnm/js2\1tnm/g' $(LIB2CC) > $@

########################################################################
# CACHED i0varfst shim (mandatory: lib2xats2cc.js references-but-never-defines
# the 6 i0varfst_* funset helpers; any program with a function crashes without
# it).  Scans cc.js2 + a tiny extract of the two opt-resident helper names.
########################################################################
$(SHIMNAMES): $(OPT_JS1) | dirs
	@echo ">> extract opt-resident shim helper names (one-time grep over opt.js1)"
	@grep -oE 'd2var_get_stmp_[0-9]+|stamp_get_uint_[0-9]+' $(OPT_JS1) | sort -u > $@

$(CHEZ_SHIM): $(CC_JS2) $(SHIMNAMES) $(JSSHIM) | dirs
	@echo ">> cache i0varfst shim (scans cc.js2 + opt-names)"
	@cat $(CC_JS2) $(SHIMNAMES) > $@.scan.tmp
	@bash $(JSSHIM) $@.scan.tmp $@ >/dev/null \
	  || { echo "!! shim gen failed" >&2; rm -f $@.scan.tmp; exit 1; }
	@rm -f $@.scan.tmp

########################################################################
# THE EMITTER BUNDLE — shim ++ RUNTIME ++ js1.opt ++ js2.cc ++ js3.chez ++ driver.
########################################################################
$(CHEZBUNDLE): $(CHEZ_SHIM) $(OPT_JS1) $(CC_JS2) $(LIB2CHEZ) $(DRV_CHEZ) | dirs
	@echo ">> link chez-emitter bundle (shim + runtime + js1.opt + js2.cc + js3.chez + driver)"
	@cat $(CHEZ_SHIM) $(RUNTIME) $(OPT_JS1) $(CC_JS2) \
	     <(sed -E 's/jsx(...)tnm/js3\1tnm/g' $(LIB2CHEZ)) \
	     $(DRV_CHEZ) > $@
	@echo "   -> $@"

bundle: $(CHEZBUNDLE)
	@echo ">> emitter bundle up to date: $(CHEZBUNDLE)"

########################################################################
# dump/NAME — run the emitter on a test; show the intrep0 dump (stderr) and
# the emitted Scheme (between the sentinels).
########################################################################
dump/%: $(CHEZBUNDLE)
	@set -uo pipefail; \
	SRC="$(TESTDIR)/$*.dats"; \
	[ -f "$$SRC" ] || { echo "!! not found: $$SRC" >&2; exit 2; }; \
	WORK="$(BUILD)/$*"; mkdir -p "$$WORK"; \
	echo "======================================================================"; \
	echo ">> EMIT: $* "; \
	echo "======================================================================"; \
	$(NODE) $(CHEZBUNDLE) "$$SRC" > "$$WORK/stdout.txt" 2>"$$WORK/stderr.txt"; RC=$$?; \
	echo "--- intrep0 dump (stderr) ---"; \
	sed -n '/intrep0 dump BEGIN/,/intrep0 dump END/p' "$$WORK/stderr.txt" || true; \
	if [ "$$RC" -ne 0 ]; then echo "!! emitter exit $$RC" >&2; tail -40 "$$WORK/stderr.txt" >&2; exit "$$RC"; fi; \
	awk '/^;;==XATS2CHEZ-BEGIN==/{f=1;next} /^;;==XATS2CHEZ-END==/{f=0} f' "$$WORK/stdout.txt" > "$$WORK/$*.dump.scm"; \
	echo "--- emitted Scheme: $$WORK/$*.dump.scm ---"; \
	cat "$$WORK/$*.dump.scm"

########################################################################
# run/NAME — emit Scheme and run it on Chez.
########################################################################
run/%: $(CHEZBUNDLE)
	@set -uo pipefail; \
	SRC="$(TESTDIR)/$*.dats"; \
	[ -f "$$SRC" ] || { echo "!! not found: $$SRC" >&2; exit 2; }; \
	WORK="$(BUILD)/$*"; mkdir -p "$$WORK"; \
	$(NODE) $(CHEZBUNDLE) "$$SRC" > "$$WORK/stdout.txt" 2>"$$WORK/stderr.txt"; RC=$$?; \
	if [ "$$RC" -ne 0 ]; then echo "!! emitter exit $$RC" >&2; tail -40 "$$WORK/stderr.txt" >&2; exit "$$RC"; fi; \
	awk '/^;;==XATS2CHEZ-BEGIN==/{f=1;next} /^;;==XATS2CHEZ-END==/{f=0} f' "$$WORK/stdout.txt" > "$$WORK/$*.body.scm"; \
	[ -f "$(CHEZRT)/xats2chez_runtime.scm" ] && RT="$(CHEZRT)/xats2chez_runtime.scm" || RT=/dev/null; \
	cat "$$RT" "$$WORK/$*.body.scm" > "$$WORK/$*.scm"; \
	echo ">> run on Chez: $$WORK/$*.scm"; \
	$(CHEZ) "$$WORK/$*.scm"

########################################################################
# DIFFERENTIAL JS ORACLE — assert Chez stdout == JS-backend stdout, byte-equal.
# The JS reference bundle emits from intrep1 via js1emit (lib2xats2js); it uses
# the SAME prebuilt cc/opt as the Chez bundle, so a single CC_JS2 serves both.
########################################################################
JSDRIVER  := $(SRCGEN2)/xats2js/srcgen2/UTIL/xats2js_jsemit01.dats
NS2R      := $(SRCGEN2)/xats2js/srcgen1/xshared/runtime
NODEPRE   := $(NS2R)/srcgen2_prelude.js $(NS2R)/srcgen2_prelude_node.js \
             $(NS2R)/srcgen2_precats.js $(NS2R)/srcgen2_xatslib.js \
             $(NS2R)/xats2js_js1emit.js
JS_SHIM   := $(BUILD)/i0varfst-shim-js.js
JDRV      := $(BUILD)/xats2js_jsemit01_dats.js
JSPATCHED := $(BUILD)/xats2js-ref-bundle.js

.PHONY: suite

# JS shim: like the chez shim but scans lib2xats2js too, so the missing
# tokenfpr (referenced by js1emit on lambdas/fix) is no-op-defined.
$(JS_SHIM): $(CC_JS2) $(SHIMNAMES) $(LIB2JS) $(JSSHIM) | dirs
	@echo ">> cache i0varfst+tokenfpr shim (JS oracle)"
	@cat $(CC_JS2) $(SHIMNAMES) $(LIB2JS) > $@.scan.tmp
	@bash $(JSSHIM) $@.scan.tmp $@ >/dev/null \
	  || { echo "!! JS shim gen failed" >&2; rm -f $@.scan.tmp; exit 1; }
	@rm -f $@.scan.tmp

$(JDRV): $(JSDRIVER) | dirs
	@echo ">> transpile js-oracle driver"
	@$(NODE) $(JSEMIT) $< > $@ 2> $(BUILD)/transpile_jsdrv.err; \
	if [ "$$(wc -l < $@)" -lt 5 ]; then \
	  echo "!! js driver transpile too small" >&2; \
	  tail -40 $(BUILD)/transpile_jsdrv.err >&2; rm -f $@; exit 1; fi

$(JSPATCHED): $(JS_SHIM) $(OPT_JS1) $(CC_JS2) $(LIB2JS) $(JDRV) | dirs
	@echo ">> link JS-oracle reference bundle"
	@cat $(JS_SHIM) $(RUNTIME) $(OPT_JS1) $(CC_JS2) \
	     <(sed -E 's/jsx(...)tnm/js3\1tnm/g' $(LIB2JS)) \
	     $(JDRV) > $@
	@echo "   -> $@"

# cmp/NAME — emit + run on BOTH backends, assert byte-equal stdout.
cmp/%: $(CHEZBUNDLE) $(JSPATCHED)
	@set -uo pipefail; \
	SRC="$(TESTDIR)/$*.dats"; \
	[ -f "$$SRC" ] || { echo "!! not found: $$SRC" >&2; exit 2; }; \
	WORK="$(BUILD)/$*"; mkdir -p "$$WORK"; \
	$(NODE) $(CHEZBUNDLE) "$$SRC" > "$$WORK/cz.out" 2>"$$WORK/cz.err" \
	  || { echo "!! [$*] chez-emit failed" >&2; tail -20 "$$WORK/cz.err" >&2; exit 1; }; \
	awk '/^;;==XATS2CHEZ-BEGIN==/{f=1;next} /^;;==XATS2CHEZ-END==/{f=0} f' "$$WORK/cz.out" > "$$WORK/$*.body.scm"; \
	[ -f "$(CHEZRT)/xats2chez_runtime.scm" ] && RT="$(CHEZRT)/xats2chez_runtime.scm" || RT=/dev/null; \
	cat "$$RT" "$$WORK/$*.body.scm" > "$$WORK/$*.scm"; \
	$(CHEZ) "$$WORK/$*.scm" > "$$WORK/chez.stdout" 2>"$$WORK/chez.runerr" \
	  || { echo "!! [$*] chez run failed" >&2; tail -20 "$$WORK/chez.runerr" >&2; exit 1; }; \
	$(NODE) $(JSPATCHED) "$$SRC" > "$$WORK/$*.emit.js" 2>"$$WORK/jsemit.err"; \
	awk -v n="$*" 'f||$$0 ~ ("^// LCSRCsome1.*"n){f=1; print}' "$$WORK/$*.emit.js" > "$$WORK/$*.user.js"; \
	cat $(NODEPRE) "$$WORK/$*.user.js" > "$$WORK/$*.run.js"; \
	node "$$WORK/$*.run.js" > "$$WORK/js.stdout" 2>"$$WORK/js.runerr" \
	  || { echo "!! [$*] js run failed" >&2; tail -20 "$$WORK/js.runerr" >&2; exit 1; }; \
	if cmp -s "$$WORK/chez.stdout" "$$WORK/js.stdout"; then \
	  echo "PASS  $*  ($$(wc -c < "$$WORK/chez.stdout") bytes)"; \
	else \
	  echo "FAIL  $*  (chez != js)"; \
	  echo "--- chez ---"; cat "$$WORK/chez.stdout"; \
	  echo "--- js   ---"; cat "$$WORK/js.stdout"; \
	  diff <(xxd "$$WORK/chez.stdout") <(xxd "$$WORK/js.stdout") | head -20; exit 1; \
	fi

# suite — differential oracle over every TEST/*.dats.
suite: $(CHEZBUNDLE) $(JSPATCHED)
	@set -uo pipefail; pass=0; fail=0; fails=""; \
	for f in $(TESTDIR)/*.dats; do \
	  n=$$(basename "$$f" .dats); \
	  if $(MAKE) --no-print-directory cmp/$$n >"$(BUILD)/$$n.cmplog" 2>&1; then \
	    echo "$$(tail -1 "$(BUILD)/$$n.cmplog")"; pass=$$((pass+1)); \
	  else \
	    echo "FAIL  $$n"; fail=$$((fail+1)); fails="$$fails $$n"; \
	  fi; \
	done; \
	echo "====================================================="; \
	echo ">> SUITE: $$pass passed, $$fail failed$${fails:+ (failed:$$fails)}"; \
	[ "$$fail" -eq 0 ]

########################################################################
clean:
	@echo ">> clean emitter artifacts (keep cached fixed libs)"
	@rm -f $(OUT0) $(NSJS) $(LIB2CHEZ) $(DRV_CHEZ) $(CHEZBUNDLE)
	@rm -f $(JSDIR)/*.err $(BUILD)/transpile_*.err

cleanall: clean
	@echo ">> cleanall (also cached fixed libs; NEVER lib2xatsopt.js)"
	@rm -f $(OPT_JS1) $(CC_JS2) $(CHEZ_SHIM) $(SHIMNAMES)
	@rm -rf $(V8CACHE)
