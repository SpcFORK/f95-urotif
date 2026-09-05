// Explicit example grants for both generations of the foreign interface.
import numbers from './demo-host.mjs';
import typed from './typed-host.mjs';
export default {...numbers, ...typed};
