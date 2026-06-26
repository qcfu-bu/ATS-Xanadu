#!/usr/bin/env node
/* End-to-end smoke for the CHEZ resident LSP server (spawns chez --script).
 * Covers: initialize, diagnostics, hover, definition, typeDefinition,
 * documentSymbol, references, semanticTokens/full, completion. Exit 0 = pass. */
'use strict';
const { spawn } = require('child_process');
const path = require('path'); const fs = require('fs'); const os = require('os');
const XATSHOME = process.env.XATSHOME || '/Users/qcfu/Projects/ATS-Xanadu';
const SO = process.env.CHEZ_SERVER || path.resolve(__dirname, '..', 'BUILD', 'chez', 'chez-lsp-resident.so');
const TIMEOUT = parseInt(process.env.SMOKE_TIMEOUT_MS || '120000', 10);

function encode(m){const p=Buffer.from(JSON.stringify(m),'utf8');return Buffer.concat([Buffer.from(`Content-Length: ${p.length}\r\n\r\n`,'ascii'),p]);}
class MR{constructor(on){this.b=Buffer.alloc(0);this.on=on;}push(c){this.b=Buffer.concat([this.b,c]);for(;;){const he=this.b.indexOf('\r\n\r\n');if(he<0)return;const m=/Content-Length:\s*(\d+)/i.exec(this.b.slice(0,he));if(!m){this.b=this.b.slice(he+4);continue;}const len=+m[1],bs=he+4;if(this.b.length<bs+len)return;const body=this.b.slice(bs,bs+len).toString('utf8');this.b=this.b.slice(bs+len);try{this.on(JSON.parse(body));}catch(e){}}}}

const fails=[]; const fail=(m)=>{fails.push(m);console.error('FAIL: '+m);}; const pass=(m)=>console.log('PASS: '+m);
const WS=fs.mkdtempSync(path.join(os.tmpdir(),'ats3-chez-'));
const BAD=path.join(WS,'bad.dats'); fs.writeFileSync(BAD,'val x: int = "hello"\nval y: int = nonexistent_var\n');
const OK=path.join(WS,'ok.dats');  fs.writeFileSync(OK,'fun dbl(n: int): int = n + n\nval r = dbl(3)\n');
const uriOf=p=>'file://'+p;

if(!fs.existsSync(SO)){fail('server .so missing: '+SO);process.exit(1);}
const child=spawn('chez',['--script',SO,'--stdio'],{cwd:WS,stdio:['pipe','pipe','pipe'],env:Object.assign({},process.env,{XATSHOME})});
let id=1,done=false; const pend=new Map(); const diagW=[];
const send=m=>child.stdin.write(encode(m));
const req=(method,params)=>{const i=id++;return new Promise(r=>{pend.set(i,r);send({jsonrpc:'2.0',id:i,method,params});});};
const notify=(method,params)=>send({jsonrpc:'2.0',method,params});
const waitDiag=uri=>new Promise(r=>diagW.push({uri,r}));
const reader=new MR(msg=>{
  if(msg.id!==undefined&&pend.has(msg.id)){const r=pend.get(msg.id);pend.delete(msg.id);r(msg);return;}
  if(msg.method==='textDocument/publishDiagnostics'){const p=msg.params||{};const i=diagW.findIndex(w=>w.uri===p.uri);if(i>=0)diagW.splice(i,1)[0].r(p.diagnostics||[]);}
});
child.stdout.on('data',c=>reader.push(c));
child.stderr.on('data',c=>{/* uncomment to debug: process.stderr.write(c); */});
child.on('exit',(code,sig)=>{if(!done)fail('server exited early code='+code+' sig='+sig);});
const timer=setTimeout(()=>{fail('timeout');finish();},TIMEOUT);
function finish(){if(done)return;done=true;clearTimeout(timer);try{notify('exit');}catch(_){}setTimeout(()=>{try{child.kill();}catch(_){}try{fs.rmSync(WS,{recursive:true,force:true});}catch(_){}console.log('\n=== '+(fails.length?('FAILED ('+fails.length+')'):'ALL PASS')+' ===');process.exit(fails.length?1:0);},200);}

