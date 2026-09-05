#ifndef UROTIF_BACKEND_H
#define UROTIF_BACKEND_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define UROTIF_IR_ABI 1
/* No Fortran CHARACTER descriptors or compiler-specific name mangling cross
 * this interface. All PC, text, and register indices are zero-based. */
typedef struct {
    int32_t op, arg, line, column;
    double number;
} UrotifInstruction;
typedef struct {
    int32_t offset, length;
} UrotifTextSpan;
/* format 0 = binary WASM, 1 = WAT. Borrowed buffers remain caller-owned.
 * error is a NUL-terminated diagnostic (when capacity > 0).
 * Return 0 = success, 1 = failure, 2 = contained Rust panic.
 * Caller must provide valid/aligned buffers and no overlapping error buffer.
 * Counts: 1..8192 instructions, <=1024 texts, <=2048 bytes/text,
 * <=2097152 text bytes, 1..4096 UTF-8 path bytes. Text constants are interned.
 * Fortran remains the executable's main program. */
int32_t urotif_backend_emit(
    int32_t abi, const UrotifInstruction *code, size_t count, int32_t entry,
    const uint8_t *text_bytes, size_t byte_count,
    const UrotifTextSpan *texts, size_t text_count,
    const uint8_t *path, size_t path_length, int32_t format,
    uint8_t *error, size_t error_capacity);
#ifdef __cplusplus
}
#endif
#endif
