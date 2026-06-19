#!/usr/bin/env node
/*
 * Package-time helper: copy the resident LSP server artifact AND its runtime
 * node_modules into the extension so an installed `.vsix` is self-contained.
 *
 * The resident server (`xats-lsp-resident.opt1.js`) `require()`s
 * `vscode-languageserver/node` and `vscode-languageserver-textdocument` from a
 * SIBLING `node_modules` directory. So we copy:
 *
 *   <repo>/language-server/server/resident/BUILD/xats-lsp-resident.opt1.js
 *     ->  client/server-dist/xats-lsp-resident.opt1.js
 *
 *   <repo>/language-server/server/resident/node_modules/<runtime deps>
 *     ->  client/server-dist/node_modules/<runtime deps>
 *
 * At runtime the installed extension launches
 * `<extensionPath>/server-dist/xats-lsp-resident.opt1.js`, and node resolves
 * its requires against `<extensionPath>/server-dist/node_modules` (resolved
 * by `resolveServerModule` in src/extension.ts, which prefers server-dist).
 *
 * This runs at PACKAGE time (npm run package), so it always snapshots the
 * CURRENT server bytes — fine even while the resident server is being rebuilt
 * in parallel; just re-run `npm run package` to pick up fresh bytes.
 *
 * Idempotent: clears server-dist first.
 */
"use strict";

const fs = require("fs");
const path = require("path");

const clientDir = path.resolve(__dirname, "..");
// client -> language-server (the resident server lives under language-server/server).
const lsRoot = path.resolve(clientDir, "..");

const serverArtifact = path.join(
  lsRoot,
  "server",
  "resident",
  "BUILD",
  "xats-lsp-resident.opt1.js",
);
// `server/resident/node_modules` is a symlink to `../lsp-server/node_modules`;
// realpath resolves it so we copy the actual files (not a dangling symlink).
const serverNodeModulesLink = path.join(
  lsRoot,
  "server",
  "resident",
  "node_modules",
);

const destDir = path.join(clientDir, "server-dist");
const destArtifact = path.join(destDir, "xats-lsp-resident.opt1.js");
const destNodeModules = path.join(destDir, "node_modules");

// The runtime deps the server actually requires (flat tree). We copy exactly
// these to keep the payload tight and avoid dev cruft (.bin, lockfiles).
const RUNTIME_DEPS = [
  "vscode-languageserver",
  "vscode-languageserver-textdocument",
  "vscode-languageserver-protocol",
  "vscode-languageserver-types",
  "vscode-jsonrpc",
];

function fail(msg) {
  console.error(`[copy-server] ERROR: ${msg}`);
  process.exit(1);
}

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dst, entry.name);
    if (entry.isDirectory()) {
      copyDir(s, d);
    } else if (entry.isSymbolicLink()) {
      // Dereference symlinks into real files so the packaged copy stands alone.
      const real = fs.realpathSync(s);
      if (fs.statSync(real).isDirectory()) {
        copyDir(real, d);
      } else {
        fs.copyFileSync(real, d);
      }
    } else {
      fs.copyFileSync(s, d);
    }
  }
}

function main() {
  if (!fs.existsSync(serverArtifact)) {
    fail(
      `resident server artifact not found at ${serverArtifact}. ` +
        `Build it first (cd ../server/resident && bash build.sh).`,
    );
  }
  if (!fs.existsSync(serverNodeModulesLink)) {
    fail(
      `server node_modules not found at ${serverNodeModulesLink}. ` +
        `Install the server runtime deps first (vscode-languageserver etc.).`,
    );
  }
  // Resolve the (possibly symlinked) node_modules to its real directory.
  const nodeModulesReal = fs.realpathSync(serverNodeModulesLink);

  // Fresh start.
  fs.rmSync(destDir, { recursive: true, force: true });
  fs.mkdirSync(destDir, { recursive: true });

  // 1) the server .js
  fs.copyFileSync(serverArtifact, destArtifact);
  console.log(
    `[copy-server] copied server artifact (${(
      fs.statSync(destArtifact).size /
      (1024 * 1024)
    ).toFixed(2)} MB) -> server-dist/xats-lsp-resident.opt1.js`,
  );

  // 2) the runtime node_modules the server requires.
  fs.mkdirSync(destNodeModules, { recursive: true });
  const missing = [];
  for (const dep of RUNTIME_DEPS) {
    const src = path.join(nodeModulesReal, dep);
    if (!fs.existsSync(src)) {
      missing.push(dep);
      continue;
    }
    copyDir(src, path.join(destNodeModules, dep));
    console.log(`[copy-server] copied node_modules/${dep}`);
  }
  if (missing.length > 0) {
    fail(
      `missing runtime server deps under ${nodeModulesReal}: ` +
        `${missing.join(", ")}. Reinstall the server deps and retry.`,
    );
  }

  console.log(`[copy-server] done -> ${destDir}`);
}

main();
