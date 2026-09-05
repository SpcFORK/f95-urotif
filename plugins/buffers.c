/* ABI-2 demo: binary/text and vector functions share one typed call contract. */
#include "../include/urotif_plugin_v2.h"
#include <string.h>
#include <math.h>
static int args_ok(const UrotifTypedArg*a,size_t n,size_t want,UrotifTypedResult*r){return r&&n==want&&(!n||a);}
int32_t urotif_ext_buffers_hex(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){
 static const char h[]="0123456789abcdef";
 if(!args_ok(a,n,1,r)||a[0].tag!=UROTIF_T_BYTES)return 1;
 if(a[0].length>r->capacity/2)return 2;
 for(size_t i=0;i<a[0].length;i++){r->bytes[2*i]=(uint8_t)h[a[0].bytes[i]>>4];r->bytes[2*i+1]=(uint8_t)h[a[0].bytes[i]&15];}
 r->length=2*a[0].length;return 0;
}
static int hex_digit(uint8_t x){if(x>='0'&&x<='9')return x-'0';if(x>='a'&&x<='f')return x-'a'+10;if(x>='A'&&x<='F')return x-'A'+10;return -1;}
int32_t urotif_ext_buffers_unhex(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){
 if(!args_ok(a,n,1,r)||a[0].tag!=UROTIF_T_BYTES||a[0].length%2)return 1;
 size_t count=a[0].length/2;if(count>r->capacity)return 2;
 for(size_t i=0;i<count;i++){int hi=hex_digit(a[0].bytes[2*i]),lo=hex_digit(a[0].bytes[2*i+1]);if(hi<0||lo<0)return 1;r->bytes[i]=(uint8_t)(hi*16+lo);}
 r->length=count;return 0;
}
int32_t urotif_ext_buffers_concat(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){
 if(!args_ok(a,n,2,r)||a[0].tag!=UROTIF_T_BYTES||a[1].tag!=UROTIF_T_BYTES)return 1;
 if(a[0].length>r->capacity||a[1].length>r->capacity-a[0].length)return 2;
 if(a[0].length)memcpy(r->bytes,a[0].bytes,a[0].length);
 if(a[1].length)memcpy(r->bytes+a[0].length,a[1].bytes,a[1].length);
 r->length=a[0].length+a[1].length;return 0;
}
int32_t urotif_ext_buffers_empty(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){
 if(!args_ok(a,n,0,r))return 1;r->length=0;return 0;
}
int32_t urotif_ext_buffers_prefix(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){
 if(!args_ok(a,n,2,r)||a[0].tag!=UROTIF_T_BYTES||a[1].tag!=UROTIF_T_NUMBER)return 1;
 double x=a[1].number;if(!isfinite(x)||x<0||x!=trunc(x)||x>(double)a[0].length)return 1;
 size_t count=(size_t)x;if(count>r->capacity)return 2;
 if(count)memcpy(r->bytes,a[0].bytes,count);r->length=count;return 0;
}
int32_t urotif_ext_buffers_affine(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){
 if(!args_ok(a,n,3,r)||a[0].tag!=UROTIF_T_VECTOR||a[1].tag!=UROTIF_T_NUMBER||a[2].tag!=UROTIF_T_NUMBER)return 1;
 if(a[0].count>r->vector_capacity)return 2;
 for(size_t i=0;i<a[0].count;i++){double v=a[0].vector[i]*a[1].number+a[2].number;if(!isfinite(v))return 1;r->vector[i]=v;}
 r->count=a[0].count;return 0;
}
int32_t urotif_ext_buffers_sum(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){
 if(!args_ok(a,n,1,r)||a[0].tag!=UROTIF_T_VECTOR)return 1;
 double x=0;for(size_t i=0;i<a[0].count;i++)x+=a[0].vector[i];if(!isfinite(x))return 1;r->number=x;return 0;
}
int32_t urotif_ext_buffers_dot(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){
 if(!args_ok(a,n,2,r)||a[0].tag!=UROTIF_T_VECTOR||a[1].tag!=UROTIF_T_VECTOR||a[0].count!=a[1].count)return 1;
 double x=0;for(size_t i=0;i<a[0].count;i++)x+=a[0].vector[i]*a[1].vector[i];if(!isfinite(x))return 1;r->number=x;return 0;
}
#ifndef UROTIF_STATIC_LINK
static const UrotifPluginSymbolV2 symbols[]={
 {"hex",1,{2},2,urotif_ext_buffers_hex},
 {"unhex",1,{2},2,urotif_ext_buffers_unhex},
 {"concat",2,{2,2},2,urotif_ext_buffers_concat},
 {"empty",0,{0},2,urotif_ext_buffers_empty},
 {"prefix",2,{2,1},2,urotif_ext_buffers_prefix},
 {"affine",3,{3,1,1},3,urotif_ext_buffers_affine},
 {"sum",1,{3},1,urotif_ext_buffers_sum},
 {"dot",2,{3,3},1,urotif_ext_buffers_dot}
};
static const UrotifPluginV2 plugin={2,sizeof(UrotifPluginV2),"buffers",sizeof(symbols)/sizeof(symbols[0]),symbols};
const UrotifPluginV2*urotif_plugin_v2(void){return &plugin;}
#endif
