#!/usr/bin/env bash
# assemble.sh — emit all emitter modules to Go and assemble them into one
# package, to drive a multi-module `go build` toward self-hosting.
set -uo pipefail
# repo root: three levels up from this script (srcgen2/xats2go/selfhost-build)
X="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export XATSHOME=$X
# deep-recursion headroom: go1emit_dynexp.dats overflows an 8MB OS stack
# (SIGSEGV with an EMPTY emit, no error text) — raise the OS limit where
# allowed and keep V8's limit under it.  Stack size never changes emitted
# bytes, only the crash threshold.
ulimit -s 65520 2>/dev/null || true
NODESTK="${NODESTK:-50000}"
GOPATCHED=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
OUT=$X/srcgen2/xats2go/selfhost-build
RUNTIME=$X/srcgen2/xats2go/runtime/xatsgo
mkdir -p "$OUT/src"
EMIT="$OUT/emit"; mkdir -p "$EMIT"

# 1. emit each module to Go (between sentinels), strip header (first 6 lines) +
#    the trailing trivial `func main(){...}`.  Each module's goxtnm temps are
#    renamed go<N>tnm / gof<N>tnm (the same per-module rename the JS bootstrap
#    does with jsxtnm -> jsx<N>tnm) so module-level `var` temps cannot collide
#    in the concatenated package.
: > "$OUT/src/emitter_all.go"
printf 'package main\n\nimport "xatsgo"\nimport "unsafe"\n\nvar _ = xatsgo.XATSNIL\nvar _ unsafe.Pointer\n\n' > "$OUT/src/emitter_all.go"
# MODULE-INIT PRESERVATION: each module's top-level effect initializers (e.g.
# lexing_kword_init that populates the keyword table, or dynexp2's stamp
# counters) live in that module's `func main`.  Stripping main dropped them,
# so directives never resolved and the self-hosted parser rejected every
# declaration.  Instead RENAME each module's main to a unique zzmodinit_<MI>
# and register it; a generated `func init()` runs them all (in assembly order)
# before the driver's main — matching the JS backend, which runs every
# module's top-level effects at load.
MI=0
: > "$OUT/src/.modinits"
: > "$OUT/src/.layouts"
n=0
for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
  m="$(basename "$f" .dats)"
  if [ ! -s "$EMIT/$m.go" ] || [ "$f" -nt "$EMIT/$m.go" ] || [ "$GOPATCHED" -nt "$EMIT/$m.go" ]; then
    node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
  fi
  # strip header (up to first `func`/`var`); RENAME the module's main to a
  # per-module init so its top-level effects survive.
  awk 'BEGIN{started=0}
       /^type zzs_[a-z]* struct \{$/{lay=1}
       lay{if($0=="}"){lay=0}; next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed -E "s/goxtnm([0-9])/go${n}tnm\\1/g" \
    | sed "s/^func main() {\$/func zzmodinit_${MI}() {/" >> "$OUT/src/emitter_all.go"
  awk '/^type zzs_[a-z]* struct \{$/{lay=1} lay{print; if($0=="}"){lay=0}}' "$EMIT/$m.go" >> "$OUT/src/.layouts"
  echo "zzmodinit_${MI}" >> "$OUT/src/.modinits"
  MI=$((MI+1))
  printf "\n" >> "$OUT/src/emitter_all.go"
  n=$((n+1))
done

# 1b. emit the designated FRONTEND modules (host-compiler library, from
#     srcgen2/DATS) and append them the same way.  These resolve the
#     package-routed frontend symbols (stamp_cmp_<N>, ...) the emitter calls;
#     the bundle assigns STABLE stamps across separately-emitted modules, so a
#     frontend def `stamp_cmp_1903` matches the emitter call site `stamp_cmp_1903`.
FRONTEND="xbasics xbasics_print0 xlibext xlibext_tmplib xlibext_jsemit xlibext_pyemit xsynoug xerrory xstamp0 xstamp0_print0 xstamp0_tmpmap xsymbol xsymbol_print0 xsymbol_mymap0 xsymbol_inits0 xlabel0 xlabel0_print0 xsymmap xsymmap_topmap xsymmap_stkmap xglobal xglobal_ext000 filpath filpath_print0 filpath_drpth0 filpath_fpath0 filpath_search locinfo locinfo_print0 lexbuf0 lexbuf0_cstrx1 lexbuf0_cstrx2 lexing0 lexing0_print0 lexing0_mymap0 lexing0_kword0 lexing0_token0 lexing0_utils1 lexing0_utils2 lexing0_ext000 staexp0 staexp0_print0 dynexp0 dynexp0_print0 parsing parsing_basics parsing_tokbuf parsing_utils0 parsing_staexp parsing_dynexp parsing_decl00 pread00 pread00_staexp pread00_dynexp pread00_decl00 pread00_errmsg xfixity staexp1 staexp1_print0 dynexp1 dynexp1_print0 gmacro1 gmacro1_print0 trans01 trans01_myenv0 trans01_utils0 trans01_staexp trans01_dynexp trans01_decl00 tread01 tread01_staexp tread01_dynexp tread01_decl00 tread01_errmsg staexp2 statyp2 staexp2_print0 statyp2_print0 staexp2_inits0 statyp2_inits0 staexp2_utils1 staexp2_utils2 statyp2_utils1 statyp2_utils2 statyp2_tmplib dynexp2 dynexp2_print0 dynexp2_utils0 dynexp2_tmplib nmspace trans12 trans11_myenv0 trans12_myenv0 trans11_gmacro trans12_gmacro trans12_utils0 trans12_staexp trans12_dynexp trans12_decl00 tread12 tread12_staexp tread12_dynexp tread12_decl00 tread12_errmsg trans2a trans2a_myenv0 trans2a_utils0 trans2a_dynexp trans2a_decl00 trsym2b trsym2b_utils0 trsym2b_dynexp trsym2b_decl00 t2read0 t2read0_dynexp t2read0_decl00 f2perr0 f2perr0_staexp f2perr0_dynexp f2perr0_decl00 dynexp3 dynexp3_print0 dynexp3_utils0 dynexp3_tmplib trans23 trans23_myenv0 trans23_utils0 trans23_dynexp trans23_decl00 tread23 tread23_dynexp tread23_decl00 tread23_errmsg trans3a trans3a_myenv0 trans3a_staexp trans3a_dynexp trans3a_decl00 tread3a tread3a_staexp tread3a_dynexp tread3a_decl00 trtmp3b trtmp3b_myenv0 trtmp3b_utils0 trtmp3b_dynexp trtmp3b_decl00 trtmp3c trtmp3c_myenv0 trtmp3c_utils0 trtmp3c_dynexp trtmp3c_decl00 t3read0 t3read0_myenv0 t3read0_dynexp t3read0_decl00 f3perr0 f3perr0_dynexp f3perr0_decl00 xatsopt xatsopt_tmplib xatsopt_utils0"  # the FULL Makefile_xjsemit SRCDATS list (162 modules)
fn=0
for m in $FRONTEND; do
  f="$X/srcgen2/DATS/$m.dats"
  if [ ! -s "$EMIT/$m.go" ] || [ "$f" -nt "$EMIT/$m.go" ] || [ "$GOPATCHED" -nt "$EMIT/$m.go" ]; then
    node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
  fi
  awk 'BEGIN{started=0}
       /^type zzs_[a-z]* struct \{$/{lay=1}
       lay{if($0=="}"){lay=0}; next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed -E "s/goxtnm([0-9])/gof${fn}tnm\\1/g" \
    | sed "s/^func main() {\$/func zzmodinit_${MI}() {/" >> "$OUT/src/emitter_all.go"
  awk '/^type zzs_[a-z]* struct \{$/{lay=1} lay{print; if($0=="}"){lay=0}}' "$EMIT/$m.go" >> "$OUT/src/.layouts"
  echo "zzmodinit_${MI}" >> "$OUT/src/.modinits"
  MI=$((MI+1))
  printf "\n" >> "$OUT/src/emitter_all.go"
  fn=$((fn+1))
done

# 1c. the xats2cc D3->intrep0 lowering modules (the driver runs trxd3i0 +
#     tryd3i0).  With go1emit_package_pathq treating xats2cc as package
#     source, every intrep0 accessor/constructor reference is a stamped name
#     defined by intrep0.dats's own emission here.  xats2cc's intrep1* are
#     EXCLUDED -- xats2go's own srcgen2/DATS/intrep1.dats already owns the
#     emit/intrep1.go slot (same basename).  intrep0_utils0 is EXCLUDED too:
#     the prebuilt lib2xats2cc lowering CRASHES on it (d3pat_trxd3i0 cfail --
#     the same pre-existing defect the JS bundle works around); its exports
#     (i0pat_allq + the 6 i0varfst_*) are supplied as Go shims in zz_shims.go
#     below, mirroring runtime/jsshim/gen-i0varfst-shim.sh.
CCMODS="intrep0 intrep0_print0 trxd3i0 trxd3i0_decl00 trxd3i0_dynexp trxd3i0_myenv0 trxd3i0_print0 trxd3i0_statyp tryd3i0 tryd3i0_decl00 tryd3i0_dynexp tryd3i0_myenv0 xats2cc_tmplib"
cn=0
for m in $CCMODS; do
  f="$X/srcgen2/xats2go/xats2cc/srcgen1/DATS/$m.dats"
  if [ ! -s "$EMIT/$m.go" ] || [ "$f" -nt "$EMIT/$m.go" ] || [ "$GOPATCHED" -nt "$EMIT/$m.go" ]; then
    node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
  fi
  awk 'BEGIN{started=0}
       /^type zzs_[a-z]* struct \{$/{lay=1}
       lay{if($0=="}"){lay=0}; next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed -E "s/goxtnm([0-9])/goc${cn}tnm\\1/g" \
    | sed "s/^func main() {\$/func zzmodinit_${MI}() {/" >> "$OUT/src/emitter_all.go"
  awk '/^type zzs_[a-z]* struct \{$/{lay=1} lay{print; if($0=="}"){lay=0}}' "$EMIT/$m.go" >> "$OUT/src/.layouts"
  echo "zzmodinit_${MI}" >> "$OUT/src/.modinits"
  MI=$((MI+1))
  printf "\n" >> "$OUT/src/emitter_all.go"
  cn=$((cn+1))
done

# generated master init(): run every module's preserved top-level effects, in
# assembly order, before the driver's main (Go runs func init() after all var
# initializers, so IIFE-var globals like the keyword map are already built).
{
  printf '\nfunc init() {\n'
  while IFS= read -r nm; do printf '\t%s()\n' "$nm"; done < "$OUT/src/.modinits"
  printf '}\n'
} >> "$OUT/src/emitter_all.go"

# PER-LAYOUT CONSTRUCTOR STRUCTS: every module emits declarations for the
# layouts it touched, so the same struct arrives many times.  Emit the UNION
# once, deduplicated by type name (identical layouts SHARE a struct — that is
# what keeps ATS's representation casts free).  See
# docs/11-datatype-representation.md.
{
  printf '\n// ---- per-layout constructor structs (deduplicated) ----\n'
  awk '/^type (zzs_[a-z]*) struct \{$/{nm=$2; if(nm in seen){skip=1} else {seen[nm]=1; skip=0}}
       !skip{print}
       /^\}$/{skip=0}' "$OUT/src/.layouts"
} >> "$OUT/src/emitter_all.go"

printf '\nfunc main() { xatsgo.XATS2GO_flush_pending() }\n' >> "$OUT/src/emitter_all.go"
echo ">> assembled $n emitter + $fn frontend + $cn xats2cc modules -> $OUT/src/emitter_all.go ($(wc -l < "$OUT/src/emitter_all.go") lines)"

# 2. the CATS/GO prelude floor (typed XATS2GO_* leaves), $->_ mangled, exactly
#    as run-goarm.sh splices it for the rungs.
GO_CATS="xtop000 gint000 bool000 char000 gflt000 axrf000 unsfx00 strn000"
CATSPATHS=""; for c in $GO_CATS; do CATSPATHS="$CATSPATHS $X/prelude/DATS/CATS/GO/$c.cats"; done
IMPLINE=""
for p in fmt math reflect strconv strings; do
  if grep -qhE "\b$p\." $CATSPATHS 2>/dev/null; then IMPLINE="$IMPLINE \"$p\";"; fi
done
{
  echo 'package main'
  echo "import ($IMPLINE )"
  for c in $GO_CATS; do sed 's/\$/_/g' "$X/prelude/DATS/CATS/GO/$c.cats"; done
} > "$OUT/src/zz_floor.go"

# 2b. package-local shims.  (a) The emitter's own $extnam externs
#     (XATS2GO_gochar_esc / XATS2GO_chrfpr) — the Go ports of the JS bundle
#     shim (i0varfst-shim.js).  (b) STAMPED template shims: a Task-#8 worker
#     body may reference an UNRESOLVED inner template call as a stamped
#     package-local name (s2lab_get_itm_<N>); the template's body is the
#     one-liner S2LAB projection, so generate a def per referenced stamp.
{
  cat <<'GOEOF'
package main

import (
	"fmt"

	"xatsgo"
)

// Go char-literal escaping for the emitted source (JS shim XATS2GO_gochar_esc).
func XATS2GO_gochar_esc(c0 rune) string {
	c := int(c0)
	switch c {
	case 10:
		return "\\n"
	case 9:
		return "\\t"
	case 13:
		return "\\r"
	case 8:
		return "\\b"
	case 12:
		return "\\f"
	case 11:
		return "\\v"
	case 39:
		return "\\'"
	case 92:
		return "\\\\"
	}
	if c >= 32 && c != 127 {
		return string(rune(c))
	}
	if c <= 0xff {
		return fmt.Sprintf("\\x%02x", c)
	}
	if c <= 0xffff {
		return fmt.Sprintf("\\u%04x", c)
	}
	return fmt.Sprintf("\\U%08x", c)
}

// ATS-facing raw char output (filr, char) — routes to the runtime prim.
func XATS2GO_chrfpr(filr any, c0 rune) any {
	return xatsgo.Xats_XATS2GO_chrfpr(filr, c0)
}

// diagnostics-window channel brackets (see runtime + xats2go_goemit01.dats).
func XATS2GO_report_begin() any { return xatsgo.Xats_XATS2GO_report_begin() }
func XATS2GO_report_end() any   { return xatsgo.Xats_XATS2GO_report_end() }
GOEOF
  # stamped s2lab_get_itm shims: S2LAB(l0, x0) => x0 (Args[1])
  grep -ohE '\bs2lab_get_itm_[0-9]+' "$OUT/src/emitter_all.go" | sort -u | while read -r nm; do
    if ! grep -q "^func $nm(" "$OUT/src/emitter_all.go"; then
      printf '\nfunc %s(slab any) any { return xatsgo.Xats_as_con(slab).Args[1] }\n' "$nm"
    fi
  done

  # stamped mydict_search$opt shims: xlibext's mydict IS the jshmap (see the
  # runtime), so an unresolved inner-template reference delegates directly.
  grep -ohE '\bmydict_search_opt_[0-9]+' "$OUT/src/emitter_all.go" | sort -u | while read -r nm; do
    if ! grep -q "^func $nm(" "$OUT/src/emitter_all.go"; then
      printf '\nfunc %s(m any, k any) *xatsgo.XatsCon { return xatsgo.Xats_XATS2JS_jshmap_search_opt(m, k) }\n' "$nm"
    fi
  done

  # sort2 g_lte hook: the frontend's `#impltmp g_lte<sort2> = lte_sort2_sort2`
  # reaches the emitter UNRESOLVED (a prelude-cst dapp) and bridges to
  # xatsgo.Xats_g_lte; EVERY such site in the assembly compares sort2 values
  # (s2explst_stck / l2s2elst_stck / the trans12_decl00 sort filter), so
  # register the package's real stamped lte_sort2_sort2 as the runtime's
  # constructor-operand `<=` hook (see XatsGlteConHook in the runtime).
  LTES2=$(grep -ohE 'func lte_sort2_sort2_[0-9]+' "$OUT/src/emitter_all.go" | head -1 | sed 's/func //')
  if [ -n "$LTES2" ]; then
    cat <<GOEOF

func init() {
	xatsgo.XatsGlteConHook = func(a any, b any) any {
		return ${LTES2}(xatsgo.Xats_as_con(a), xatsgo.Xats_as_con(b))
	}
}
GOEOF
  fi

  # i0varfst funset shims (the Go port of runtime/jsshim/gen-i0varfst-shim.sh):
  # intrep0_utils0.dats cannot be lowered by the prebuilt lib2xats2cc, so the
  # 6 i0varfst_* helpers + i0pat_allq it implements are supplied here.  The
  # set is a []any SORTED ASCENDING by the var's stamp key, deduped -- the
  # SAME order the JS shim uses, so free-var traversal (and thus emitted
  # code) matches the oracle.  Stamped helper names are discovered from the
  # assembled package (robust to stamp shifts).
  AGG="$OUT/src/emitter_all.go $OUT/src/zz_driver.go"
  ref() { grep -ohE "$1"'_[0-9]+' $AGG 2>/dev/null | sort -u | head -1; }
  MKNIL=$(ref 'i0varfst_mknil'); MKLST=$(ref 'i0varfst_mklst')
  ADDVAR=$(ref 'i0varfst_addvar'); ADDLST=$(ref 'i0varfst_addlst')
  LISTIZE=$(ref 'i0varfst_listize'); STRMIZE=$(ref 'i0varfst_strmize')
  ALLQ=$(ref 'i0pat_allq')
  I0VAR_DVAR=$(ref 'i0var_dvar_get'); D2VAR_STMP=$(ref 'd2var_get_stmp')
  STMP_UINT=$(ref 'stamp_get_uint'); I0PAT_NODE=$(ref 'i0pat_node_get')
  if [ -n "$MKNIL" ] && [ -n "$I0VAR_DVAR" ] && [ -n "$D2VAR_STMP" ] && [ -n "$STMP_UINT" ]; then
    cat <<GOEOF

// i0varfst: functional set of i0var, keyed+ordered by stamp (see the JS shim).
func xats2goI0varfstKey(v any) int {
	return xatsgo.Xats_as_int(${STMP_UINT}(${D2VAR_STMP}(${I0VAR_DVAR}(v))))
}
func xats2goI0varfstIns(s []any, v any) []any {
	k := xats2goI0varfstKey(v)
	i := 0
	for i < len(s) && xats2goI0varfstKey(s[i]) < k {
		i++
	}
	if i < len(s) && xats2goI0varfstKey(s[i]) == k {
		return s // already present
	}
	out := make([]any, 0, len(s)+1)
	out = append(out, s[:i]...)
	out = append(out, v)
	out = append(out, s[i:]...)
	return out
}
func xats2goI0varfstFold(s []any, vs any) []any {
	for p := xatsgo.Xats_as_con(vs); p != nil && p.Tag == 1; p = xatsgo.Xats_as_con(p.Args[1]) {
		s = xats2goI0varfstIns(s, p.Args[0])
	}
	return s
}
func xats2goI0varfstConslist(s []any) *xatsgo.XatsCon {
	r := &xatsgo.XatsCon{Tag: 0}
	for i := len(s) - 1; i >= 0; i-- {
		r = &xatsgo.XatsCon{Tag: 1, Args: []any{s[i], r}}
	}
	return r
}
func ${MKNIL}() any            { return []any{} }
func ${ADDVAR}(s any, v any) any { return xats2goI0varfstIns(s.([]any), v) }
func ${MKLST}(vs any) any      { return xats2goI0varfstFold([]any{}, vs) }
func ${ADDLST}(s any, vs any) any { return xats2goI0varfstFold(s.([]any), vs) }
// listize/strmize both yield the ascending cons-list (the Go floor's streams
// are eager lists: strm_vt_listize0 is identity, list_make_lstrm asserts).
func ${LISTIZE}(s any) *xatsgo.XatsCon { return xats2goI0varfstConslist(s.([]any)) }
func ${STRMIZE}(s any) func() any       { return xatsgo.Xats_strm_of_items(s.([]any)) }
GOEOF
  fi
  if [ -n "$ALLQ" ] && [ -n "$I0PAT_NODE" ]; then
    cat <<GOEOF

// i0pat_allq (intrep0_utils0): var/any-only pattern?  Tags follow the
// i0pat_node declaration order in xats2cc/srcgen1/SATS/intrep0.sats:
// 0=any 1=var 2..6=literals 16=tup0(npf,ps) 17=tup1(k,npf,ps) 18=rcd2(k,npf,lips).
func ${ALLQ}(p any) bool {
	n := xatsgo.Xats_as_con(${I0PAT_NODE}(p))
	switch n.Tag {
	case 0, 1:
		return true
	case 16:
		return xats2goI0patAllqList(n.Args[1])
	case 17:
		return xats2goI0patAllqList(n.Args[2])
	case 18:
		return xats2goI0patAllqLips(n.Args[2])
	}
	return false
}
func xats2goI0patAllqList(ps any) bool {
	for p := xatsgo.Xats_as_con(ps); p != nil && p.Tag == 1; p = xatsgo.Xats_as_con(p.Args[1]) {
		if !${ALLQ}(p.Args[0]) {
			return false
		}
	}
	return true
}
func xats2goI0patAllqLips(lips any) bool {
	for p := xatsgo.Xats_as_con(lips); p != nil && p.Tag == 1; p = xatsgo.Xats_as_con(p.Args[1]) {
		lab := xatsgo.Xats_as_con(p.Args[0]) // I0LAB(l0, i0p)
		if !${ALLQ}(lab.Args[1]) {
			return false
		}
	}
	return true
}
GOEOF
  fi
} > "$OUT/src/zz_shims.go"

# 3. go module
printf 'module selfhostemit\n\ngo 1.26\n\nrequire xatsgo v0.0.0\nreplace xatsgo => %s\n' "$RUNTIME" > "$OUT/src/go.mod"
