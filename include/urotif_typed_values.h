#ifndef UROTIF_TYPED_VALUES_H
#define UROTIF_TYPED_VALUES_H
#include <stdint.h>
#include <stddef.h>
/* ABI 2 value kinds are NOT VM node tags. No VM handles cross the boundary. */
#define UROTIF_T_NUMBER 1u
#define UROTIF_T_BYTES  2u
#define UROTIF_T_VECTOR 3u
/* All payloads are read-only and borrowed for this call. Unused fields are zero/NULL.
   bytes need not be UTF-8 and may contain NUL. vector is an aligned array of
   finite doubles; it is not a serialized byte stream. reserved must be zero. */
typedef struct {
    uint32_t tag, reserved;
    double number;
    const uint8_t *bytes;
    size_t length;
    const double *vector;
    size_t count;
} UrotifTypedArg;
/* Host-owned output buffers. The callback must leave pointers/capacities
   unchanged. Only the declared result is used: set number, length, or count.
   It must not free/retain buffers, allocate a replacement, or write past caps.
   Length/count start at zero; number starts at NaN. Empty buffers are valid.
   Trusted native code only: no exceptions/unwinding, reentry into the running
   VM, retained/freed pointers, input writes, or floating-point environment changes.
   Validation does not sandbox native code, catch crashes, or enforce timeouts. */
typedef struct {
    double number;
    uint8_t *bytes;
    size_t capacity, length;
    double *vector;
    size_t vector_capacity, count;
} UrotifTypedResult;
typedef int32_t (*UrotifTypedFn)(const UrotifTypedArg *args, size_t argc,
                               UrotifTypedResult *result);
#endif
