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
 *   2. the bundled stub server shipped next to this extension.
 *
 * The stub lives at `<extensionRoot>/../server/stub/server.js` in the repo
 * layout. We also tolerate the packaged layout where it may be copied under the
 * extension root.
 */
function resolveServerModule(context: ExtensionContext): string {
  const configured = workspace
    .getConfiguration("ats3")
    .get<string>("server.module", "")
    .trim();
  if (configured.length > 0) {
    return configured;
  }

  // Repo layout: language-server/client  ->  language-server/server/...
  // Prefer the real ATS3-built server; fall back to the WS-0b stub if it
  // has not been built yet, so the extension still does something useful.
  const candidates = [
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
        `Set "ats3.server.module" to the server entrypoint.`,
    );
    channel.appendLine(`[ats3] server module not found: ${serverModule}`);
    return;
  }

  // The real ATS3 server spawns the compiler-linking checker, which reads
  // XATSHOME to locate the prelude. Default to the repo root (two levels up
  // from the client dir: language-server/client -> repo root), overridable via
  // the `ats3.xatshome` setting. Propagated into the server's process env and
  // inherited by the checker the server spawns.
  const xatshomeCfg = workspace
    .getConfiguration("ats3")
    .get<string>("xatshome", "")
    .trim();
  const xatshome =
    xatshomeCfg.length > 0
      ? xatshomeCfg
      : path.resolve(context.extensionPath, "..", "..");
  const serverEnv = { ...process.env, XATSHOME: xatshome };

  channel.appendLine(`[ats3] launching server: ${nodePath} ${serverModule}`);
  channel.appendLine(`[ats3] XATSHOME=${xatshome}`);

  // Launch the server as a child node process; communicate over stdio.
  // Pass `--stdio` explicitly: vscode-languageserver selects its transport from
  // this flag. (The client's TransportKind.stdio already implies it, but being
  // explicit keeps the server's bare-launch path and the client path identical.)
  const serverOptions: ServerOptions = {
    run: {
      command: nodePath,
      args: [serverModule, "--stdio"],
      transport: TransportKind.stdio,
      options: { env: serverEnv },
    },
    debug: {
      command: nodePath,
      args: ["--nolazy", serverModule, "--stdio"],
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
