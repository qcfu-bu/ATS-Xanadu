// node shim: re-exec the Chez resident .so so the node-spawning smoke harnesses
// can drive the Chez server unchanged. Point RESIDENT_SERVER at this file.
'use strict';
const { spawn } = require('child_process');
const path = require('path');
const SO = process.env.CHEZ_SO || path.resolve(__dirname, '..', 'BUILD', 'chez', 'chez-lsp-resident.so');
const c = spawn('chez', ['--script', SO, '--stdio'], { stdio: ['pipe','pipe','pipe'], env: process.env });
process.stdin.pipe(c.stdin); c.stdout.pipe(process.stdout); c.stderr.pipe(process.stderr);
c.on('exit', code => process.exit(code == null ? 0 : code));
