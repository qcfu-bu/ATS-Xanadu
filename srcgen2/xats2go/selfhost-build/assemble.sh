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
  node --stack-size=8801 "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
  awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
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
FRONTEND="xstamp0 xsymbol statyp2 statyp2_inits0 staexp2 staexp2_inits0 dynexp2 lexing0_token0 locinfo xbasics staexp2_utils1 xstamp0_tmpmap xglobal xatsopt_tmplib locinfo_print0 xsymmap_stkmap xsymmap_topmap xsymbol_inits0 xsymbol_mymap0 statyp2_utils1 dynexp2_utils0 filpath_fpath0"
fn=0
for m in $FRONTEND; do
  f="$X/srcgen2/DATS/$m.dats"
  node --stack-size=8801 "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
  awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
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

printf '\nfunc main() { xatsgo.XATS2GO_flush_pending() }\n' >> "$OUT/src/emitter_all.go"
echo ">> assembled $n emitter + $fn frontend modules -> $OUT/src/emitter_all.go ($(wc -l < "$OUT/src/emitter_all.go") lines)"

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
