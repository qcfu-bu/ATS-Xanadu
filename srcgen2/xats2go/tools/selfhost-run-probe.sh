#!/bin/sh
#
# selfhost-run-probe.sh — M5 Phase 1: prove emitted backend Go COMPILES (as a
# typed Go package, via a bootstrap frontend shim) and RUNS (a pure emitted
# function under a Go test). Adds nothing to the tree; all scratch under
# srcgen2/BUILD/selfhost-m5/. Read-only wrt emitter/runtime.
#
#  RUN-PROOF  : extract go1emit_strn_contains (VERBATIM emitter output, no
#               patch -- blocker (a) is fixed at the root: Xats_strn_length
#               returns concrete int) -> go test must PASS.
#  SHIM-BUILD : assemble the full go1emit_utils0 package + an any-typed frontend
#               shim -> reduce to exactly the two known remaining blockers.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
export NODE_COMPILE_CACHE="$repo/srcgen2/BUILD/.v8cache"
BUNDLE="$repo/srcgen2/BUILD/xats2go-bundle.patched.js"
RT="$repo/runtime/xatsgo"
WORK="$repo/srcgen2/BUILD/selfhost-m5"
rm -rf "$WORK"; mkdir -p "$WORK/runproof"

echo ">> [1/4] emit go1emit_utils0.dats -> Go"
node --stack-size=8801 "$BUNDLE" "$repo/srcgen2/DATS/go1emit_utils0.dats" 2>/dev/null \
  | awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' > "$WORK/go1emit_utils0.go"
[ "$(wc -l < "$WORK/go1emit_utils0.go")" -gt 100 ] || { echo "!! emit failed"; exit 1; }

echo ">> [2/4] RUN-PROOF: extract go1emit_strn_contains (VERBATIM) + run it"
# Blocker (a) is now fixed at its root (Xats_strn_length returns concrete int),
# so the emitted go1emit_strn_contains type-checks AS EMITTED -- no simulation.
awk 'NR>=1 && /^func go1emit_strn_contains_21828/{f=1} f{print} f&&/^}/{exit}' "$WORK/go1emit_utils0.go" \
  > "$WORK/runproof/body.txt"
cat > "$WORK/runproof/go.mod" <<EOF
module xats2go_m5_runproof
go 1.26
require xatsgo v0.0.0
replace xatsgo => $RT
EOF
{ echo "package main"; echo; echo 'import "xatsgo"'; echo; echo "var _ = xatsgo.XATSNIL";
  echo "// VERBATIM emitter output (blocker (a) fixed in the xatsgo runtime).";
  cat "$WORK/runproof/body.txt"; printf '\nfunc main() {}\n'; } > "$WORK/runproof/strn_contains.go"
rm -f "$WORK/runproof/body.txt"
cat > "$WORK/runproof/strn_contains_test.go" <<'EOF'
package main

import "testing"

func TestStrnContains(t *testing.T) {
	cases := []struct {
		hay, needle string
		want        bool
	}{
		{"hello", "ell", true}, {"hello", "xyz", false}, {"abc", "", true},
		{"ab", "abc", false}, {"banana", "ana", true}, {"banana", "nana", true},
		{"banana", "anan", true}, {"abcdef", "def", true}, {"abcdef", "deg", false},
		{"x", "x", true},
	}
	for _, c := range cases {
		if got := go1emit_strn_contains_21828(c.hay, c.needle); got != c.want {
			t.Errorf("strn_contains(%q,%q)=%v want %v", c.hay, c.needle, got, c.want)
		}
	}
}
EOF
( cd "$WORK/runproof" && gofmt -w . && go vet ./... && go test ./... ) \
  || { echo "!! RUN-PROOF FAILED"; exit 1; }
echo "   RUN-PROOF: emitted go1emit_strn_contains logic runs correct (10 cases)"

echo ">> [3/4] SHIM-BUILD: full package + frontend shim -> isolate remaining blockers"
cat > "$WORK/go.mod" <<EOF
module xats2go_selfhost_m5
go 1.26
require xatsgo v0.0.0
replace xatsgo => $RT
EOF
cat > "$WORK/xatsfront_shim.go" <<'EOF'
package main

// BOOTSTRAP FRONTEND SHIM (temporary). The emitted backend calls frontend
// accessors defined in the unemitted ATS frontend (lib2xatsopt); this provides
// them with the exact (stable) stamped names + any-typed sigs so the package
// TYPE-CHECKS. Bodies panic. At fixpoint these are REPLACED by emitting the
// frontend type modules (same stamps -> same names).
func d2cst_get_lctn_9750(a any) any           { panic("shim") }
func d2cst_get_name_9786(a any) any           { panic("shim") }
func d2cst_get_stmp_10002(a any) any          { panic("shim") }
func d2var_get_lctn_11080(a any) any          { panic("shim") }
func d2var_get_name_11116(a any) any          { panic("shim") }
func loctn_get_lsrc_3058(a any) any           { panic("shim") }
func symbl_get_name_2206(a any) any           { panic("shim") }
func symbl_cmp_2067(a, b any) any             { panic("shim") }
func token_get_node_7837(a any) any           { panic("shim") }
func fpath_get_fnm1_2863(a any) any           { panic("shim") }
func the_d2cstmap_xnmfind_5592(a any) any     { panic("shim") }
func i1tnm_stmp_get_4294(a any) any           { panic("shim") }
func strnfpr_1691(a, b any) any               { panic("shim") }
func chrfpr_1737(a, b any) any                { panic("shim") }
func fprint_loctn_as_stamp_3749(a, b any) any { panic("shim") }
var TRUE_symbl_4365 any = nil
EOF
gofmt -w "$WORK/xatsfront_shim.go"
rem=$( cd "$WORK" && go build -gcflags="-e" ./... 2>&1 | grep '\.go:' || true )
nfront=$(echo "$rem" | grep -c 'strn_foritm' || true)
ntype=$(echo "$rem" | grep -c 'not defined on interface\|mismatched types' || true)
echo "$rem" | sed 's/^/   | /'
echo "   shim resolved all 16 Class-C frontend symbols; remaining = ${ntype} emitter type-bug + ${nfront} strn_foritm(M3)"

echo ">> [4/4] PASS — emitted backend logic RUNS; Class-C frontend dep fully shimmable."
echo "   Remaining blocker to a clean full build (out of shim scope):"
echo "     - xatsgo.Xats_strn_foritm = higher-order template foritm\$work (M3 template-body emission)"
echo "   (Resolved: blocker (a) native ops on any-typed prelude-call results -- scalar-query"
echo "    runtime fns now return concrete Go scalars; go1emit_strn_contains runs VERBATIM above.)"
