#!/usr/bin/env bash
# assemble.sh — emit all emitter modules to Go and assemble them into one
# package, to drive a multi-module `go build` toward self-hosting.
set -uo pipefail
X=/home/user/ATS-Xanadu
export XATSHOME=$X
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
printf 'package main\n\nimport "xatsgo"\n\nvar _ = xatsgo.XATSNIL\n\n' > "$OUT/src/emitter_all.go"
n=0
for f in "$X"/srcgen2/xats2go/srcgen2/DATS/*.dats; do
  m="$(basename "$f" .dats)"
  if [ ! -s "$EMIT/$m.go" ] || [ "$f" -nt "$EMIT/$m.go" ] || [ "$GOPATCHED" -nt "$EMIT/$m.go" ]; then
    node --stack-size=8801 "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
  fi
  # strip header (package/import/keepalive — up to first `func `) and the final main.
  awk 'BEGIN{started=0}
       /^func main\(\) \{/{inmain=1}
       inmain{next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed "s/goxtnm/go${n}tnm/g" >> "$OUT/src/emitter_all.go"
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
    node --stack-size=8801 "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
  fi
  awk 'BEGIN{started=0}
       /^func main\(\) \{/{inmain=1}
       inmain{next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed "s/goxtnm/gof${fn}tnm/g" >> "$OUT/src/emitter_all.go"
  printf "\n" >> "$OUT/src/emitter_all.go"
  fn=$((fn+1))
done

# 1c. the xats2cc D3->intrep0 lowering modules (the driver runs trxd3i0 +
#     tryd3i0).  With go1emit_package_pathq treating xats2cc as package
#     source, every intrep0 accessor/constructor reference is a stamped name
#     defined by intrep0.dats's own emission here.  xats2cc's intrep1* are
#     EXCLUDED -- xats2go's own srcgen2/DATS/intrep1.dats already owns the
#     emit/intrep1.go slot (same basename).
CCMODS="intrep0 intrep0_print0 intrep0_utils0 trxd3i0 trxd3i0_decl00 trxd3i0_dynexp trxd3i0_myenv0 trxd3i0_print0 trxd3i0_statyp tryd3i0 tryd3i0_decl00 tryd3i0_dynexp tryd3i0_myenv0 xats2cc_tmplib"
cn=0
for m in $CCMODS; do
  f="$X/srcgen2/xats2go/xats2cc/srcgen1/DATS/$m.dats"
  if [ ! -s "$EMIT/$m.go" ] || [ "$f" -nt "$EMIT/$m.go" ] || [ "$GOPATCHED" -nt "$EMIT/$m.go" ]; then
    node --stack-size=8801 "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
    awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
  fi
  awk 'BEGIN{started=0}
       /^func main\(\) \{/{inmain=1}
       inmain{next}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed "s/goxtnm/goc${cn}tnm/g" >> "$OUT/src/emitter_all.go"
  printf "\n" >> "$OUT/src/emitter_all.go"
  cn=$((cn+1))
done

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
GOEOF
  # stamped s2lab_get_itm shims: S2LAB(l0, x0) => x0 (Args[1])
  grep -ohE '\bs2lab_get_itm_[0-9]+' "$OUT/src/emitter_all.go" | sort -u | while read -r nm; do
    if ! grep -q "^func $nm(" "$OUT/src/emitter_all.go"; then
      printf '\nfunc %s(slab any) any { return xatsgo.Xats_as_con(slab).Args[1] }\n' "$nm"
    fi
  done
} > "$OUT/src/zz_shims.go"

# 3. go module
printf 'module selfhostemit\n\ngo 1.26\n\nrequire xatsgo v0.0.0\nreplace xatsgo => %s\n' "$RUNTIME" > "$OUT/src/go.mod"
