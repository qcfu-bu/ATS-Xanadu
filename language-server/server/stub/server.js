/*
 * ATS3 LSP STUB SERVER (WS-0b) -- intentionally dumb, throwaway.
 *
 * Purpose: prove the VSCode client <-> server round-trip (plan §2, P0) without
 * any ATS3 compiler involvement. It does the minimum LSP handshake and, on
 * `didOpen`/`didChangeContent` of ANY document, publishes ONE hard-coded
 * diagnostic (a warning squiggle over the first line). That single squiggle in
 * the Extension Development Host is the entire acceptance test.
 *
 * This file will be replaced by the real ATS3-built `xats-lsp-server.js`
 * (workstream WS-1b). The client points at this stub by default but is
 * configurable (`ats3.server.module`), so swapping it in requires no client
 * change.
 *
 * Transport: LSP/JSON-RPC over stdio (createConnection(ProposedFeatures.all)
 * defaults to stdio when launched as a child process with piped stdio).
 */

"use strict";

const {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  DiagnosticSeverity,
  TextDocumentSyncKind,
} = require("vscode-languageserver/node");

const { TextDocument } = require("vscode-languageserver-textdocument");
const { StreamMessageReader, StreamMessageWriter } = require("vscode-languageserver/node");

// Create the connection over stdio.
//
// vscode-languageserver does NOT auto-select a transport: it needs either a
// `--stdio`/`--node-ipc`/`--socket` CLI flag (which the VSCode client passes
// automatically) or explicit reader/writer streams. To make this stub robust
// whether launched by the VSCode client (with --stdio) or bare (e.g. the smoke
// test), bind stdin/stdout explicitly unless a transport flag is supplied.
const hasTransportFlag = process.argv.some((a) =>
  a === "--stdio" || a === "--node-ipc" || a.startsWith("--socket"),
);

const connection = hasTransportFlag
  ? createConnection(ProposedFeatures.all)
  : createConnection(
      ProposedFeatures.all,
      new StreamMessageReader(process.stdin),
      new StreamMessageWriter(process.stdout),
    );

// Full document sync managed for us; we get onDidOpen / onDidChangeContent.
const documents = new TextDocuments(TextDocument);

connection.onInitialize(() => {
  connection.console.log("[ats3-stub] onInitialize");
  return {
    capabilities: {
      // Stub only needs document sync to react to opens/changes.
      textDocumentSync: TextDocumentSyncKind.Incremental,
    },
    serverInfo: {
      name: "ats3-lsp-stub-server",
      version: "0.0.1",
    },
  };
});

connection.onInitialized(() => {
  connection.console.log("[ats3-stub] onInitialized");
});

/**
 * Produce the single hard-coded diagnostic for a document.
 * Range: covers the first line (or as much of it as exists).
 */
function stubDiagnostics(textDocument) {
  const text = textDocument.getText();
  const firstNewline = text.indexOf("\n");
  const firstLineLen = firstNewline === -1 ? text.length : firstNewline;

  return [
    {
      severity: DiagnosticSeverity.Warning,
      range: {
        start: { line: 0, character: 0 },
        end: { line: 0, character: Math.max(1, firstLineLen) },
      },
      message:
        "ATS3 stub server is alive: this is a hard-coded diagnostic proving " +
        "the editor <-> server round-trip (WS-0b).",
      source: "ats3-stub",
      code: "stub-roundtrip",
    },
  ];
}

function publish(textDocument) {
  const diagnostics = stubDiagnostics(textDocument);
  connection.console.log(
    `[ats3-stub] publishDiagnostics for ${textDocument.uri} (${diagnostics.length})`,
  );
  connection.sendDiagnostics({ uri: textDocument.uri, diagnostics });
}

// Fire on first open and on every content change.
documents.onDidOpen((e) => {
  connection.console.log(`[ats3-stub] didOpen ${e.document.uri}`);
  publish(e.document);
});

documents.onDidChangeContent((e) => {
  connection.console.log(`[ats3-stub] didChangeContent ${e.document.uri}`);
  publish(e.document);
});

// Clear diagnostics when a document closes.
documents.onDidClose((e) => {
  connection.sendDiagnostics({ uri: e.document.uri, diagnostics: [] });
});

// Wire the document manager to the connection, then start listening.
documents.listen(connection);
connection.listen();

connection.console.log("[ats3-stub] listening on stdio");
