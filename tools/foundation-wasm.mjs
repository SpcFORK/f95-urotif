#!/usr/bin/env node
// Fixed-buffer numeric/typed ABI host. Does not parse or interpret Urotif.
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {makeImports} from './wasm-links.mjs';
const args=process.argv.slice(2),path=args.shift();
if(!path){console.error('usage: node tools/foundation-wasm.mjs FILE.wasm [--json] [--fuel N] [--repeat N] [--host FILE.mjs]');process.exit(2)}
let fuel=1_000_000,repeat=1,json=false,hostPath;
for(let i=0;i<args.length;i++){
 if(args[i]==='--json')json=true;
 else if(args[i]==='--fuel')fuel=Number(args[++i]);
 else if(args[i]==='--repeat')repeat=Number(args[++i]);
 else if(args[i]==='--host')hostPath=args[++i];
 else throw Error(`unknown option: ${args[i]}`);
}
if(!Number.isInteger(fuel)||fuel<1||fuel>2147483647)throw Error('fuel must be 1..2147483647');
if(!Number.isInteger(repeat)||repeat<1||repeat>10000)throw Error('repeat must be 1..10000');
let instance;
try{
 const functions=hostPath?(await import(pathToFileURL(resolve(hostPath)).href)).default:{};
 const module=await WebAssembly.compile(readFileSync(path));
 const imports=makeImports(module,functions,()=>instance);
 instance=await WebAssembly.instantiate(module,imports);
 const input=instance.exports.urotif_uses_input()?readFileSync(0):Buffer.alloc(0);const ptr=instance.exports.urotif_input_ptr()>>>0;
 if(input.length>instance.exports.urotif_input_capacity())throw Error('input buffer limit exceeded');
 new Uint8Array(instance.exports.memory.buffer,ptr,input.length).set(input);
 let result,output;
 for(let i=0;i<repeat;i++){
  const status=instance.exports.urotif_run(input.length,fuel);
  output=Buffer.from(new Uint8Array(instance.exports.memory.buffer,instance.exports.urotif_output_ptr()>>>0,instance.exports.urotif_output_len()>>>0));
  result={status,output:output.toString('utf8'),output_hex:output.toString('hex'),steps:instance.exports.urotif_steps(),line:instance.exports.urotif_error_line(),column:instance.exports.urotif_error_column(),collections:instance.exports.urotif_collections(),stack_depth:instance.exports.urotif_stack_depth()};
 }
 if(json)console.log(JSON.stringify(result));else{process.stdout.write(output);if(result.status)console.error(`Foundation P${String(result.status).padStart(3,'0')} at ${result.line}:${result.column}`)}
 process.exitCode=result.status?1:0;
}catch(error){if(json)console.log(JSON.stringify({status:-1,error:String(error)}));else console.error(String(error));process.exitCode=2}
