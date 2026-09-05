import test from 'node:test';
import assert from 'node:assert/strict';
import {makeImports, readCatalog} from '../tools/wasm-links.mjs';
import providers from '../plugins/typed-host.mjs';
const encode = new TextEncoder();
const leb = n => { const b = []; do { const x = n & 127; n >>>= 7; b.push(x | (n ? 128 : 0)); } while (n); return b; };
const str = s => { const b = [...encode.encode(s)]; return [...leb(b.length), ...b]; };
const section = (id, b) => [id, ...leb(b.length), ...b];
const policy = {nodes:128,edges:32,text:256,output:64,stack:16,frames:1,returns:1,'input-line':128,input:256,source:1024,work:128};
function moduleFor(name, parameters, result, edit = x => x, copies = 1) {
  const [module, field] = name.split('.');
  const s = {slot:0,module,name:field,arity:parameters.length,kind:7,wasm_import:true,signature:{abi:2,parameters,result}};
  const catalog = edit({format:'Urotif Foundation link catalog 2',symbols:[s],limits:{...policy}});
  const custom = section(0, [...str('urotif.links.v2'), ...encode.encode(JSON.stringify(catalog))]);
  return new WebAssembly.Module(Uint8Array.from([0,97,115,109,1,0,0,0,
    ...section(1,[1,0x60,3,0x7f,0x7f,0x7f,1,0x7f]),
    ...section(2,[1,...str(module),...str(field),0,0]),
    ...Array.from({length:copies},()=>custom).flat()]));
}
function fixture(name='buffers.hex',parameters=[2],result=2,host=providers) {
  const memory = new WebAssembly.Memory({initial:1});
  const fake = {exports:{memory,urotif_typed_arg_size:()=>32,urotif_typed_result_size:()=>32}};
  const mod = moduleFor(name,parameters,result);
  const imports = makeImports(mod, host, () => fake), [m,f] = name.split('.');
  const view = () => new DataView(memory.buffer);
  const u32 = (p,n) => view().setUint32(p,n,true);
  const f64 = (p,n) => view().setFloat64(p,n,true);
  const out=512,bp=1024,vp=2048;
  u32(out+8,bp);u32(out+12,result===2?64:0);u32(out+20,vp);u32(out+24,result===3?8:0);
  parameters.forEach((tag,i)=>u32(8+i*32,tag));
  return {memory,fake,imports,view,u32,f64,out,bp,vp,call:(p=8,n=parameters.length,o=out)=>imports[m][f](p,n,o)};
}
const desc = (parameters,result,call) => ({abi:2,parameters,result,call});
test('binary bytes, copies, and refreshed views after memory.grow', () => {
  let x;
  const host={'buffers.hex':desc(['bytes'],'bytes',([b])=>{b[0]=0xaa;x.memory.grow(1);return b;})};
  x=fixture('buffers.hex',[2],2,host);x.u32(24,3000);x.u32(28,3);
  new Uint8Array(x.memory.buffer,3000,3).set([0,255,67]);
  const old=x.memory.buffer;assert.equal(x.call(),0);assert.equal(old.byteLength,0);
  assert.deepEqual([...new Uint8Array(x.memory.buffer,3000,3)],[0,255,67]);
  assert.deepEqual([...new Uint8Array(x.memory.buffer,x.bp,3)],[170,255,67]);
  assert.equal(x.view().getUint32(x.out+16,true),3);
});
test('vectors preserve order, are copied, and use little-endian float64', () => {
  const host={'vector.copy':desc(['vector','number'],'vector',([v,n])=>{v[0]+=n;return v;})};
  const x=fixture('vector.copy',[3,1],3,host);x.u32(32,3000);x.u32(36,2);x.f64(3000,-2.5);x.f64(3008,4);x.f64(48,3);
  assert.equal(x.call(),0);assert.equal(x.view().getFloat64(3000,true),-2.5);
  assert.equal(x.view().getFloat64(x.vp,true),0.5);assert.equal(x.view().getFloat64(x.vp+8,true),4);
  assert.equal(x.view().getUint32(x.out+28,true),2);
});
test('zero-argument byte and numeric calls', () => {
  assert.equal(fixture('buffers.empty',[],2).call(),0);
  const x=fixture('zero.answer',[],1,{'zero.answer':desc([],'number',()=>42)});
  assert.equal(x.call(),0);assert.equal(x.view().getFloat64(x.out,true),42);
});
test('arity, alignment, tags, null and out-of-range buffers are rejected before callback', () => {
  let calls=0;const host={'buffers.hex':desc(['bytes'],'bytes',()=>{calls++;return new Uint8Array();})};
  for(const setup of [x=>x.u32(8,1),x=>x.u32(12,1),x=>{x.u32(24,0);x.u32(28,1)},
    x=>{x.u32(24,65530);x.u32(28,20)},x=>x.u32(x.out+12,65)]){
    const x=fixture('buffers.hex',[2],2,host);setup(x);assert.equal(x.call(),1);
  }
  const x=fixture('buffers.hex',[2],2,host);
  assert.equal(x.call(12),1);assert.equal(x.call(8,2),1);assert.equal(x.call(8,0xffffffff),1);assert.equal(x.call(8,1,65520),1);
  const v=fixture('vector.noop',[3],1,{'vector.noop':desc(['vector'],'number',()=>{calls++;return 0;})});
  v.u32(32,3001);v.u32(36,1);assert.equal(v.call(),1);
  assert.equal(calls,0);
});
test('aggregate input limits count aliases, not just unique input addresses', () => {
  const x=fixture('all.bytes',Array(8).fill(2),1,{'all.bytes':desc(Array(8).fill('bytes'),'number',()=>0)});
  for(let i=0;i<8;i++){x.u32(24+i*32,3000);x.u32(28+i*32,40)}
  assert.equal(x.call(),1);
});
test('invalid numbers, sparse vectors, result types, and capacities fail', () => {
  for(const result of [NaN,Infinity,undefined,Promise.resolve(1)]){
    assert.equal(fixture('bad.number',[],1,{'bad.number':desc([],'number',()=>result)}).call(),1);
  }
  for(const result of [[NaN],Array(1),['3'],new Float64Array(9)]){
    assert.equal(fixture('bad.vector',[],3,{'bad.vector':desc([],'vector',()=>result)}).call(),1);
  }
  for(const result of ['not bytes',new Uint8Array(65)]){
    assert.equal(fixture('bad.bytes',[],2,{'bad.bytes':desc([],'bytes',()=>result)}).call(),1);
  }
  assert.equal(fixture('bad.throw',[],1,{'bad.throw':desc([],'number',()=>{throw Error('failure')})}).call(),1);
});
test('non-finite inputs and changed output ownership are rejected', () => {
  const x=fixture('number.id',[1],1,{'number.id':desc(['number'],'number',([n])=>n)});x.f64(16,NaN);assert.equal(x.call(),1);
  let y;y=fixture('bad.owner',[],2,{'bad.owner':desc([],'bytes',()=>{y.u32(y.out+8,3000);return new Uint8Array([1]);})});
  assert.equal(y.call(),1);assert.equal(y.view().getUint32(y.out+16,true),0);
});
test('typed grants must be own properties with exact, dense signatures', () => {
  const mod=moduleFor('buffers.hex',[2],2);
  for(const host of [{},Object.create(providers),{'buffers.hex':()=>0},
    {'buffers.hex':desc(['number'],'bytes',()=>new Uint8Array())},
    {'buffers.hex':desc(Array(1),'bytes',()=>new Uint8Array())}]){
    assert.throws(()=>makeImports(mod,host,()=>{}));
  }
});
test('prototype-related import names do not modify object prototypes', () => {
  for(const name of ['__proto__.constructor','constructor.__proto__']){
    const x=fixture(name,[],1,{[name]:desc([],'number',()=>3)});
    assert.equal(Object.getPrototypeOf(x.imports),null);
    assert.equal(Object.getPrototypeOf(x.imports[name.split('.')[0]]),null);
    assert.equal(x.call(),0);
  }
});
test('duplicate and corrupt catalogs fail closed', () => {
  assert.throws(()=>readCatalog(moduleFor('buffers.hex',[2],2,x=>x,2)),/duplicate/);
  assert.throws(()=>readCatalog(moduleFor('buffers.hex',[2],2,x=>{x.limits.output=1;return x})),/limit/);
  assert.throws(()=>readCatalog(moduleFor('buffers.hex',[2],2,x=>{x.symbols[0].signature.parameters=[4];return x})),/signature/);
});
test('Unicode providers reject invalid UTF-8 and retain a BOM as a codepoint', () => {
  const f=providers['unicode.codepoints'].call;
  assert.equal(f([encode.encode('\ufeffA😀')]),3);
  assert.throws(()=>f([new Uint8Array([0xff])]));
});
test('legacy numeric imports without a catalog still work, including memory growth', () => {
  const raw=[0,97,115,109,1,0,0,0,...section(1,[1,0x60,3,0x7f,0x7f,0x7f,1,0x7f]),...section(2,[1,...str('demo'),...str('cube'),0,0])];
  const mod=new WebAssembly.Module(Uint8Array.from(raw)),memory=new WebAssembly.Memory({initial:1});
  new DataView(memory.buffer).setFloat64(8,3,true);
  const imports=makeImports(mod,{'demo.cube':([n])=>{memory.grow(1);return n*n*n}},()=>({exports:{memory}}));
  assert.equal(readCatalog(mod),null);assert.equal(imports.demo.cube(8,1,16),0);
  assert.equal(new DataView(memory.buffer).getFloat64(16,true),27);
});