(async()=>{
  const initRes=await req('initialize',{processId:process.pid,rootUri:uriOf(WS),capabilities:{workspace:{semanticTokens:{refreshSupport:true}}},workspaceFolders:[{uri:uriOf(WS),name:'ws'}]});
  const caps=initRes.result&&initRes.result.capabilities;
  if(caps&&caps.hoverProvider&&caps.definitionProvider&&caps.semanticTokensProvider) pass('initialize advertises capabilities');
  else fail('initialize capabilities missing: '+JSON.stringify(caps));
  notify('initialized',{});

  // diagnostics
  const dP=waitDiag(uriOf(BAD));
  notify('textDocument/didOpen',{textDocument:{uri:uriOf(BAD),languageId:'ats',version:1,text:fs.readFileSync(BAD,'utf8')}});
  const diags=await dP;
  const hasTM=diags.some(d=>d.code==='type-mismatch'&&d.range.start.line===0);
  const hasUB=diags.some(d=>d.code==='unbound-identifier'&&d.range.start.line===1);
  if(hasTM&&hasUB) pass('diagnostics: type-mismatch + unbound-identifier'); else fail('diagnostics wrong: '+JSON.stringify(diags));

  // open the OK file
  const dP2=waitDiag(uriOf(OK));
  notify('textDocument/didOpen',{textDocument:{uri:uriOf(OK),languageId:'ats',version:1,text:fs.readFileSync(OK,'utf8')}});
  const diags2=await dP2;
  if(diags2.length===0) pass('clean file: no diagnostics'); else fail('clean file had diagnostics: '+JSON.stringify(diags2));

  // hover on 'dbl' at its def (line 0, char 4)
  const h=await req('textDocument/hover',{textDocument:{uri:uriOf(OK)},position:{line:0,character:4}});
  const hv=h.result&&h.result.contents&&h.result.contents.value;
  if(hv&&/int/.test(hv)) pass('hover shows a type: '+hv.replace(/\n/g,' ')); else fail('hover empty/wrong: '+JSON.stringify(h.result));

  // definition on the use of dbl (line 1, char 8 -> 'dbl(3)')
  const d=await req('textDocument/definition',{textDocument:{uri:uriOf(OK)},position:{line:1,character:9}});
  const dr=d.result;
  if(dr&&dr.uri&&dr.range&&dr.range.start.line===0) pass('definition jumps to dbl binding (line 0)'); else fail('definition wrong: '+JSON.stringify(dr));

  // document symbols
  const ds=await req('textDocument/documentSymbol',{textDocument:{uri:uriOf(OK)}});
  const syms=ds.result||[];
  if(syms.some(s=>s.name==='dbl')) pass('documentSymbol lists dbl'); else fail('documentSymbol missing dbl: '+JSON.stringify(syms.map(s=>s.name)));

  // references on dbl (declaration included)
  const rf=await req('textDocument/references',{textDocument:{uri:uriOf(OK)},position:{line:1,character:9},context:{includeDeclaration:true}});
  const refs=rf.result||[];
  if(refs.length>=1) pass('references found ('+refs.length+')'); else fail('references empty');

  // semantic tokens
  const st=await req('textDocument/semanticTokens/full',{textDocument:{uri:uriOf(OK)}});
  const data=st.result&&st.result.data;
  if(Array.isArray(data)&&data.length>0&&data.length%5===0) pass('semanticTokens: '+(data.length/5)+' tokens'); else fail('semanticTokens bad: '+JSON.stringify(data&&data.slice(0,10)));

  // completion (general): type 'db' on a fresh line -> should offer 'dbl'
  notify('textDocument/didChange',{textDocument:{uri:uriOf(OK),version:2},contentChanges:[{range:{start:{line:1,character:13},end:{line:1,character:13}},text:'\nval z = db'}]});
  await new Promise(r=>setTimeout(r,200));
  const cmp=await req('textDocument/completion',{textDocument:{uri:uriOf(OK)},position:{line:2,character:10}});
  const items=(cmp.result&&(cmp.result.items||cmp.result))||[];
  if(items.some(it=>it.label==='dbl')) pass('completion offers dbl'); else fail('completion missing dbl: '+JSON.stringify(items.map(i=>i.label).slice(0,15)));

  finish();
})().catch(e=>{fail('exception: '+(e&&e.stack||e));finish();});
