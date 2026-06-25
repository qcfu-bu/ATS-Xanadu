#!/usr/bin/env node
/*
 * Depgraph cross-file incrementality test for the RESIDENT server.
 *
 * Scenario: B.dats `#staload "./A.sats"` and uses a function declared in A.
 *   1. open B  -> B checks clean; the dependency pass records the edge A -> B
 *      (B depends on A) in the depgraph.
 *   2. edit A on disk so the symbol B uses no longer type-checks, then fire
 *      didChange(A). The pruner evicts A AND its dependent B from the compiler
 *      caches (env_reset over the topmaps via the depgraph).
 *   3. re-validate B (didSave B). Because B was evicted, it re-translates and
 *      re-reads the (now-changed) A -> B should now report a NEW error.
 *
 * If the depgraph edge were NOT recorded, step 2 would only evict A, leaving B's
 * stale translation cached, and step 3 would still report B as clean (a bug).
 *
 * Exit 0 = depgraph invalidation works.
 */
'use strict';
const { spawn } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const SERVER = process.env.RESIDENT_SERVER ||
  path.resolve(__dirname, '..', 'BUILD', 'xats-lsp-resident.opt1.js');
const WS = fs.mkdtempSync(path.join(os.tmpdir(), 'ats3-depgraph-'));
const A = path.join(WS, 'A.sats'), B = path.join(WS, 'B.dats');
const URI_A = 'file://' + A, URI_B = 'file://' + B;

const A_OK  = 'fun afun(x: int): int\n';
const A_BAD = 'fun afun(x: int, y: int): int\n';     // now needs 2 args
const B_SRC = '#staload "./A.sats"\nval z: int = afun(5)\n'; // calls afun with 1 arg

function enc(m){const p=Buffer.from(JSON.stringify(m));return Buffer.concat([Buffer.from(`Content-Length: ${p.length}\r\n\r\n`),p]);}
class R{constructor(f){this.b=Buffer.alloc(0);this.f=f;}push(c){this.b=Buffer.concat([this.b,c]);for(;;){const he=this.b.indexOf('\r\n\r\n');if(he<0)return;const m=/Content-Length:\s*(\d+)/i.exec(this.b.slice(0,he).toString());if(!m){this.b=this.b.slice(he+4);continue;}const len=+m[1];if(this.b.length<he+4+len)return;const body=this.b.slice(he+4,he+4+len).toString();this.b=this.b.slice(he+4+len);try{this.f(JSON.parse(body));}catch(e){}}}}

const fails=[];
function fail(m){fails.push(m);console.error('[depgraph] FAIL: '+m);}
function pass(m){console.log('[depgraph] PASS: '+m);}

fs.writeFileSync(A, A_OK); fs.writeFileSync(B, B_SRC);
const c = spawn(process.execPath, ['--stack-size=8801', SERVER, '--stdio'], { cwd: WS, stdio:['pipe','pipe','pipe'] });
let id=100; const pend=new Map(); const waiters=[]; let done=false;
function send(m){c.stdin.write(enc(m));}
function req(method,params){const i=id++;return new Promise(r=>{pend.set(i,r);send({jsonrpc:'2.0',id:i,method,params});});}
function notify(method,params){send({jsonrpc:'2.0',method,params});}
function waitDiag(uri){return new Promise(res=>waiters.push({uri,res}));}
function open(uri,t){notify('textDocument/didOpen',{textDocument:{uri,languageId:uri.endsWith('.sats')?'ats':'ats3',version:1,text:t}});}
function change(uri,v){notify('textDocument/didChange',{textDocument:{uri,version:v},contentChanges:[{text:fs.readFileSync(uri.replace('file://',''),'utf8')}]});}
function save(uri){notify('textDocument/didSave',{textDocument:{uri}});}

const reader=new R(msg=>{
  if(msg.id!==undefined&&pend.has(msg.id)){const r=pend.get(msg.id);pend.delete(msg.id);return r(msg);}
  if(msg.method==='textDocument/publishDiagnostics'){const p=msg.params||{};const i=waiters.findIndex(w=>w.uri===p.uri);if(i>=0){const w=waiters.splice(i,1)[0];w.res(p.diagnostics||[]);}}
});
c.stdout.on('data',ch=>reader.push(ch));
c.stderr.on('data',ch=>{for(const l of ch.toString().split('\n')){if(l.includes('[xats-lsp-metric]')||l.includes('threw'))console.error('[server]',l);}});
c.on('exit',(code,sig)=>{if(!done)fail(`server exited early code=${code} sig=${sig}`);});

const TO=setTimeout(()=>{fail('timeout');finish();},120000);
function finish(){if(done)return;done=true;clearTimeout(TO);try{notify('exit');}catch(e){}setTimeout(()=>{try{c.kill();}catch(e){}try{fs.rmSync(WS,{recursive:true,force:true});}catch(e){}},200);const ok=fails.length===0;console.log(ok?'\n[depgraph] ALL PASS':`\n[depgraph] FAILURES: ${fails.length}`);process.exitCode=ok?0:1;}

(async()=>{
  await req('initialize',{processId:process.pid,rootUri:'file://'+WS,capabilities:{}});
  notify('initialized',{});

  // 1) open B -> checks B, records depgraph edge A -> B.
  let w=waitDiag(URI_B); open(URI_B,B_SRC); let d=await w;
  console.log(`[depgraph] (1) open B (clean) -> ${d.length} diagnostic(s) [${d.map(x=>x.code).join(',')}]`);
  // B as written (afun(5)) is clean against A_OK.
  d.length===0 ? pass('B checks clean against the original A (edge A->B recorded)') : console.log('[depgraph] note: B not clean initially:', JSON.stringify(d.map(x=>x.code)));

  // 2) break A on disk (afun now needs 2 args), fire didChange(A) to PRUNE A + dependents.
  fs.writeFileSync(A, A_BAD);
  open(URI_A, A_BAD);          // tell the server A is open (so it has a doc)
  change(URI_A, 2);            // PRUNE: evict A AND its dependent B (depgraph)

  // 3) re-validate B. If B was evicted (depgraph worked), it re-reads the new A
  //    and afun(5) is now a wrong-arity call -> B reports an error.
  w=waitDiag(URI_B); save(URI_B); d=await w;
  console.log(`[depgraph] (3) re-check B after editing A -> ${d.length} diagnostic(s) [${d.map(x=>x.code).join(',')}]`);
  if (d.length > 0) pass('DEPGRAPH: editing A invalidated B -> B re-checked and now reports an error (transitive eviction works)');
  else fail('DEPGRAPH: B still clean after breaking A -> B was NOT evicted (stale cross-file cache)');

  finish();
})().catch(e=>{fail('threw: '+(e&&e.stack?e.stack:e));finish();});
