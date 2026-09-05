/* Contract violations without out-of-bounds writes: these must be rejected. */
#include "../../include/urotif_plugin_v2.h"
#include <math.h>
int32_t urotif_ext_audit_missing(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;(void)r;return 0;}
int32_t urotif_ext_audit_nan(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;r->number=NAN;return 0;}
int32_t urotif_ext_audit_infinite(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;if(!r->vector_capacity)return 2;r->vector[0]=INFINITY;r->count=1;return 0;}
int32_t urotif_ext_audit_long_bytes(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;r->length=r->capacity+1;return 0;}
int32_t urotif_ext_audit_long_vector(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;r->count=r->vector_capacity+1;return 0;}
int32_t urotif_ext_audit_capacity(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;r->capacity++;return 0;}
int32_t urotif_ext_audit_vector_capacity(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;r->vector_capacity++;return 0;}
int32_t urotif_ext_audit_pointer(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;r->bytes=NULL;return 0;}
int32_t urotif_ext_audit_vector_pointer(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;r->vector=NULL;return 0;}
int32_t urotif_ext_audit_status(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;(void)n;(void)r;return 37;}
int32_t urotif_ext_audit_zero(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){(void)a;if(n)return 1;r->number=42;return 0;}
int32_t urotif_ext_audit_sum8(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){if(n!=8)return 1;double sum=0;for(size_t i=0;i<n;i++){if(a[i].tag!=1)return 1;sum+=a[i].number;}r->number=sum;return 0;}
#ifndef UROTIF_STATIC_LINK
static const UrotifPluginSymbolV2 symbols[]={
 {"missing",0,{0},1,urotif_ext_audit_missing},{"nan",0,{0},1,urotif_ext_audit_nan},
 {"infinite",0,{0},3,urotif_ext_audit_infinite},{"long_bytes",0,{0},2,urotif_ext_audit_long_bytes},
 {"long_vector",0,{0},3,urotif_ext_audit_long_vector},{"capacity",0,{0},2,urotif_ext_audit_capacity},
 {"vector_capacity",0,{0},3,urotif_ext_audit_vector_capacity},{"pointer",0,{0},2,urotif_ext_audit_pointer},
 {"vector_pointer",0,{0},3,urotif_ext_audit_vector_pointer},{"status",0,{0},1,urotif_ext_audit_status},
 {"zero",0,{0},1,urotif_ext_audit_zero},{"sum8",8,{1,1,1,1,1,1,1,1},1,urotif_ext_audit_sum8}
};
static const UrotifPluginV2 plugin={2,sizeof(UrotifPluginV2),"audit",sizeof(symbols)/sizeof(symbols[0]),symbols};
const UrotifPluginV2*urotif_plugin_v2(void){return &plugin;}
#endif
