// C-compatible numeric/typed imports for emitted core-WASM; no Urotif parser.
// Providers are explicitly granted, synchronous, trusted JavaScript code.
const typeNames = ['', 'number', 'bytes', 'vector'];
const limits = {
  nodes: [128, 1048576], edges: [32, 4194304], text: [256, 67108864],
  output: [64, 33554432], stack: [16, 1048576], frames: [1, 1024],
  returns: [1, 1048576], 'input-line': [1, 16777216], input: [1, 67108864],
  source: [64, 8388608], work: [1, 16777216],
};
const ident = s => typeof s === 'string' && /^[A-Za-z_][A-Za-z0-9_]{0,62}$/.test(s);
const kind = k => Number.isInteger(k) && k >= 1 && k <= 3;
function check(ok, message) { if (!ok) throw Error(message); }
function range(memory, ptr, count, width = 1, alignment = 1) {
  check(Number.isInteger(ptr) && ptr >= 0 && Number.isInteger(count) && count >= 0 &&
    (count === 0 || (ptr !== 0 && ptr % alignment === 0)) &&
    ptr <= memory.byteLength && count <= Math.floor((memory.byteLength - ptr) / width),
    'invalid WASM buffer range/alignment');
}
export function readCatalog(module) {
  const sections = WebAssembly.Module.customSections(module, 'urotif.links.v2');
  if (sections.length === 0) return null; // Old numeric modules remain usable.
  check(sections.length === 1 && sections[0].byteLength <= 262144, 'invalid/duplicate link catalog');
  const catalog = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(sections[0]));
  check(catalog?.format === 'Urotif Foundation link catalog 2' &&
    Array.isArray(catalog.symbols) && catalog.symbols.length <= 256, 'invalid link catalog');
  for (const [key, [low, high]] of Object.entries(limits)) {
    check(Number.isInteger(catalog.limits?.[key]) && catalog.limits[key] >= low &&
      catalog.limits[key] <= high, `invalid catalog limit ${key}`);
  }
  const entries = new Map();
  for (const [index, s] of catalog.symbols.entries()) {
    check(s && s.slot === index && ident(s.module) && ident(s.name) &&
      Number.isInteger(s.arity) && s.arity >= 0 && s.arity <= 8 &&
      Number.isInteger(s.kind) && [0, 1, 2, 3, 4, 7].includes(s.kind) &&
      typeof s.wasm_import === 'boolean', 'invalid catalog symbol');
    if (s.kind === 7) {
      check(s.wasm_import && s.signature?.abi === 2 && Array.isArray(s.signature.parameters) &&
        s.signature.parameters.length === s.arity && s.signature.parameters.every(kind) &&
        kind(s.signature.result), 'invalid typed catalog signature');
    } else {
      check(s.signature === null && (!s.wasm_import || s.kind === 0), 'invalid numeric catalog signature');
    }
    const key = `${s.module}.${s.name}`;
    check(!entries.has(key), 'duplicate catalog symbol');
    entries.set(key, s);
  }
  return {entries, limits: catalog.limits};
}
function numericImport(fn, arity, getInstance) {
  return (ptr, n, out) => {
    try {
      ptr >>>= 0; n >>>= 0; out >>>= 0;
      const memory = getInstance().exports.memory.buffer;
      check(n <= 8 && (arity === undefined || n === arity), 'numeric arity mismatch');
      range(memory, ptr, n, 8, 8); range(memory, out, 1, 8, 8);
      const view = new DataView(memory), values = [];
      for (let i = 0; i < n; i++) {
        const x = view.getFloat64(ptr + i * 8, true);
        check(Number.isFinite(x), 'non-finite argument'); values.push(x);
      }
      const result = fn(values);
      check(typeof result === 'number' && Number.isFinite(result), 'non-finite numeric result');
      const fresh = getInstance().exports.memory.buffer;
      range(fresh, out, 1, 8, 8);
      new DataView(fresh).setFloat64(out, result, true);
      return 0;
    } catch { return 1; }
  };
}
function typedImport(provider, signature, budget, getInstance) {
  const fn = provider.call, parameters = [...signature.parameters], resultKind = signature.result;
  return (ptr, n, out) => {
    try {
      ptr >>>= 0; n >>>= 0; out >>>= 0;
      const exports = getInstance().exports;
      check(exports.urotif_typed_arg_size?.() === 32 && exports.urotif_typed_result_size?.() === 32,
        'typed WASM layout mismatch');
      const memory = exports.memory.buffer;
      check(n === parameters.length && n <= 8, 'typed arity mismatch');
      range(memory, ptr, n, 32, 8); range(memory, out, 1, 32, 8);
      let view = new DataView(memory);
      const bp = view.getUint32(out + 8, true), bc = view.getUint32(out + 12, true);
      const vp = view.getUint32(out + 20, true), vc = view.getUint32(out + 24, true);
      check(bc <= Math.min(budget.output, budget.text) &&
        vc <= Math.min(Math.floor(budget.output / 8), budget.edges, budget.nodes - 1) &&
        (resultKind === 2 || bc === 0) && (resultKind === 3 || vc === 0), 'typed result capacity exceeds policy');
      range(memory, bp, bc); range(memory, vp, vc, 8, 8);
      let bytes = 0, vectors = 0;
      const values = [];
      for (let i = 0; i < n; i++) {
        const a = ptr + i * 32, tag = view.getUint32(a, true);
        check(tag === parameters[i] && view.getUint32(a + 4, true) === 0, 'typed tag mismatch');
        if (tag === 1) {
          const x = view.getFloat64(a + 8, true);
          check(Number.isFinite(x), 'non-finite argument'); values.push(x);
        } else if (tag === 2) {
          const p = view.getUint32(a + 16, true), count = view.getUint32(a + 20, true);
          check(count <= budget.text - bytes, 'aggregate byte inputs exceed policy'); bytes += count;
          range(memory, p, count);
          values.push(new Uint8Array(memory, p, count).slice()); // No borrowed WASM views escape.
        } else {
          const p = view.getUint32(a + 24, true), count = view.getUint32(a + 28, true);
          check(count <= budget.edges - vectors, 'aggregate vector inputs exceed policy'); vectors += count;
          range(memory, p, count, 8, 8);
          const vector = new Float64Array(count);
          for (let j = 0; j < count; j++) {
            const x = view.getFloat64(p + j * 8, true);
            check(Number.isFinite(x), 'non-finite vector argument'); vector[j] = x;
          }
          values.push(vector);
        }
      }
      const result = fn(values, Object.freeze({bytesCapacity: bc, vectorCapacity: vc}));
      let resultBytes, resultVector;
      if (resultKind === 1) {
        check(typeof result === 'number' && Number.isFinite(result), 'invalid typed number result');
      } else if (resultKind === 2) {
        check(result instanceof Uint8Array && result.length <= bc, 'invalid typed bytes result');
        resultBytes = new Uint8Array(result.length); resultBytes.set(result);
      } else {
        check((result instanceof Float64Array || Array.isArray(result)) && result.length <= vc,
          'invalid typed vector result');
        resultVector = new Float64Array(result.length);
        for (let i = 0; i < resultVector.length; i++) {
          const x = result[i]; // Do not skip holes in sparse JS arrays.
          check(typeof x === 'number' && Number.isFinite(x), 'non-finite typed vector result');
          resultVector[i] = x;
        }
      }
      // Providers may cause memory.grow; old views would now be detached.
      const fresh = getInstance().exports.memory.buffer;
      range(fresh, out, 1, 32, 8); range(fresh, bp, bc); range(fresh, vp, vc, 8, 8);
      view = new DataView(fresh);
      check(view.getUint32(out + 8, true) === bp && view.getUint32(out + 12, true) === bc &&
        view.getUint32(out + 20, true) === vp && view.getUint32(out + 24, true) === vc,
        'caller-owned output descriptor changed');
      if (resultKind === 1) view.setFloat64(out, result, true);
      else if (resultKind === 2) {
        new Uint8Array(fresh, bp, resultBytes.length).set(resultBytes);
        view.setUint32(out + 16, resultBytes.length, true);
      } else {
        for (let i = 0; i < resultVector.length; i++) view.setFloat64(vp + i * 8, resultVector[i], true);
        view.setUint32(out + 28, resultVector.length, true);
      }
      return 0;
    } catch { return 1; }
  };
}
export function makeImports(module, providers, getInstance) {
  check(providers && typeof providers === 'object', 'host must export an explicit provider object');
  const catalog = readCatalog(module), imports = Object.create(null);
  for (const item of WebAssembly.Module.imports(module)) {
    const key = `${item.module}.${item.name}`;
    check(item.kind === 'function' && Object.hasOwn(providers, key), `host has not granted import ${key}`);
    const provider = providers[key], entry = catalog?.entries.get(key);
    if (catalog) check(entry?.wasm_import, `import missing from catalog: ${key}`);
    let implementation;
    if (entry?.kind === 7) {
      const sig = entry.signature;
      check(provider?.abi === 2 && Array.isArray(provider.parameters) &&
        provider.parameters.length === sig.parameters.length &&
        Array.from(provider.parameters).every((name, i) => name === typeNames[sig.parameters[i]]) &&
        provider.result === typeNames[sig.result] && typeof provider.call === 'function',
        `host signature mismatch for ${key}`);
      implementation = typedImport(provider, sig, catalog.limits, getInstance);
    } else {
      check(typeof provider === 'function', `numeric host function required for ${key}`);
      implementation = numericImport(provider, entry?.arity, getInstance);
    }
    imports[item.module] ??= Object.create(null); // __proto__/constructor are ordinary import names.
    imports[item.module][item.name] = implementation;
  }
  return imports;
}
