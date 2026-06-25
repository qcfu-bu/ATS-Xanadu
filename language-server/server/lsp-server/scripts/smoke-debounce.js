#!/usr/bin/env node
/*
 * WS-1b debounce smoke: prove a BURST of didChange notifications for one uri
 * COALESCES into a SINGLE checker run (one publishDiagnostics), per the brief
 * ("coalesce didChange bursts per uri"). We count `run_check ... (debounced
 * fire)` lines on the server's stderr; it must be exactly 1 despite 4 edits.
 *
 * Uses a counting wrapper checker so we can also assert spawn-once.
 */
'use strict';
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

const HERE = __dirname;
const SERVER = path.resolve(HERE, '..', 'xats-lsp-server.js');
const CONTRACT = path.resolve(HERE, '..', '..', '..', 'contract');
const FAKE_CHECKER = path.join(CONTRACT, 'fake-checker.js');

// A wrapper checker that bumps a counter file each spawn, then delegates.
const COUNTER = path.join(os.tmpdir(), `xats-lsp-spawncount-${process.pid}`);
const WRAPPER = path.join(os.tmpdir(), `xats-lsp-wrapper-${process.pid}.js`);
fs.writeFileSync(COUNTER, '0');
fs.writeFileSync(WRAPPER, `
'use strict';
const fs=require('fs'); const cp=require('child_process');
const COUNTER=${JSON.stringify(COUNTER)};
fs.writeFileSync(COUNTER, String((parseInt(fs.readFileSync(COUNTER,'utf8'),10)||0)+1));
const r=cp.spawnSync(process.execPath, [${JSON.stringify(FAKE_CHECKER)}, ...process.argv.slice(2)], {stdio:'inherit'});
process.exit(r.status||0);
`);

function encode(m){const p=Buffer.from(JSON.stringify(m),'utf8');return Buffer.concat([Buffer.from(`Content-Length: ${p.length}\r\n\r\n`,'ascii'),p]);}

const URI='file:///tmp/ats3-smoke/burst.dats';
const child=spawn(process.execPath,[SERVER,'--stdio'],{cwd:path.resolve(HERE,'..'),stdio:['pipe','pipe','pipe'],
  env:Object.assign({},process.env,{ATS3_LSP_CHECKER:WRAPPER,ATS3_LSP_DEBOUNCE_MS:'200'})});

let stderr='';
child.stderr.on('data',c=>{stderr+=c.toString();});
function send(m){child.stdin.write(encode(m));}

send({jsonrpc:'2.0',id:1,method:'initialize',params:{processId:process.pid,rootUri:null,capabilities:{}}});
send({jsonrpc:'2.0',method:'initialized',params:{}});
// open, then fire a burst of 4 changes within the debounce window.
send({jsonrpc:'2.0',method:'textDocument/didOpen',params:{textDocument:{uri:URI,languageId:'ats3',version:1,text:'val x: int = 1\n'}}});
let v=1;
const iv=setInterval(()=>{
  v++;
  send({jsonrpc:'2.0',method:'textDocument/didChange',params:{textDocument:{uri:URI,version:v},contentChanges:[{text:'val x: int = '+v+'\n'}]}});
  if(v>=5){clearInterval(iv);}
},20);

setTimeout(()=>{
  const fires=(stderr.match(/run_check: uri=.*\(debounced fire\)/g)||[]).length;
  const spawns=parseInt(fs.readFileSync(COUNTER,'utf8'),10)||0;
  console.log(`[debounce] debounced fires = ${fires}; checker spawns = ${spawns}`);
  let exitCode=0;
  if(fires===1) console.log('[debounce] PASS: a 5-version burst coalesced into exactly 1 debounced check.');
  else { console.error(`[debounce] FAIL: expected exactly 1 debounced fire, got ${fires}`); exitCode=1; }
  if(spawns===1) console.log('[debounce] PASS: checker was spawned exactly once.');
  else { console.error(`[debounce] FAIL: expected exactly 1 checker spawn, got ${spawns}`); exitCode=1; }
  try{child.kill();}catch(_){}
  try{fs.unlinkSync(COUNTER);fs.unlinkSync(WRAPPER);}catch(_){}
  process.exit(exitCode);
},2000);
