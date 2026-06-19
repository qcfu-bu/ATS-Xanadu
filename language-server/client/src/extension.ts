/*
 * ATS3 LSP client (WS-0b).
 *
 * Thin TypeScript VSCode extension that launches the language server as a
 * child `node` process and speaks LSP/JSON-RPC over stdio (plan §2).
 *
 * For Phase 0 the server defaults to the throwaway stub at
 * `server/stub/server.js`, which publishes one hard-coded diagnostic to prove
 * the editor <-> server round-trip. The server module path is configurable via
 * the `ats3.server.module` setting so this client can later point at the real
 * ATS3-built `xats-lsp-server.js` with no code change.
 */

import * as path from "path";
import * as fs from "fs";
import {
  ExtensionContext,
  workspace,
  window,
  OutputChannel,
} from "vscode";

import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;

/**
 * Resolve the absolute path to the server entrypoint.
 *
 * Priority:
 *   1. the `ats3.server.module` setting, if set (absolute path expected);
 *   2. the PACKAGED server shipped inside the extension at
 *      `<extensionPath>/server-dist/xats-lsp-resident.opt1.js` (this is what
 *      an installed `.vsix` uses; its runtime `node_modules` sit next to it);
 *   3. the repo-relative dev paths (resident, then spawn-based, then the stub),
 *      so running the unpackaged extension via F5 still works.
 */
