#include "../include/urotif_plugin.h"
#include <math.h>
int32_t urotif_ext_demo_cube(const double *a, size_t n, double *out) {
    if (n != 1 || !a || !out) return 1;
    *out = a[0] * a[0] * a[0];
    return isfinite(*out) ? 0 : 1;
}
int32_t urotif_ext_demo_sum3(const double *a, size_t n, double *out) {
    if (n != 3 || !a || !out) return 1;
    *out = a[0] + a[1] + a[2];
    return isfinite(*out) ? 0 : 1;
}
int32_t urotif_ext_demo_affine(const double *a, size_t n, double *out) {
    if (n != 3 || !a || !out) return 1;
    *out = a[0] * a[1] + a[2];
    return isfinite(*out) ? 0 : 1;
}
#ifndef UROTIF_STATIC_LINK
static const UrotifPluginSymbol symbols[] = {
    {"cube", 1, urotif_ext_demo_cube},
    {"sum3", 3, urotif_ext_demo_sum3},
    {"affine", 3, urotif_ext_demo_affine}
};
static const UrotifPlugin plugin = {UROTIF_PLUGIN_ABI, "demo", 3, symbols};
const UrotifPlugin *urotif_plugin_v1(void) { return &plugin; }
#endif
