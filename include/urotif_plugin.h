#ifndef UROTIF_PLUGIN_H
#define UROTIF_PLUGIN_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
#define UROTIF_PLUGIN_ABI 1u
#define UROTIF_MAX_ARITY 8u
/* Trusted native plugin ABI. No exceptions/panics may cross this boundary.
   Arguments are borrowed for this call only. Write exactly one result.
   Return 0 on success; nonzero on domain/service failure. Preserve the
   caller's floating-point environment. Do not retain the borrowed pointers. */
typedef int32_t (*UrotifNumberFn)(const double *args, size_t argc, double *result);
typedef struct {
    const char *name;       /* immutable NUL-terminated ASCII identifier */
    uint32_t arity;         /* 0..8; all arguments and result are f64 */
    UrotifNumberFn call;
} UrotifPluginSymbol;
typedef struct {
    uint32_t abi;
    const char *module;
    size_t count;           /* 1..128 */
    const UrotifPluginSymbol *symbols;
} UrotifPlugin;
/* Export this entry point from a shared library. Its descriptor, strings,
   table and function pointers must remain valid until process termination. */
const UrotifPlugin *urotif_plugin_v1(void);
/* To link a transpiled native program, also export each function with the
   name urotif_ext_MODULE_SYMBOL and the UrotifNumberFn signature. WASM uses
   imports MODULE.SYMBOL with the same pointer/count/result/status convention.
   Native plugins are NOT sandboxed. Loading one executes trusted native code. */
#ifdef __cplusplus
}
#endif
#endif
