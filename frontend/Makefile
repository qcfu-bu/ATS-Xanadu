SHELL := /bin/bash
.DEFAULT_GOAL := help

XATSHOME ?= $(abspath ..)
export XATSHOME

BUILD ?= BUILD
USER_PP_OUT := $(filter command line environment environment override,$(origin PP_OUT))
PP_OUT ?= $(BUILD)/pp-corpus-make
PP_MODE ?= auto
PP_FILE_LIST ?= CORPUS/pp-default-auto.files
PP_JOBS ?= 8
PP_REPARSE ?= 1
PP_STRICT ?= 1

PP_BUNDLE := $(BUILD)/pp-corpus.js
M3_BUNDLE := $(BUILD)/pyfront-m3.js
PP_BUNDLE_SRC := DATS/pyprint.dats DATS/pyprint_main.dats CATS/pyprint.cats build-pp-corpus.sh
M3_BUNDLE_SRC := $(wildcard SATS/*.sats DATS/*.dats CATS/*.cats pyrt/*.sats) build-m3.sh

ifeq ($(origin PP_FILES),undefined)
PP_FILES := $(shell sed -e '/^[[:space:]]*\#/d' -e '/^[[:space:]]*$$/d' "$(PP_FILE_LIST)")
endif
PP_ITEM_DIR := $(PP_OUT)/items
PP_SUMMARY := $(PP_OUT)/summary.tsv
PP_AUTO_OUT := $(if $(USER_PP_OUT),$(PP_OUT),$(BUILD)/pp-corpus-make-auto)
PP_DYNAMIC_OUT := $(if $(USER_PP_OUT),$(PP_OUT),$(BUILD)/pp-corpus-make-dynamic)

pp_slug = $(subst /,_,$(subst ..,_,$(1)))

ifeq ($(PP_REPARSE),0)
PP_REPARSE_FLAGS := --no-reparse
PP_ITEM_DEPS := $(PP_BUNDLE)
else
PP_REPARSE_FLAGS :=
PP_ITEM_DEPS := $(PP_BUNDLE) $(M3_BUNDLE)
endif

PP_TARGETS := $(foreach f,$(PP_FILES),$(PP_ITEM_DIR)/$(call pp_slug,$(f)).done)
PP_SUMMARIES := $(foreach f,$(PP_FILES),$(PP_ITEM_DIR)/$(call pp_slug,$(f))/summary.tsv)

.PHONY: help pp-bundles pp-corpus pp-corpus-auto pp-corpus-dynamic clean-pp-corpus

help:
	@echo "Targets:"
	@echo "  make pp-corpus-auto           # default static+dynamic corpus in parallel (PP_JOBS=$(PP_JOBS))"
	@echo "  make pp-corpus-dynamic        # default dynamic corpus in parallel (PP_JOBS=$(PP_JOBS))"
	@echo "  make -j8 pp-corpus PP_FILE_LIST=PATH PP_MODE=auto PP_OUT=BUILD/pp-corpus-make-custom"
	@echo "  make -j8 pp-corpus PP_MODE=dynamic PP_FILES='file1.dats file2.dats' PP_OUT=BUILD/probe"
	@echo "  make pp-bundles               # build/rebuild shared pyprint + M3 bundles"
	@echo ""
	@echo "Options:"
	@echo "  PP_JOBS=8                     # jobs used by pp-corpus-auto/dynamic wrappers"
	@echo "  PP_REPARSE=0                  # translate only, skip M3 reparse"
	@echo "  PP_STRICT=0                   # keep the summary even when TODO/M3 checks fail"
	@echo "  PP_OUT=BUILD/dir              # output directory"

pp-bundles: $(PP_BUNDLE) $(M3_BUNDLE)

$(PP_BUNDLE): $(PP_BUNDLE_SRC)
	@mkdir -p "$(BUILD)"
	@bash build-pp-corpus.sh --rebuild-pp --no-reparse --out-dir "$(BUILD)/pp-corpus-bundle-smoke" "$(firstword $(PP_FILES))"

$(M3_BUNDLE): $(M3_BUNDLE_SRC)
	@bash build-m3.sh

pp-corpus-auto:
	+$(MAKE) -j$(PP_JOBS) pp-corpus PP_MODE=auto PP_FILE_LIST=CORPUS/pp-default-auto.files PP_OUT=$(PP_AUTO_OUT)

pp-corpus-dynamic:
	+$(MAKE) -j$(PP_JOBS) pp-corpus PP_MODE=dynamic PP_FILE_LIST=CORPUS/pp-default-dynamic.files PP_OUT=$(PP_DYNAMIC_OUT)

pp-corpus: $(PP_SUMMARY)
	@true

$(PP_SUMMARY): $(PP_TARGETS) Makefile
	@mkdir -p "$(PP_OUT)"
	@printf 'stadyn\tinput\tpyprint_rc\temitted_lines\ttodo_pp\tm3_nerror\tm3_zero\temitted_file\tm3_status\n' > "$@"
	@for s in $(PP_SUMMARIES); do tail -n +2 "$$s" >> "$@"; done
	@total=$$(tail -n +2 "$@" | wc -l | tr -d ' '); \
	  todos=$$(awk -F '\t' 'NR>1 { sum += $$5 } END { print sum + 0 }' "$@"); \
	  zeros=$$(awk -F '\t' 'NR>1 && $$7 == "yes" { n++ } END { print n + 0 }' "$@"); \
	  echo ">> parallel PP corpus summary: $@"; \
	  echo ">> files audited: $$total"; \
	  echo ">> total # TODO(pp): $$todos"; \
	  echo ">> M3 reparse reached nerror=0: $$zeros / $$total"; \
	  if [ "$(PP_STRICT)" != "0" ]; then \
	    if [ "$$todos" -ne 0 ]; then echo "!! PP corpus strict check failed: TODO(pp) markers remain" >&2; exit 1; fi; \
	    if [ "$(PP_REPARSE)" != "0" ] && [ "$$zeros" -ne "$$total" ]; then echo "!! PP corpus strict check failed: M3 reparse did not reach nerror=0 for every file" >&2; exit 1; fi; \
	  fi

define PP_ITEM_template
$(PP_ITEM_DIR)/$(call pp_slug,$(1)).done: $(PP_ITEM_DEPS) build-pp-corpus.sh Makefile
	@mkdir -p "$(PP_ITEM_DIR)/$(call pp_slug,$(1))"
	@echo ">> PP $(1)"
	@bash build-pp-corpus.sh --stadyn $(PP_MODE) --reuse-bundle $(PP_REPARSE_FLAGS) --out-dir "$(PP_ITEM_DIR)/$(call pp_slug,$(1))" "$(1)" > "$(PP_ITEM_DIR)/$(call pp_slug,$(1)).log" 2>&1
	@touch "$$@"
endef

$(foreach file,$(PP_FILES),$(eval $(call PP_ITEM_template,$(file))))

clean-pp-corpus:
	rm -rf "$(PP_OUT)" "$(BUILD)/pp-corpus-make-auto" "$(BUILD)/pp-corpus-make-dynamic"
