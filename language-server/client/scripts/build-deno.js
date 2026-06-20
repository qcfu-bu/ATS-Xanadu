#!/usr/bin/env node
/*
 * Package-time helper: compile the resident LSP server into a SELF-CONTAINED
 * native binary via `deno compile`.
 *
 * Why Deno: the resident server bundles the deeply-recursive ATS3 compiler and
 * overflows V8's default stack while loading the prelude. Node fixes this with
 * `--stack-size=8801`; Deno (also V8-based) takes the same knob via
 * `--v8-flags`, and `deno compile` bakes it into the binary. Bun (JSC) cannot —
 * its stack is fixed. So Deno is our single-binary path.
 *
 * The produced binary:
 *   - embeds V8 + the deno runtime + the server JS + its vscode-languageserver
 *     deps (resolved from the resident server's sibling node_modules), so it
 *     needs NO node/deno/node_modules at runtime;
 *   - bakes in `--allow-all` and `--v8-flags=--stack-size=8801`, so it is
 *     launched simply as `xats-lsp-deno --stdio`;
 *   - still reads the prelude from XATSHOME at runtime (data, not code), exactly
 *     like the node path.
 *
 * Output: client/server-dist/xats-lsp-deno  (.exe on Windows)
 *
 * Gotchas baked in here (discovered empirically):
 *   - the server bundle is CommonJS (uses require + has duplicate `function`
 *     decls); Deno loads `.js` as ESM (strict) and rejects it, so we compile a
 *     `.cjs` copy;
 *   - it is not TypeScript, so `--no-check` is required (else Deno tries to
 *     type-check against @types/node and errors).
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const clientDir = path.resolve(__dirname, "..");
const lsRoot = path.resolve(clientDir, "..");
const serverArtifact = path.join(
  lsRoot, "server", "resident", "BUILD", "xats-lsp-resident.opt1.js",
);
const buildDir = path.dirname(serverArtifact); // sibling node_modules resolves from here
const cjsCopy = path.join(buildDir, "xats-lsp-resident.deno.cjs");
const destDir = path.join(clientDir, "server-dist");
const exeName = process.platform === "win32" ? "xats-lsp-deno.exe" : "xats-lsp-deno";
const destBin = path.join(destDir, exeName);

const STACK = "8801";

function fail(msg) {
  console.error(`[build-deno] ERROR: ${msg}`);
  process.exit(1);
}

function main() {
  // deno present?
  const ver = spawnSync("deno", ["--version"], { encoding: "utf8" });
  if (ver.status !== 0) {
    fail(
      "deno not found on PATH. Install it (e.g. `brew install deno` or " +
        "`curl -fsSL https://deno.land/install.sh | sh`) and retry.",
    );
  }
  console.log(`[build-deno] using ${ver.stdout.split("\n")[0]}`);

  if (!fs.existsSync(serverArtifact)) {
    fail(
      `resident server not found at ${serverArtifact}. ` +
        `Build it first (cd ../server/resident && bash build.sh).`,
    );
  }

  // Fresh server-dist: the binary is fully self-contained, so this is the ONLY
  // thing the extension ships at runtime (no node server, no node_modules).
  fs.rmSync(destDir, { recursive: true, force: true });
  fs.mkdirSync(destDir, { recursive: true });
  // CommonJS copy next to the server so `require("vscode-languageserver/...")`
  // resolves against resident/node_modules during compile.
  fs.copyFileSync(serverArtifact, cjsCopy);

  try {
    console.log(`[build-deno] compiling -> ${destBin} (this can take a minute)`);
    const r = spawnSync(
      "deno",
      [
        "compile",
        "--allow-all",
        "--no-check",
        `--v8-flags=--stack-size=${STACK}`,
        "--output", destBin,
        cjsCopy,
      ],
      { stdio: "inherit" },
    );
    if (r.status !== 0) fail(`deno compile failed (exit ${r.status}).`);
  } finally {
    fs.rmSync(cjsCopy, { force: true });
  }

  if (!fs.existsSync(destBin)) fail("deno compile reported success but no binary was produced.");
  fs.chmodSync(destBin, 0o755);
  const mb = (fs.statSync(destBin).size / (1024 * 1024)).toFixed(1);
  console.log(`[build-deno] done -> server-dist/${exeName} (${mb} MB)`);
  console.log(`[build-deno] launch: ${destBin} --stdio   (stack flag + perms baked in)`);
}

main();
