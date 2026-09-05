#ifndef UROTIF_FOUNDATION_H
#define UROTIF_FOUNDATION_H
#include <stdint.h>
#include <stddef.h>
#include "urotif_plugin.h"
#ifdef __cplusplus
extern "C" {
#endif
#define UROTIF_FOUNDATION_IR_ABI 2
/* Source-stable entries; wire size 32 bytes on the tested C/Fortran ABI.
   line/column are 1-based diagnostics. Language jumps use 1-based lines and
   0-based columns. next is an absolute 0-based IR index. All buffers are
   borrowed for the duration of emission. The caller supplies valid pointers. */
typedef struct {
    int32_t op, arg, next, cost, line, column;
    double number;
} UrotifFoundationInstruction;
typedef struct { int32_t offset, length; } UrotifFoundationText;
int32_t urotif_foundation_emit(
    int32_t abi, const UrotifFoundationInstruction *code, size_t count,
    int32_t entry, const uint8_t *text, size_t text_length,
    const UrotifFoundationText *spans, size_t span_count,
    const uint8_t *path, size_t path_length, int32_t format,
    uint8_t *error, size_t error_capacity);
#define UROTIF_FOUNDATION_EMIT_ABI 3
#define UROTIF_EMBED_SOURCE 1
#define UROTIF_STRICT_F95 2
/* v3 adds policy + optional normalized-source metadata; instruction ABI is IR2.
   limits[11] order: nodes, edges, text, output, stack, frames, returns,
   input-line, input, source, work. See urotif_limits.f90 for checked ranges. */
int32_t urotif_foundation_emit_v3(
    int32_t abi, const UrotifFoundationInstruction *code, size_t count,
    int32_t entry, const uint8_t *text, size_t text_length,
    const UrotifFoundationText *spans, size_t span_count,
    const uint8_t *path, size_t path_length, int32_t format,
    const int32_t limits[11], const uint8_t *source, size_t source_length,
    int32_t flags, uint8_t *error, size_t error_capacity);
/* Capsule recovery only: does not parse/decompile the target language. */
int32_t urotif_source_recover(const uint8_t *input, size_t input_length,
    const uint8_t *output, size_t output_length, uint8_t *error, size_t error_capacity);
/* format: 0 C99 source, 1 Rust source, 2 WASM + .wasm.rs, 3 Fortran source.
   Every emitted target also gets a .links.json capability/signature catalog. */
int32_t urotif_host_load(const uint8_t *path, size_t n, uint8_t *error, size_t cap);
int32_t urotif_host_declare(const uint8_t *signature, size_t n, uint8_t *error, size_t cap);
/* lookup mode: 0 module, 1 member of module ID, 2 qualified module.symbol.
   First lookup/catalog/emission seals the process-wide registry permanently. */
int32_t urotif_host_lookup(int32_t mode, int32_t module, const uint8_t *name, size_t n,
                         int32_t *id, int32_t *arity, int32_t *kind,
                         uint8_t *error, size_t cap);
int32_t urotif_host_call(int32_t id, const double *args, size_t n, double *result,
                       uint8_t *error, size_t cap);
int32_t urotif_host_catalog(uint8_t *out, size_t cap);
#ifdef __cplusplus
}
#endif
#endif