function resolveServerModule(context: ExtensionContext): string {
  const configured = workspace
    .getConfiguration("ats3")
    .get<string>("server.module", "")
    .trim();
  if (configured.length > 0) {
    return configured;
  }

  // Packaged-first: when installed from a .vsix, the resident server and its
  // runtime node_modules are copied into <extensionPath>/server-dist at package
  // time (see package.json `package` script / scripts/copy-server.js). Prefer it
  // so installed users do not depend on any repo-relative layout.
  // Repo layout fallback: language-server/client -> language-server/server/...
  // Prefer the fast RESIDENT in-process server (R1); then the spawn-based
  // server; then the WS-0b stub, so the extension still does something if the
  // newer artifacts have not been built yet.
  const candidates = [
    path.join(context.extensionPath, "server-dist", "xats-lsp-resident.opt1.js"),
    path.join(context.extensionPath, "..", "server", "resident", "BUILD", "xats-lsp-resident.opt1.js"),
    path.join(context.extensionPath, "server", "resident", "BUILD", "xats-lsp-resident.opt1.js"),
    path.join(context.extensionPath, "..", "server", "lsp-server", "xats-lsp-server.js"),
    path.join(context.extensionPath, "server", "lsp-server", "xats-lsp-server.js"),
    path.join(context.extensionPath, "..", "server", "stub", "server.js"),
    path.join(context.extensionPath, "server", "stub", "server.js"),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  // Fall back to the first candidate so the error message is actionable.
  return candidates[0];
}

/**
 * True when this extension is running from a packaged install (a `.vsix`)
 * rather than the in-repo dev checkout. We detect this by the presence of the
 * packaged server payload at `<extensionPath>/server-dist`, which only the
 * `package` step produces. In the packaged case we cannot infer XATSHOME from
 * the extension's location (the repo is not next to it), so it MUST come from
 * the `ats3.xatshome` setting (or the XATSHOME env var).
 */
function isPackaged(context: ExtensionContext): boolean {
  return fs.existsSync(path.join(context.extensionPath, "server-dist"));
}

/**
 * Resolve XATSHOME (the ATS3/Xanadu repo root, needed by the checker to find
 * the prelude). Returns `undefined` when it cannot be determined.
 *
 * Priority:
 *   1. the `ats3.xatshome` setting, if set;
 *   2. the `XATSHOME` env var of the host process;
 *   3. (dev/in-repo only) two directories up from the extension, i.e. the repo
 *      root in the `language-server/client` layout. NOT used when packaged.
 */
function resolveXatshome(context: ExtensionContext): string | undefined {
  const xatshomeCfg = workspace
    .getConfiguration("ats3")
    .get<string>("xatshome", "")
    .trim();
  if (xatshomeCfg.length > 0) {
    return xatshomeCfg;
  }

  const envHome = (process.env.XATSHOME ?? "").trim();
  if (envHome.length > 0) {
    return envHome;
  }

  if (isPackaged(context)) {
    // No safe default for an installed extension: the repo is not adjacent to
    // the installed extension dir. The caller surfaces an actionable error.
    return undefined;
  }

  // Dev / in-repo layout: language-server/client -> repo root (two levels up).
  return path.resolve(context.extensionPath, "..", "..");
}

export function activate(context: ExtensionContext): void {
  const channel: OutputChannel = window.createOutputChannel("ATS3 Language Server");
  context.subscriptions.push(channel);

  const serverModule = resolveServerModule(context);
  const nodePath = workspace
    .getConfiguration("ats3")
    .get<string>("server.nodePath", "node");

  if (!fs.existsSync(serverModule)) {
    window.showErrorMessage(
      `ATS3 LSP: server module not found at "${serverModule}". ` +
        `Set "ats3.server.module" to the server entrypoint, or reinstall the ` +
        `extension (the packaged server should live at ` +
        `<extension>/server-dist/xats-lsp-resident.opt1.js).`,
    );
    channel.appendLine(`[ats3] server module not found: ${serverModule}`);
    return;
  }

  // The real ATS3 server checks in-process and reads XATSHOME to locate the
  // prelude. In the dev/in-repo layout we can default it to the repo root, but
  // an installed extension has no repo next to it, so it MUST be configured via
  // the `ats3.xatshome` setting (or the XATSHOME env var). Propagated into the
  // server's process env.
  const xatshome = resolveXatshome(context);
  if (xatshome === undefined) {
    window.showErrorMessage(
      `ATS3 LSP: XATSHOME is not set. Set the "ats3.xatshome" setting to the ` +
        `path of your ATS3/Xanadu repo root (it holds the prelude the checker ` +
        `needs), then reload the window.`,
    );
    channel.appendLine(
      `[ats3] XATSHOME unresolved (packaged install without ats3.xatshome / XATSHOME env)`,
    );
    return;
  }
  // Validate the configured/derived XATSHOME so a typo surfaces clearly rather
  // than as an opaque prelude-load crash inside the server.
  if (!fs.existsSync(xatshome)) {
    window.showErrorMessage(
      `ATS3 LSP: XATSHOME path does not exist: "${xatshome}". ` +
        `Fix the "ats3.xatshome" setting to point at your ATS3/Xanadu repo root.`,
    );
    channel.appendLine(`[ats3] XATSHOME does not exist: ${xatshome}`);
    return;
  }
  const serverEnv = { ...process.env, XATSHOME: xatshome };

  channel.appendLine(`[ats3] launching server: ${nodePath} ${serverModule}`);
  channel.appendLine(`[ats3] XATSHOME=${xatshome}`);

  // Launch the server as a child node process; communicate over stdio.
  // Pass `--stdio` explicitly: vscode-languageserver selects its transport from
  // this flag. (The client's TransportKind.stdio already implies it, but being
  // explicit keeps the server's bare-launch path and the client path identical.)
  // The resident server bundles the deeply-recursive ATS3 compiler and loads
  // the prelude at startup, so node needs a large V8 stack or it overflows
  // before it can respond to `initialize` (the headless smokes pass this flag,
  // which is why they didn't catch it). Harmless for the stub/spawn fallbacks.
  // Must precede the script path to be parsed as a node flag.
  const nodeArgs = ["--stack-size=8801"];
  const serverOptions: ServerOptions = {
    run: {
      command: nodePath,
      args: [...nodeArgs, serverModule, "--stdio"],
      transport: TransportKind.stdio,
      options: { env: serverEnv },
    },
    debug: {
      command: nodePath,
      args: ["--nolazy", ...nodeArgs, serverModule, "--stdio"],
      transport: TransportKind.stdio,
      options: { env: serverEnv },
    },
  };

  const clientOptions: LanguageClientOptions = {
    // Bind to both language ids registered in package.json.
    documentSelector: [
      { scheme: "file", language: "ats" },
      { scheme: "file", language: "ats3" },
    ],
    synchronize: {
      // Watch ATS source files so the server is notified of on-disk changes.
      fileEvents: workspace.createFileSystemWatcher("**/*.{sats,hats,dats}"),
    },
    outputChannel: channel,
  };

  client = new LanguageClient(
    "ats3LanguageServer",
    "ATS3 Language Server",
    serverOptions,
    clientOptions,
  );

  // Starting the client also launches the server.
  client.start();
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}
