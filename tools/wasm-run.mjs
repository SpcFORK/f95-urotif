#!/usr/bin/env node
// Host for the experimental numeric/text WASM backend. Not a prototype parser.
import { readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const path = args.shift();
if (!path) { console.error('usage: node tools/wasm-run.mjs FILE.wasm [--json] [--fuel N] [--repeat N]'); process.exit(2); }
let fuel = 1_000_000, repeat = 1, json = false;
for (let i = 0; i < args.length; ++i) {
  if (args[i] === '--json') json = true;
  else if (args[i] === '--fuel') fuel = Number(args[++i]);
  else if (args[i] === '--repeat') repeat = Number(args[++i]);
  else throw new Error(`unknown option ${args[i]}`);
}
if (!Number.isInteger(fuel) || fuel < 1 || fuel > 2147483647) throw new Error('fuel must be 1..2147483647');
if (!Number.isInteger(repeat) || repeat < 1 || repeat > 100) throw new Error('repeat must be 1..100');
const rawInput = readFileSync(0, 'utf8');
const lines = rawInput.split(/\r?\n/);
if (lines.at(-1) === '') lines.pop();
const errors = [null, 'data stack underflow', 'data stack overflow', 'numeric operand required',
  'division by zero', 'return stack overflow', 'uninitialized global register',
  'invalid instruction/program counter', 'instruction fuel exhausted', 'invalid/exhausted numeric input',
  'non-finite arithmetic result'];
const decimal = /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/;
const decoder = new TextDecoder('utf-8');
let instance, output = '', inputIndex = 0;
function formatNumber(x) {
  if (x === 0) return '0';
  if (Math.abs(x) < 1e15 && Number.isInteger(x)) return String(x);
  const [mantissa, exponent] = x.toExponential(15).split('e');
  return `${mantissa}E${Number(exponent) < 0 ? '-' : '+'}${String(Math.abs(Number(exponent))).padStart(3, '0')}`;
}
function append(s) {
  if (output.length + s.length > 262144) throw new Error('host output limit exceeded');
  output += s;
}
const imports = { urotif: {
  write_text(ptr, len) {
    append(decoder.decode(new Uint8Array(instance.exports.memory.buffer, ptr >>> 0, len >>> 0)));
  },
  write_number(x) { append(formatNumber(x)); },
  read_number() {
    if (inputIndex >= lines.length) return NaN;
    const raw = lines[inputIndex++];
    const line = raw.replace(/^ +| +$/g, '');
    if (Buffer.byteLength(raw) > 2048 || !decimal.test(line)) return NaN;
    const value = Number(line);
    return Number.isFinite(value) ? value : NaN;
  },
}};
try {
  ({ instance } = await WebAssembly.instantiate(readFileSync(path), imports));
  let results = [];
  for (let i = 0; i < repeat; ++i) {
    output = ''; inputIndex = 0;
    const status = instance.exports.urotif_run(fuel);
    results.push({ status, output, error: errors[status] ?? null,
      line: instance.exports.urotif_error_line(), column: instance.exports.urotif_error_column(),
      steps: instance.exports.urotif_steps() });
  }
  const last = results.at(-1);
  if (json) console.log(JSON.stringify(repeat === 1 ? last : results));
  else {
    process.stdout.write(last.output);
    if (last.status) console.error(`WASM E${last.status} at ${last.line}:${last.column}: ${last.error}`);
  }
  process.exitCode = last.status ? 1 : 0;
} catch (e) {
  if (json) console.log(JSON.stringify({ status: -1, output, error: String(e) }));
  else console.error(String(e));
  process.exitCode = 2;
}
