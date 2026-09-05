import typed from '../../plugins/typed-host.mjs';
import numeric from '../../plugins/demo-host.mjs';
const descriptor = (result, call, parameters = []) => ({abi: 2, parameters, result, call});
const invalid = () => { throw Error('native descriptor contract violation, represented as a JS provider failure'); };
export default {
  ...typed, ...numeric,
  'audit.missing': descriptor('number', () => undefined),
  'audit.nan': descriptor('number', () => NaN),
  'audit.infinite': descriptor('vector', () => [Infinity]),
  'audit.long_bytes': descriptor('bytes', (_, cap) => new Uint8Array(cap.bytesCapacity + 1)),
  'audit.long_vector': descriptor('vector', (_, cap) => new Float64Array(cap.vectorCapacity + 1)),
  'audit.capacity': descriptor('bytes', invalid),
  'audit.vector_capacity': descriptor('vector', invalid),
  'audit.pointer': descriptor('bytes', invalid),
  'audit.vector_pointer': descriptor('vector', invalid),
  'audit.status': descriptor('number', invalid),
  'audit.zero': descriptor('number', () => 42),
  'audit.sum8': descriptor('number', values => values.reduce((a, b) => a + b, 0), Array(8).fill('number')),
};
