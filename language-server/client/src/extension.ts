/*
 * ATS3 LSP client.
 *
 * Thin TypeScript VSCode extension that launches the language server and speaks
 * LSP/JSON-RPC over stdio.
 *
 * The server is a single self-contained NATIVE binary: the ATS3 server sources
 * (language-server/go-server) compiled by the xats2go Go backend.  It needs no
 * runtime; the client spawns it directly.  Per typecheck the server spawns the
 * CHECK-ONLY compiler driver (xats2go-tcheck) on the file, so the client passes
 * XATSHOME via initializationOptions (M6: the compiler is in-process).
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
 * True when this extension is running from a packaged install (a `.vsix`)
 * rather than the in-repo dev checkout, detected by the packaged server
 * payload at `<extensionPath>/server-dist`. In the packaged case XATSHOME
 * cannot be inferred from the extension's location and MUST come from the
 * `ats3.xatshome` setting (or the XATSHOME env var).
 */
function isPackaged(context: ExtensionContext): boolean {
  return fs.existsSync(path.join(context.extensionPath, "server-dist"));
}

/**
 * Resolve the native server binary (ats3-lsp-server, built by
 * language-server/go-server/tools/build.sh).
 *
 * Priority: the `ats3.server.path` setting; the packaged binary in
 * `server-dist/`; the repo-relative dev build. Returns `undefined` when none
 * exists (the caller surfaces an actionable error).
 */
function resolveServerBinary(context: ExtensionContext): string | undefined {
  const exe = process.platform === "win32" ? "ats3-lsp-server.exe" : "ats3-lsp-server";
  const configured = workspace
    .getConfiguration("ats3")
    .get<string>("server.path", "")
    .trim();
  if (configured.length > 0) {
    return fs.existsSync(configured) ? configured : undefined;
  }
  const candidates = [
    path.join(context.extensionPath, "server-dist", exe),
    path.join(context.extensionPath, "..", "go-server", "BUILD", exe),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return undefined;
}

/**
 * Resolve XATSHOME (the ATS3/Xanadu repo root; the in-process compiler
 * reads the prelude from there). Priority: the `ats3.xatshome` setting; the XATSHOME env var;
 * (dev/in-repo only) two directories up from the extension.
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

  const serverBin = resolveServerBinary(context);
  if (serverBin === undefined) {
    window.showErrorMessage(
      `ATS3 LSP: server binary not found. Build it with ` +
        `"language-server/go-server/tools/build.sh" (-> go-server/BUILD/ats3-lsp-server) ` +
        `or set "ats3.server.path".`,
    );
    channel.appendLine(`[ats3] no server binary found`);
    return;
  }

  const xatshome = resolveXatshome(context);
  if (xatshome === undefined) {
    window.showErrorMessage(
      `ATS3 LSP: XATSHOME is not set. Set the "ats3.xatshome" setting to the ` +
        `path of your ATS3/Xanadu repo root (it holds the prelude the server ` +
        `needs), then reload the window.`,
    );
    channel.appendLine(
      `[ats3] XATSHOME unresolved (packaged install without ats3.xatshome / XATSHOME env)`,
    );
    return;
  }
  // Validate the configured/derived XATSHOME so a typo surfaces clearly rather
  // than as an opaque prelude-load failure inside the server.
  if (!fs.existsSync(xatshome)) {
    window.showErrorMessage(
      `ATS3 LSP: XATSHOME path does not exist: "${xatshome}". ` +
        `Fix the "ats3.xatshome" setting to point at your ATS3/Xanadu repo root.`,
    );
    channel.appendLine(`[ats3] XATSHOME does not exist: ${xatshome}`);
    return;
  }

  channel.appendLine(`[ats3] launching server: ${serverBin}`);
  channel.appendLine(`[ats3] XATSHOME=${xatshome}`);

  const launch = {
    command: serverBin,
    args: [] as string[],
    transport: TransportKind.stdio,
    options: { env: { ...process.env, XATSHOME: xatshome } },
  };
  const serverOptions: ServerOptions = { run: launch, debug: launch };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: "file", language: "ats" },
      { scheme: "file", language: "ats3" },
    ],
    synchronize: {
      // Watch ATS source files so the server is notified of on-disk changes.
      fileEvents: workspace.createFileSystemWatcher("**/*.{sats,hats,dats}"),
    },
    // The server's whole configuration rides in here: XATSHOME for the
    // in-process compiler's prelude (M6: the compiler is linked into the
    // server binary; there is no separate checker to spawn).
    initializationOptions: {
      xatshome: xatshome,
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
