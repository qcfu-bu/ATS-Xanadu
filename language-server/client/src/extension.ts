/*
 * ATS3 LSP client.
 *
 * Thin TypeScript VSCode extension that launches the language server and speaks
 * LSP/JSON-RPC over stdio.
 *
 * The server is shipped as a single self-contained native binary built with
 * `deno compile` (see scripts/build-deno.js). It embeds V8 + the deno runtime +
 * the ATS3 checker + its deps, and bakes in `--allow-all` and
 * `--v8-flags=--stack-size=8801` (the deeply-recursive prelude load overflows
 * V8's default stack). So the client just spawns `xats-lsp-deno --stdio` and
 * passes XATSHOME through the environment. No node/node_modules at runtime.
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
 * Resolve the self-contained Deno server binary.
 *
 * Built by `npm run build:deno` (scripts/build-deno.js) via `deno compile`,
 * it embeds V8 + the runtime + the server + its deps, and bakes in
 * `--allow-all` and `--v8-flags=--stack-size=8801` — so it needs no node and is
 * launched simply as `xats-lsp-deno --stdio`. It is V8-based, so (unlike Bun)
 * it handles the deeply-recursive prelude load.
 *
 * Priority: the `ats3.server.denoPath` setting; then the packaged binary in
 * `server-dist/`; then the repo-relative dev build. Returns `undefined` when
 * none exists (the caller surfaces an actionable error).
 */
function resolveDenoBinary(context: ExtensionContext): string | undefined {
  const exe = process.platform === "win32" ? "xats-lsp-deno.exe" : "xats-lsp-deno";
  const configured = workspace
    .getConfiguration("ats3")
    .get<string>("server.denoPath", "")
    .trim();
  if (configured.length > 0) {
    return fs.existsSync(configured) ? configured : undefined;
  }
  const candidates = [
    path.join(context.extensionPath, "server-dist", exe),
    path.join(context.extensionPath, "..", "server", "resident", "BUILD", exe),
    path.join(context.extensionPath, "server", "resident", "BUILD", exe),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return undefined;
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

  const denoBin = resolveDenoBinary(context);
  if (denoBin === undefined) {
    window.showErrorMessage(
      `ATS3 LSP: server binary not found. Build it with "npm run build:deno" ` +
        `(it lands in server-dist/xats-lsp-deno), or set "ats3.server.denoPath" ` +
        `to the compiled Deno binary.`,
    );
    channel.appendLine(`[ats3] server binary not found (no server-dist/xats-lsp-deno)`);
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

  channel.appendLine(`[ats3] launching server: ${denoBin} (deno binary)`);
  channel.appendLine(`[ats3] XATSHOME=${xatshome}`);

  // Launch the server binary; communicate over stdio. `--stdio` is passed
  // explicitly: vscode-languageserver selects its transport from this flag.
  // (TransportKind.stdio already implies it, but being explicit keeps the
  // bare-launch path and the client path identical.) The stack flag and
  // permissions are compiled into the binary, so no extra args are needed.
  const serverOptions: ServerOptions = {
    run: {
      command: denoBin,
      args: ["--stdio"],
      transport: TransportKind.stdio,
      options: { env: serverEnv },
    },
    debug: {
      command: denoBin,
      args: ["--stdio"],
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
