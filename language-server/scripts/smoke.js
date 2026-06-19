#!/usr/bin/env node
/*
 * Headless smoke test for the ATS3 LSP stub server (WS-0b).
 *
 * Spawns the stub server as a child process and speaks raw LSP/JSON-RPC over
 * stdio (Content-Length framed messages), exactly as the VSCode client would.
 * It then asserts:
 *
 *   1. the server replies to `initialize` with a result (capabilities);
 *   2. after `initialized` + `textDocument/didOpen` of a fake `.dats` doc, the
 *      server emits a `textDocument/publishDiagnostics` notification containing
 *      the hard-coded stub diagnostic.
 *
 * Exit code 0 = round-trip proven; non-zero = failure.
 *
 * This proves the editor<->server pipeline headlessly (no VSCode GUI required).
 */

"use strict";

const { spawn } = require("child_process");
const path = require("path");

const SERVER = path.resolve(__dirname, "..", "server", "stub", "server.js");
const TIMEOUT_MS = 10000;

// --- LSP framing: encode a JSON-RPC message with a Content-Length header. ---
function encode(msg) {
  const json = JSON.stringify(msg);
  const payload = Buffer.from(json, "utf8");
  return Buffer.concat([
    Buffer.from(`Content-Length: ${payload.length}\r\n\r\n`, "ascii"),
    payload,
  ]);
}

// --- LSP framing: a streaming decoder that yields parsed messages. ---
class MessageReader {
  constructor(onMessage) {
    this.buffer = Buffer.alloc(0);
    this.onMessage = onMessage;
  }
  push(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    // Loop: extract as many complete messages as are buffered.
    for (;;) {
      const headerEnd = this.buffer.indexOf("\r\n\r\n");
      if (headerEnd === -1) return;
      const header = this.buffer.slice(0, headerEnd).toString("ascii");
      const m = /Content-Length:\s*(\d+)/i.exec(header);
      if (!m) {
        // Malformed; drop the header to avoid an infinite loop.
        this.buffer = this.buffer.slice(headerEnd + 4);
        continue;
      }
      const len = parseInt(m[1], 10);
      const bodyStart = headerEnd + 4;
      if (this.buffer.length < bodyStart + len) return; // wait for more bytes
      const body = this.buffer.slice(bodyStart, bodyStart + len).toString("utf8");
      this.buffer = this.buffer.slice(bodyStart + len);
      try {
        this.onMessage(JSON.parse(body));
      } catch (e) {
        console.error("[smoke] failed to parse message body:", body);
        throw e;
      }
    }
  }
}

function fail(msg) {
  console.error(`\n[smoke] FAIL: ${msg}`);
  process.exitCode = 1;
}

function main() {
  console.log(`[smoke] server: ${SERVER}`);
  const child = spawn(process.execPath, [SERVER], {
    stdio: ["pipe", "pipe", "pipe"],
  });

  // The fake document we will "open".
  const DOC_URI = "file:///tmp/ats3-smoke/Foo.dats";
  const DOC_TEXT = 'implement main0 () = let val x: int = "hello" in () end\n';

  let initializeReplied = false;
  let gotDiagnostics = false;
  let diagPayload = null;
  let done = false;

  const timer = setTimeout(() => {
    if (!done) {
      fail(`timed out after ${TIMEOUT_MS}ms (initializeReplied=${initializeReplied}, gotDiagnostics=${gotDiagnostics})`);
      try { child.kill(); } catch (_) {}
    }
  }, TIMEOUT_MS);

  function finish() {
    if (done) return;
    done = true;
    clearTimeout(timer);
    // Politely ask the server to shut down, then exit.
    try {
      child.stdin.write(encode({ jsonrpc: "2.0", id: 99, method: "shutdown" }));
      child.stdin.write(encode({ jsonrpc: "2.0", method: "exit" }));
    } catch (_) {}
    setTimeout(() => { try { child.kill(); } catch (_) {} }, 250);

    if (initializeReplied && gotDiagnostics) {
      console.log("\n[smoke] PASS: initialize replied AND publishDiagnostics received with the stub diagnostic.");
      process.exitCode = 0;
    } else {
      fail(`round-trip incomplete (initializeReplied=${initializeReplied}, gotDiagnostics=${gotDiagnostics})`);
    }
  }

  const reader = new MessageReader((msg) => {
    // Pretty-log every server->client message for the captured output.
    const tag = msg.method ? `notif/${msg.method}` : (msg.id !== undefined ? `reply#${msg.id}` : "msg");
    console.log(`[smoke] <- ${tag}: ${JSON.stringify(msg).slice(0, 400)}`);

    // 1) initialize reply
    if (msg.id === 1 && msg.result && msg.result.capabilities) {
      initializeReplied = true;
      console.log("[smoke]    initialize OK, capabilities present.");
      // Send `initialized` then `didOpen`.
      child.stdin.write(encode({ jsonrpc: "2.0", method: "initialized", params: {} }));
      child.stdin.write(encode({
        jsonrpc: "2.0",
        method: "textDocument/didOpen",
        params: {
          textDocument: {
            uri: DOC_URI,
            languageId: "ats3",
            version: 1,
            text: DOC_TEXT,
          },
        },
      }));
    }

    // 2) publishDiagnostics notification
    if (msg.method === "textDocument/publishDiagnostics") {
      const p = msg.params || {};
      if (p.uri === DOC_URI && Array.isArray(p.diagnostics) && p.diagnostics.length > 0) {
        gotDiagnostics = true;
        diagPayload = p;
        console.log(`[smoke]    publishDiagnostics OK for ${p.uri} with ${p.diagnostics.length} diagnostic(s):`);
        for (const d of p.diagnostics) {
          console.log(`[smoke]      - [sev=${d.severity}] code=${JSON.stringify(d.code)} @${JSON.stringify(d.range)} :: ${d.message}`);
        }
        finish();
      }
    }
  });

  child.stdout.on("data", (chunk) => reader.push(chunk));

  // Server log/console output arrives on stderr; surface it for the capture.
  child.stderr.on("data", (chunk) => {
    process.stderr.write(`[server-stderr] ${chunk.toString()}`);
  });

  child.on("error", (err) => {
    fail(`failed to spawn server: ${err.message}`);
    clearTimeout(timer);
  });

  child.on("exit", (code, signal) => {
    if (!done) {
      fail(`server exited early (code=${code}, signal=${signal})`);
      clearTimeout(timer);
    }
  });

  // Kick off the handshake with `initialize`.
  child.stdin.write(encode({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {
      processId: process.pid,
      clientInfo: { name: "ats3-smoke", version: "0.0.1" },
      rootUri: null,
      capabilities: {},
    },
  }));
}

main();
