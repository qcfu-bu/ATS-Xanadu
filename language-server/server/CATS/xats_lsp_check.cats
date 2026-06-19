////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//        WS-1a  LSP diagnostics checker  -  JS-glue companion        //.
//        (the ".cats" half of the FFI idiom; primer S10.1)           //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
// Every ATS3 `#extern fun NAME(...) = $extnam()` in xats_lsp_check.dats is
// implemented here by a same-named JS function. This file is cat-linked
// into the final app.js by build.sh, BEFORE the compiled driver, so the
// `require('node:fs')` const exists when the driver's top-level runs.
//
// Design (decided in WS-1a): the ATS side walks the typed AST and, at each
// `…errck` node, classifies it and calls LSPCHK_diag_push(...). All mutable
// state (the diagnostics accumulator), the dedup (Decision D6), the JSON
// serialization and the file write live HERE in JS — the ATS side stays a
// pure traversal + classification pass.
//
////////////////////////////////////////////////////////////////////////.
//
const LSPCHK_fs = require('node:fs');
//
////////////////////////////////////////////////////////////////////////.
// ---- argv access (scalar, like the WS-0a spike) -------------------- //
//
function LSPCHK_argv_count()      { return process.argv.length; }
function LSPCHK_argv_get(i0)      { return process.argv[i0]; }
//
////////////////////////////////////////////////////////////////////////.
// ---- string-buffer FILR --------------------------------------------- //
// A FILR (FILEref) in this runtime is any object with a .write(string)
// method (see srcgen1_xatslib_node.js: g_fprint does out.write(...)).
// We hand the compiler's own s2typ_fprint such a buffer so we can capture
// a type's printed form as a JS string for the type-mismatch message.
//
function LSPCHK_strbuf_new() {
  return { buf: "", write: function (s) { this.buf += s; } };
}
function LSPCHK_strbuf_get(fb) { return fb.buf; }
//
// int label / xtv stamp -> string (faithful s2typ printer helpers).
function TYPRINT_int2str(n)   { return String(n|0); }
function TYPRINT_stamp2str(s) { return String(s); }
//
////////////////////////////////////////////////////////////////////////.
// ---- diagnostics accumulator + dedup + JSON ------------------------- //
//
// One global accumulator (the checker is one-shot, one file per process).
let LSPCHK_diags   = [];
let LSPCHK_hovers  = [];
let LSPCHK_defs    = [];
let LSPCHK_symbols = [];   // WS-5 document symbols (outline)
let LSPCHK_inlays  = [];   // WS-5 inlay hints (inferred val types)
//
// Friendly-name map for the few internal type-constant head names that show
// up in type-mismatch messages, so "expected `gint_type`" reads as
// "expected `int`". Unknown names pass through unchanged (still informative).
// (A proper source-syntax type printer in WS-2 supersedes this heuristic.)
// Grounded in prelude/basics0.sats head names. Used ONLY for the leaf head-name
// renderer in type-MISMATCH messages — the faithful s2typ printer resolves int
// widths / surface names on the ATS side, so hover strings pass through unchanged.
const LSPCHK_TYPENAME = {
  "gint_type":        "int",
  "bool_type":        "bool",
  "char_type":        "char",
  "gflt_type":        "double",
  "xats_void_t":      "void",
  "string_i0_tx":     "string",
  "the_s2exp_strn0":  "string",
  "the_s2exp_sint0":  "int",
  "the_s2exp_uint0":  "uint",
  "the_s2exp_slint0": "lint",
  "the_s2exp_ulint0": "ulint",
  "the_s2exp_sllint0": "llint",
  "the_s2exp_ullint0": "ullint",
  "the_s2exp_sflt0":  "float",
  "the_s2exp_dflt0":  "double",
  "the_s2exp_list0":  "list",
  "the_s2exp_optn0":  "optn",
  "the_s2exp_lazy0":  "lazy",
  "the_s2exp_p1":     "ptr",
  "the_s2exp_p2":     "p2tr",
  "the_s2exp_bool0":  "bool",
  "the_s2exp_char0":  "char",
  "the_s2exp_void":   "void",
  "strn":             "string",
  // per-width integer rep tags (basics0.sats:589-606)
  "xats_sint_t":      "int",
  "xats_uint_t":      "uint",
  "xats_slint_t":     "lint",
  "xats_ulint_t":     "ulint",
  "xats_ssize_t":     "ssize",
  "xats_usize_t":     "usize",
  "xats_sllint_t":    "llint",
  "xats_ullint_t":    "ullint",
  "xats_strn_t":      "string",
  "xats_bool_t":      "bool",
  "xats_char_t":      "char",
  "xats_dflt_t":      "double",
  // pointer / container heads
  "p1tr_tbox":        "ptr",
  "p2tr_tbox":        "p2tr",
  "list_t0_i0_tx":    "list",
  "list_vt_i0_vx":    "list_vt",
  "optn_t0_i0_tx":    "optn",
  "optn_vt_i0_vx":    "optn_vt",
  "lazy_t0_tx":       "lazy",
  "lazy_vt_vx":       "lazy_vt"
};
function LSPCHK_friendly(msg) {
  // replace any `name` token that has a friendly alias
  return msg.replace(/`([A-Za-z_][A-Za-z0-9_$]*)`/g, function (m, nm) {
    return LSPCHK_TYPENAME.hasOwnProperty(nm) ? ("`" + LSPCHK_TYPENAME[nm] + "`") : m;
  });
}
//
// Push one raw diagnostic. Coordinates are the INTERNAL 0-based values the
// ATS side read via the locinfo accessors (line=nrow, char=ncol[byte]).
// `code`/`message` are authored ATS-side per constructor.
function LSPCHK_diag_push(l0, c0, l1, c1, code, message) {
  LSPCHK_diags.push({
    l0: l0|0, c0: c0|0, l1: l1|0, c1: c1|0,
    code: String(code), message: LSPCHK_friendly(String(message))
  });
}
//
////////////////////////////////////////////////////////////////////////.
// ---- path -> file:// URI mapping (go-to-def; primer §5/§8) ---------- //
//
// The ATS side hands us the entity's def-site fnm1 (the normalized path
// inside its LCSRCfpath source). For the file under check this is the
// (absolute) path the server passed; for prelude/staloaded entities it's the
// resolved prelude path. We turn it into a file:// URI:
//   * absolute (starts with "/")  -> "file://" + encoded path
//   * relative                    -> resolve against cwd, then encode
// (POSIX/macOS only for v1; Windows drive-letter paths are a hardening task.)
function LSPCHK_path2uri(p) {
  let s = String(p || "");
  if (s === "") return "";
  // already a URI? pass through.
  if (s.startsWith("file://")) return s;
  // resolve relative paths against the process cwd so we always emit absolute.
  if (!s.startsWith("/")) {
    try { s = require('node:path').resolve(s); }
    catch (e) { /* fall through with the raw string */ }
  }
  // percent-encode each path segment but keep the separators.
  const enc = s.split('/').map(function (seg) {
    return encodeURIComponent(seg);
  }).join('/');
  return "file://" + enc;
}
//
////////////////////////////////////////////////////////////////////////.
// ---- hover accumulator (LSP goal #2) -------------------------------- //
//
// One entry per typed d3exp/d3pat node with a real location. The ATS side
// already pretty-printed the type to source syntax; we friendly-map any
// internal head names that slipped through (e.g. gint_type -> int) and store
// the 0-based range + kind. Dedup of exact (range,type) duplicates happens at
// serialization time (the server picks the innermost on hover).
function LSPCHK_hover_push(l0, c0, l1, c1, typ, kind) {
  // The ATS-side faithful printer already emits resolved surface syntax; pass it
  // through verbatim (the head-name remap would only corrupt it).
  let t = String(typ);
  if (t === "") return;
  LSPCHK_hovers.push({
    l0: l0|0, c0: c0|0, l1: l1|0, c1: c1|0,
    type: t, kind: String(kind)
  });
}
//
// friendly-map a whole type string: replace any internal head-name token that
// has an alias. (Reuses the LSPCHK_TYPENAME table used for diagnostics.)
function LSPCHK_typestr(s) {
  return s.replace(/[A-Za-z_][A-Za-z0-9_$]*/g, function (nm) {
    return LSPCHK_TYPENAME.hasOwnProperty(nm) ? LSPCHK_TYPENAME[nm] : nm;
  });
}
//
////////////////////////////////////////////////////////////////////////.
// ---- definition accumulator (LSP goal #3) --------------------------- //
//
// One entry per resolved use site (D3Evar/D3Ecst/D3Econ). The ATS side gives
// us the use range, the entity's binding-site path+range, the entity kind,
// and optionally the type-constant's declaration path+range (type-definition).
function LSPCHK_def_push(ul0, uc0, ul1, uc1,
                        defpath,
                        dl0, dc0, dl1, dc1,
                        entity, hastdef, tdpath,
                        tl0, tc0, tl1, tc1) {
  const defUri = LSPCHK_path2uri(defpath);
  if (defUri === "") return;            // no real def file: skip (primer §8)
  const d = {
    ul0: ul0|0, uc0: uc0|0, ul1: ul1|0, uc1: uc1|0,
    defUri: defUri,
    dl0: dl0|0, dc0: dc0|0, dl1: dl1|0, dc1: dc1|0,
    entity: String(entity)
  };
  if ((hastdef|0) === 1) {
    const tdUri = LSPCHK_path2uri(tdpath);
    if (tdUri !== "") {
      d.typeDefUri = tdUri;
      d.tl0 = tl0|0; d.tc0 = tc0|0; d.tl1 = tl1|0; d.tc1 = tc1|0;
    }
  }
  LSPCHK_defs.push(d);
}
//
////////////////////////////////////////////////////////////////////////.
// ---- WS-5 document symbols + inlay hints ---------------------------- //
//
// One symbol per top-level declaration name: 0-based name range + SymbolKind +
// container ("" for top-level; non-empty would nest it as a child).
function LSPCHK_symbol_push(l0, c0, l1, c1, name, kind, container) {
  if ((l0|0) < 0 || (c0|0) < 0) return;
  const nm = String(name);
  if (nm === "") return;
  LSPCHK_symbols.push({
    l0: l0|0, c0: c0|0, l1: l1|0, c1: c1|0,
    name: nm, kind: kind|0, container: String(container || "")
  });
}
// One inlay per inferred val-binding: position (end of the bound name) + label
// (": <type>") + InlayHintKind (1 = Type).
function LSPCHK_inlay_push(line, col, label, kind) {
  if ((line|0) < 0 || (col|0) < 0) return;
  const lbl = String(label);
  if (lbl === "") return;
  LSPCHK_inlays.push({ line: line|0, char: col|0, label: lbl, kind: kind|0 });
}
function LSPCHK_dedup_symbols(ss) {
  const seen = new Set(); const out = [];
  for (const s of ss) {
    const key = s.l0+":"+s.c0+":"+s.l1+":"+s.c1+":"+s.kind+":"+s.name+":"+s.container;
    if (seen.has(key)) continue;
    seen.add(key); out.push(s);
  }
  return out.sort((a, b) => (a.l0 - b.l0) || (a.c0 - b.c0));
}
function LSPCHK_dedup_inlays(hs) {
  const seen = new Set(); const out = [];
  for (const h of hs) {
    const key = h.line+":"+h.char+":"+h.label+":"+h.kind;
    if (seen.has(key)) continue;
    seen.add(key); out.push(h);
  }
  return out.sort((a, b) => (a.line - b.line) || (a.char - b.char));
}
//
// Decision D6 dedup: the same root error surfaces multiple times — as an
// inner expr/pat error AND an enclosing decl wrapper (D?Cerrck), and again
// across levels L2/L3. We keep the INNERMOST (smallest-range) node, and drop
// the redundant enclosing wrappers. Two collapses:
//   (a) collapse by BEGIN position: among diagnostics sharing (l0,c0), keep
//       the one with the smallest range (smallest end), preferring a more
//       specific code over "unknown"/"decl-error" on a tie.
//   (b) drop CONTAINERS: a diagnostic whose range strictly contains another
//       diagnostic's range is an outer wrapper (e.g. a `decl-error` spanning
//       the whole `val …` that wraps a `type-mismatch` on the rhs literal) —
//       drop it in favour of the inner, more precise one.
function LSPCHK_posLE(la, ca, lb, cb) {        // (la,ca) <= (lb,cb) ?
  return (la < lb) || (la === lb && ca <= cb);
}
function LSPCHK_rank(code) {                    // higher = more specific/kept
  switch (code) {
    case "type-mismatch":        return 5;
    case "unbound-identifier":   return 5;
    case "unresolved-template":  return 4;
    case "pattern-error":        return 3;
    case "unknown":              return 2;
    case "decl-error":           return 1;     // outer wrapper, least specific
    default:                     return 2;
  }
}
function LSPCHK_dedup(diags) {
  // drop dummy/negative locations first
  let xs = diags.filter(function (d) { return d.l0 >= 0 && d.c0 >= 0; });
  // (a) collapse by begin position
  const best = new Map();
  for (const d of xs) {
    const key = d.l0 + ":" + d.c0;
    const cur = best.get(key);
    if (cur === undefined) { best.set(key, d); continue; }
    const dEnd = d.l1   * 1000000 + d.c1;
    const cEnd = cur.l1 * 1000000 + cur.c1;
    if (dEnd < cEnd) best.set(key, d);
    else if (dEnd === cEnd && LSPCHK_rank(d.code) > LSPCHK_rank(cur.code))
      best.set(key, d);
  }
  xs = Array.from(best.values());
  // helper: do ranges A and B overlap at all?
  function overlap(a, b) {
    return LSPCHK_posLE(a.l0, a.c0, b.l1, b.c1) &&
           LSPCHK_posLE(b.l0, b.c0, a.l1, a.c1);
  }
  // (b) drop redundant wrappers. Keep d UNLESS:
  //   - d strictly CONTAINS another diagnostic e (d is an outer wrapper), or
  //   - d is a low-value `decl-error` that OVERLAPS a more specific
  //     diagnostic (the precise expr/pat error already covers the spot).
  const kept = xs.filter(function (d) {
    for (const e of xs) {
      if (e === d) continue;
      const inside =
        LSPCHK_posLE(d.l0, d.c0, e.l0, e.c0) &&
        LSPCHK_posLE(e.l1, e.c1, d.l1, d.c1);
      const strictly = inside &&
        !(e.l0 === d.l0 && e.c0 === d.c0 && e.l1 === d.l1 && e.c1 === d.c1);
      if (strictly) return false;   // d contains e -> d is an outer wrapper
      if (d.code === "decl-error" && e.code !== "decl-error" &&
          overlap(d, e) && LSPCHK_rank(e.code) > LSPCHK_rank(d.code))
        return false;               // a precise diagnostic already covers it
    }
    return true;
  });
  return kept.sort((a, b) =>
    (a.l0 - b.l0) || (a.c0 - b.c0) || (a.l1 - b.l1) || (a.c1 - b.c1));
}
//
function LSPCHK_jsrange(l0, c0, l1, c1) {
  return { start: { line: l0, character: c0 },
           end:   { line: l1, character: c1 } };
}
//
// Dedup hovers by exact (range,type,kind). The traversal can revisit the same
// node via multiple wrappers (D3Et2pck/D3Eannot/…), producing identical hover
// rows; collapse them. We keep one per (l0,c0,l1,c1,type,kind) key. The list
// stays large (one per subexpression) by design — the server picks the
// innermost (smallest) range covering the cursor.
function LSPCHK_hover_dedup(hs) {
  const seen = new Set();
  const out = [];
  for (const h of hs) {
    if (h.l0 < 0 || h.c0 < 0) continue;          // dummy/negative: skip
    if (h.l1 < h.l0 || (h.l1 === h.l0 && h.c1 < h.c0)) continue; // inverted
    const key = h.l0+":"+h.c0+":"+h.l1+":"+h.c1+":"+h.kind+":"+h.type;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(h);
  }
  return out.sort((a, b) =>
    (a.l0 - b.l0) || (a.c0 - b.c0) ||
    // wider ranges first so a stable read order is outer..inner
    (b.l1 - a.l1) || (b.c1 - a.c1));
}
//
// Dedup definitions by (useRange, defUri, defRange, entity).
function LSPCHK_def_dedup(ds) {
  const seen = new Set();
  const out = [];
  for (const d of ds) {
    if (d.ul0 < 0 || d.uc0 < 0) continue;
    if (d.dl0 < 0 || d.dc0 < 0) continue;
    const key = d.ul0+":"+d.uc0+":"+d.ul1+":"+d.uc1+":"+
                d.defUri+":"+d.dl0+":"+d.dc0+":"+d.dl1+":"+d.dc1+":"+d.entity;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(d);
  }
  return out.sort((a, b) =>
    (a.ul0 - b.ul0) || (a.uc0 - b.uc0) || (a.ul1 - b.ul1) || (a.uc1 - b.uc1));
}
//
// Serialize the §4 bundle and write it to jsonout. Returns nothing.
function LSPCHK_json_finish(uri, nerror, jsonout) {
  const deduped = LSPCHK_dedup(LSPCHK_diags);
  const diagnostics = deduped.map(function (d) {
    return {
      range: LSPCHK_jsrange(d.l0, d.c0, d.l1, d.c1),
      severity: 1,                 // Decision D7: v1 always Error
      code: d.code,
      message: d.message,
      source: "ats3"
    };
  });
  const hovers = LSPCHK_hover_dedup(LSPCHK_hovers).map(function (h) {
    return {
      range: LSPCHK_jsrange(h.l0, h.c0, h.l1, h.c1),
      type: h.type,
      kind: h.kind
    };
  });
  const definitions = LSPCHK_def_dedup(LSPCHK_defs).map(function (d) {
    const out = {
      useRange: LSPCHK_jsrange(d.ul0, d.uc0, d.ul1, d.uc1),
      defUri:   d.defUri,
      defRange: LSPCHK_jsrange(d.dl0, d.dc0, d.dl1, d.dc1),
      entity:   d.entity
    };
    if (d.typeDefUri) {
      out.typeDefUri   = d.typeDefUri;
      out.typeDefRange = LSPCHK_jsrange(d.tl0, d.tc0, d.tl1, d.tc1);
    }
    return out;
  });
  const symbols = LSPCHK_dedup_symbols(LSPCHK_symbols).map(function (s) {
    return {
      name: s.name,
      kind: s.kind,
      range:          LSPCHK_jsrange(s.l0, s.c0, s.l1, s.c1),
      selectionRange: LSPCHK_jsrange(s.l0, s.c0, s.l1, s.c1),
      container: s.container
    };
  });
  const inlays = LSPCHK_dedup_inlays(LSPCHK_inlays).map(function (h) {
    return {
      position: { line: h.line, character: h.char },
      label: h.label,
      kind: h.kind
    };
  });
  const bundle = {
    schema: 1,
    uri: String(uri),
    ok: true,
    nerror: nerror|0,
    diagnostics: diagnostics,
    hovers: hovers,
    definitions: definitions,
    symbols: symbols,
    inlays: inlays
  };
  try {
    LSPCHK_fs.writeFileSync(jsonout, JSON.stringify(bundle, null, 2));
  } catch (e) {
    // last-resort: emit an ok:false bundle so the server can detect crash
    try {
      LSPCHK_fs.writeFileSync(jsonout, JSON.stringify(
        { schema: 1, uri: String(uri), ok: false, nerror: 0,
          diagnostics: [], hovers: [], definitions: [], symbols: [], inlays: [],
          error: String(e) }, null, 2));
    } catch (e2) { /* give up */ }
  }
  return;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [language-server/server/CATS/xats_lsp_check.cats]
////////////////////////////////////////////////////////////////////////.
