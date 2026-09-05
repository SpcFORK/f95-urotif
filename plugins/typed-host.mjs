// Explicit ABI-2 providers; no native .so is loaded by WASM.
// The marshaller supplies numbers, copied Uint8Arrays, and copied Float64Arrays.
const utf8 = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
const encode = new TextEncoder();
const typed = (parameters, result, call) => ({abi: 2, parameters, result, call});
const finite = x => { if (!Number.isFinite(x)) throw Error('non-finite result'); return x; };
export default {
  'buffers.hex': typed(['bytes'], 'bytes', ([b], cap) => {
    if (b.length > Math.floor(cap.bytesCapacity / 2)) throw Error('capacity');
    return encode.encode(Array.from(b, x => x.toString(16).padStart(2, '0')).join(''));
  }),
  'buffers.unhex': typed(['bytes'], 'bytes', ([b], cap) => {
    if (b.length % 2 || b.length / 2 > cap.bytesCapacity) throw Error('hex/capacity');
    const s = Array.from(b, x => String.fromCharCode(x)).join('');
    if (!/^[0-9a-fA-F]*$/.test(s)) throw Error('hex');
    return Uint8Array.from({length: b.length / 2}, (_, i) => parseInt(s.slice(i * 2, i * 2 + 2), 16));
  }),
  'buffers.concat': typed(['bytes', 'bytes'], 'bytes', ([a, b], cap) => {
    if (a.length + b.length > cap.bytesCapacity) throw Error('capacity');
    const result = new Uint8Array(a.length + b.length); result.set(a); result.set(b, a.length); return result;
  }),
  'buffers.empty': typed([], 'bytes', () => new Uint8Array()),
  'buffers.prefix': typed(['bytes', 'number'], 'bytes', ([b, n], cap) => {
    if (!Number.isInteger(n) || n < 0 || n > b.length || n > cap.bytesCapacity) throw Error('prefix/capacity');
    return b.slice(0, n);
  }),
  'buffers.affine': typed(['vector', 'number', 'number'], 'vector', ([v, scale, offset], cap) => {
    if (v.length > cap.vectorCapacity) throw Error('capacity');
    return v.map(x => finite(x * scale + offset));
  }),
  'buffers.sum': typed(['vector'], 'number', ([v]) => finite(v.reduce((a, b) => a + b, 0))),
  'buffers.dot': typed(['vector', 'vector'], 'number', ([a, b]) => {
    if (a.length !== b.length) throw Error('vector length mismatch');
    return finite(a.reduce((sum, x, i) => sum + x * b[i], 0));
  }),
  'unicode.upper': typed(['bytes'], 'bytes', ([b]) => encode.encode(utf8.decode(b).toUpperCase())),
  'unicode.codepoints': typed(['bytes'], 'number', ([b]) => Array.from(utf8.decode(b)).length),
  'unicode.sort': typed(['vector'], 'vector', ([v], cap) => {
    if (v.length > cap.vectorCapacity) throw Error('capacity');
    // Float64Array.sort orders negative zero before positive zero, like total_cmp.
    return v.slice().sort();
  }),
};
