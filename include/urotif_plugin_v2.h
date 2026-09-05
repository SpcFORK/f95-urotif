#ifndef UROTIF_PLUGIN_V2_H
#define UROTIF_PLUGIN_V2_H
#include "urotif_typed_values.h"
#ifdef __cplusplus
extern "C" {
#endif
#define UROTIF_PLUGIN_ABI_V2 2u
#define UROTIF_V2_MAX_ARITY 8u
/* New descriptor/entry name: ABI-1 descriptors are not reinterpreted. */
typedef struct {
    const char *name;
    uint32_t arity;
    uint32_t parameters[8]; /* first arity kinds are 1..3; remainder zero */
    uint32_t result;        /* one kind, 1..3 */
    UrotifTypedFn call;
} UrotifPluginSymbolV2;
typedef struct {
    uint32_t abi;
    uint32_t struct_size;   /* sizeof(UrotifPluginV2) on the native platform */
    const char *module;
    size_t count;           /* 1..128 immutable descriptors */
    const UrotifPluginSymbolV2 *symbols;
} UrotifPluginV2;
const UrotifPluginV2 *urotif_plugin_v2(void);
/* Also export urotif_ext_MODULE_SYMBOL with the UrotifTypedFn signature for
   static native linking. WASM uses MODULE.SYMBOL plus an embedded typed catalog.
   Return zero on success, nonzero on service/domain/capacity failure.
   No exceptions/panics may cross this ABI; preserve floating-point state.
   A native plugin is trusted code, NOT sandboxed by these buffer checks. */
#ifdef __cplusplus
}
#endif
#endif
