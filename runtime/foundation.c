/* Portable C99 Foundation target kernel. Tables/import adapters are generated
   by the Rust backend from Fortran IR. All handles are checked arena indices. */
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <float.h>
#if FLT_RADIX != 2 || DBL_MANT_DIG != 53 || DBL_MAX_EXP != 1024
#error Foundation requires IEEE binary64 double precision
#endif
/* GENERATED_LIMITS */
/* GENERATED_TABLES */
typedef struct {int tag,start,len;double num;} V;
typedef struct {
 V nodes[NC];int edges[EC],stack[SC],bases[FC+1],kinds[FC+1],chars[256],refs[256],modules[32];
 int free_ids[NC],arrays[1024],strings[1024],ret_pc[RC],ret_depth[RC];
 unsigned char text[TC],output[OC];
 const unsigned char *input;size_t input_len,cursor;
 int nn,ne,nt,no,sp,depth,nfree,rp,pc,error,halted,jump,collections,stream_input,stream_output;
 size_t input_total;
 uint32_t steps;
} E;
static void fail(E *e,int code){if(!e->error)e->error=code;}
static int node(E*e,V v){int id;if(e->error)return 0;if(e->nfree)id=e->free_ids[--e->nfree];else{if(e->nn==NC){fail(e,2);return 0;}id=e->nn++;}e->nodes[id]=v;return id;}
static int number(E*e,double x,int integral){if(!isfinite(x)||(integral&&fabs(x)>9007199254740991.0)){fail(e,10);return 0;}V v={integral?4:1,0,0,x};return node(e,v);}
static int bytes(E*e,const unsigned char*b,int n){if(n<0||n>TC-e->nt){fail(e,2);return 0;}V v={2,e->nt,n,0};if(n)memcpy(e->text+e->nt,b,(size_t)n);e->nt+=n;return node(e,v);}
static int character(E*e,unsigned char c){if(e->chars[c])return e->chars[c];return e->chars[c]=bytes(e,&c,1);}
static int array(E*e,const int*a,int n){if(n<0||n>EC-e->ne){fail(e,2);return 0;}V v={3,e->ne,n,0};if(n)memcpy(e->edges+e->ne,a,(size_t)n*sizeof(int));e->ne+=n;return node(e,v);}
static void push(E*e,int id){if(e->error)return;if(e->sp==SC){fail(e,2);return;}e->stack[e->sp++]=id;}
static int pop(E*e){if(e->error)return 0;if(e->sp==e->bases[e->depth]){fail(e,1);return 0;}return e->stack[--e->sp];}
static void mark_id(int id,unsigned char*m,int*w,int*t){if(!m[id]){m[id]=1;w[(*t)++]=id;}}
static void collect(E*e){
 unsigned char *m=calloc((size_t)e->nn,1),*text=malloc(TC);int*w=malloc(NC*sizeof(int)),*edges=malloc(EC*sizeof(int));
 if(!m||!text||!w||!edges){free(m);free(text);free(w);free(edges);fail(e,2);return;}
 int head=0,tail=0,nt=0,ne=0;m[0]=1;
 for(int i=0;i<e->sp;i++)mark_id(e->stack[i],m,w,&tail);
 for(int i=0;i<256;i++){mark_id(e->chars[i],m,w,&tail);mark_id(e->refs[i],m,w,&tail);}
 for(int i=0;i<32;i++)mark_id(e->modules[i],m,w,&tail);
 for(int i=0;i<LITERAL_COUNT;i++){mark_id(e->arrays[i],m,w,&tail);mark_id(e->strings[i],m,w,&tail);}
 while(head<tail){V v=e->nodes[w[head++]];if(v.tag==3)for(int j=0;j<v.len;j++)mark_id(e->edges[v.start+j],m,w,&tail);}
 e->nfree=0;for(int id=1;id<e->nn;id++){if(!m[id]){e->free_ids[e->nfree++]=id;e->nodes[id]=(V){0,0,0,0};continue;}V v=e->nodes[id];
  if(v.tag==3){e->nodes[id].start=ne;if(v.len)memcpy(edges+ne,e->edges+v.start,(size_t)v.len*sizeof(int));ne+=v.len;}
  if(v.tag==2){e->nodes[id].start=nt;if(v.len)memcpy(text+nt,e->text+v.start,(size_t)v.len);nt+=v.len;}}
 if(nt)memcpy(e->text,text,(size_t)nt);if(ne)memcpy(e->edges,edges,(size_t)ne*sizeof(int));e->nt=nt;e->ne=ne;e->collections++;
 free(m);free(text);free(w);free(edges);
}
static int digit(unsigned char c){return c>='0'&&c<='9';}
static int decimal(const unsigned char*b,int n,double*out){
 while(n>0&&*b==' '){b++;n--;}while(n>0&&b[n-1]==' ')n--;if(n==0)return 0;
 int i=0,d=0;if(b[i]=='+'||b[i]=='-')i++;while(i<n&&digit(b[i])){i++;d++;}
 if(i<n&&b[i]=='.'){i++;while(i<n&&digit(b[i])){i++;d++;}}if(!d)return 0;
 if(i<n&&(b[i]=='e'||b[i]=='E')){i++;if(i<n&&(b[i]=='+'||b[i]=='-'))i++;int start=i;while(i<n&&digit(b[i]))i++;if(i==start)return 0;}
 if(i!=n)return 0;char *s=malloc((size_t)n+1);if(!s)return 0;memcpy(s,b,(size_t)n);s[n]=0;*out=strtod(s,NULL);free(s);return isfinite(*out);
}
static double num(E*e,int id,int convert,int error){V v=e->nodes[id];if(v.tag==1||v.tag==4)return v.num;double x;if(convert&&v.tag==2&&decimal(e->text+v.start,v.len,&x))return x;fail(e,error);return 0;}
static void buf(E*e,unsigned char*out,int*n,const unsigned char*b,int k){if(e->error)return;if(k<0||k>OC-*n){fail(e,2);return;}if(k)memcpy(out+*n,b,(size_t)k);*n+=k;if(e->stream_output&&out==e->output){if(k&&fwrite(b,1,(size_t)k,stdout)!=(size_t)k)fail(e,9);if(fflush(stdout))fail(e,9);}}
static void lit(E*e,unsigned char*out,int*n,const char*s){buf(e,out,n,(const unsigned char*)s,(int)strlen(s));}
static void numtext(double x,char*out){
 if(x==0){strcpy(out,"0");return;}
 if(fabs(x)>=1e-12&&fabs(x)<1e15){snprintf(out,96,"%.15f",x);int n=(int)strlen(out);while(n&&out[n-1]=='0')out[--n]=0;if(n&&out[n-1]=='.')out[--n]=0;}
 else{char tmp[96],mantissa[96];snprintf(tmp,sizeof(tmp),"%.15E",x);char*p=strchr(tmp,'E');int exp=atoi(p+1);*p=0;strcpy(mantissa,tmp);snprintf(out,96,"%sE%c%03d",mantissa,exp<0?'-':'+',abs(exp));}
}
static void repr(E*e,int id,unsigned char*out,int*n,int quote,int depth){
 if(e->error)return;if(depth>FC){fail(e,2);return;}V v=e->nodes[id];char tmp[96];
 switch(v.tag){case 0:lit(e,out,n,"?");break;case 1:case 4:numtext(v.num,tmp);lit(e,out,n,tmp);break;
 case 2:if(quote)lit(e,out,n,"'");for(int i=0;i<v.len&&!e->error;i++){unsigned char c=e->text[v.start+i];if(quote){if(c=='\n'){lit(e,out,n,"\\n");continue;}if(c=='\r'){lit(e,out,n,"\\r");continue;}if(c=='\t'){lit(e,out,n,"\\t");continue;}if(c=='\\'||c=='\'')lit(e,out,n,"\\");}buf(e,out,n,&c,1);}if(quote)lit(e,out,n,"'");break;
 case 3:lit(e,out,n,"[");for(int i=0;i<v.len&&!e->error;i++){if(i)lit(e,out,n,", ");repr(e,e->edges[v.start+i],out,n,1,depth+1);}lit(e,out,n,"]");break;
 case 5:case 6:snprintf(tmp,sizeof(tmp),"<%s:%d>",v.tag==5?"module":"external",v.start);lit(e,out,n,tmp);break;
 default:fail(e,4);}
}
static void printnode(E*e,int id){V v=e->nodes[id];if(v.tag==2){buf(e,e->output,&e->no,e->text+v.start,v.len);return;}if(v.tag==1||v.tag==4){char text[96];numtext(v.num,text);lit(e,e->output,&e->no,text);return;}unsigned char*b=malloc(OC);if(!b){fail(e,2);return;}int n=0;repr(e,id,b,&n,0,0);buf(e,e->output,&e->no,b,n);free(b);}
static int join(E*e,int id,int stringify){V v=e->nodes[id];if(v.tag!=3){fail(e,4);return 0;}unsigned char*b=malloc(OC);if(!b){fail(e,2);return 0;}int n=0;for(int i=0;i<v.len&&!e->error;i++){int x=e->edges[v.start+i];V a=e->nodes[x];if(stringify)repr(e,x,b,&n,0,0);else{if(a.tag!=2){fail(e,4);break;}buf(e,b,&n,e->text+a.start,a.len);}}int r=bytes(e,b,n);free(b);return r;}
static int equal(E*e,int ai,int bi,int*work,int depth){if((*work)--<=0){fail(e,2);return 0;}if(ai==bi)return 1;if(depth>FC){fail(e,2);return 0;}V a=e->nodes[ai],b=e->nodes[bi];if((a.tag==1||a.tag==4)&&(b.tag==1||b.tag==4))return a.num==b.num;if(a.tag!=b.tag)return 0;
 switch(a.tag){case 0:return 1;case 2:return a.len==b.len&&!memcmp(e->text+a.start,e->text+b.start,(size_t)a.len);case 3:if(a.len!=b.len)return 0;for(int i=0;i<a.len;i++)if(!equal(e,e->edges[a.start+i],e->edges[b.start+i],work,depth+1))return 0;return 1;case 5:case 6:return a.start==b.start;default:return 0;}}
static int closeframe(E*e,int kind){if(!e->depth||e->kinds[e->depth]!=kind){fail(e,3);return 0;}int base=e->bases[e->depth];int id=array(e,e->stack+base,e->sp-base);e->sp=base;e->depth--;return id;}
static void name(E*e,int id,char*out){V v=e->nodes[id];int n=0;if(v.tag==2){if(v.len>127){fail(e,11);return;}memcpy(out,e->text+v.start,(size_t)v.len);n=v.len;}else if(v.tag==3){for(int i=0;i<v.len;i++){V a=e->nodes[e->edges[v.start+i]];if(a.tag!=2||a.len>127-n){fail(e,11);return;}memcpy(out+n,e->text+a.start,(size_t)a.len);n+=a.len;}}else{fail(e,11);return;}out[n]=0;for(int i=0;i<n;i++)if(!out[i]||(unsigned char)out[i]>127){fail(e,11);return;}}
static int refid(E*e,int id){if(id<0||id>=SYMBOL_COUNT){fail(e,11);return 0;}if(e->refs[id])return e->refs[id];V v={6,id,symbols[id].arity,(double)symbols[id].kind};return e->refs[id]=node(e,v);}
static int reference(E*e,int module,const char*name){for(int i=0;i<SYMBOL_COUNT;i++)if(symbols[i].module==module&&!strcmp(symbols[i].name,name))return refid(e,i);fail(e,11);return 0;}
static int resolve(E*e,char*s){char*p=strchr(s,'.');if(!p)return reference(e,0,s);*p=0;for(int m=0;m<MODULE_COUNT;m++)if(!strcmp(modules[m],s))return reference(e,m,p+1);fail(e,11);return 0;}
/* TYPED_RUNTIME */
static void apply(E*e,int ref,const int*args,int n){V r=e->nodes[ref];if(r.tag!=6||r.len!=n||n<0||n>8){fail(e,12);return;}if((int)r.num==7){apply_typed(e,r.start,args,n);return;}int result=0;double x=0,values[8];switch((int)r.num){
 case 1:case 2:x=num(e,args[0],1,12);if((int)r.num==1){if(fabs(x)>9007199254740991.0){fail(e,12);return;}result=number(e,trunc(x),1);}else result=number(e,x,0);break;
 case 3:{unsigned char*b=malloc(OC);if(!b){fail(e,2);return;}int len=0;repr(e,args[0],b,&len,0,0);result=bytes(e,b,len);free(b);break;}
 case 4:{V a=e->nodes[args[0]];if(a.tag!=2&&a.tag!=3){fail(e,12);return;}result=number(e,(double)a.len,1);break;}
 case 0:x=NAN;for(int i=0;i<n;i++)values[i]=num(e,args[i],0,12);if(e->error)return;if(foreign_call(r.start,values,(size_t)n,&x)||!isfinite(x)){fail(e,12);return;}result=number(e,x,0);break;
 default:fail(e,12);return;}push(e,result);
}
static int coordinate(E*e,double y,double x,int error){if(!isfinite(x)||!isfinite(y)||y<1||y>LINE_COUNT||x<0||x>SOURCE_CAP||x!=trunc(x)||y!=trunc(y)){fail(e,error);return 0;}int row=(int)y-1,col=(int)x;if(col>lines[row].len)col=lines[row].len;return lines[row].start+col;}
static void at(E*e,int next){int sym=pop(e);V v=e->nodes[sym];if(e->error)return;if(v.tag==6){int args[8];if(v.len>8){fail(e,12);return;}for(int i=v.len-1;i>=0;i--)args[i]=pop(e);if(!e->error)apply(e,sym,args,v.len);return;}
 if(v.tag!=2||v.len!=1){fail(e,6);return;}unsigned char c=e->text[v.start];if(c=='h'){e->halted=1;return;}if(c=='R'){if(!e->rp){fail(e,13);return;}e->rp--;if(e->ret_depth[e->rp]!=e->depth){fail(e,13);return;}e->jump=e->ret_pc[e->rp];return;}
 if(c=='x'||c=='o'||c=='t'){int n=c=='t'?3:2;if(e->sp-e->bases[e->depth]<n){fail(e,1);return;}int a=e->stack[e->sp-n],b=e->stack[e->sp-n+1];if(c=='o')push(e,a);else if(c=='x'){e->stack[e->sp-2]=b;e->stack[e->sp-1]=a;}else{e->stack[e->sp-3]=b;e->stack[e->sp-2]=e->stack[e->sp-1];e->stack[e->sp-1]=a;}return;}
 if(c=='d'){int id=number(e,(double)(e->sp-e->bases[e->depth]),1);push(e,id);return;}
 int arg=pop(e);if(e->error)return;v=e->nodes[arg];char text[128]={0};int x=0;
 if(c=='b'){double count=num(e,arg,0,4);if(e->error)return;if(count<0||count!=trunc(count)){fail(e,4);return;}if(count>e->sp-e->bases[e->depth]){fail(e,1);return;}int n=(int)count;int id=array(e,e->stack+e->sp-n,n);if(e->error)return;e->sp-=n;push(e,id);return;}
 switch(c){case 'p':case 'P':if(v.tag==3){for(int i=0;i<v.len&&!e->error;i++){x=e->edges[v.start+i];if(e->nodes[x].tag!=2){fail(e,4);return;}printnode(e,x);}}else if(v.tag==2)printnode(e,arg);else{fail(e,4);return;}if(c=='P')lit(e,e->output,&e->no,"\n");break;
 case 'S':x=join(e,arg,0);push(e,x);break;
 case 's':{unsigned char*b=malloc(OC);if(!b){fail(e,2);return;}int n=0;repr(e,arg,b,&n,0,0);x=bytes(e,b,n);free(b);push(e,x);break;}
 case 'i':name(e,arg,text);if(e->error)return;for(int i=0;i<MODULE_COUNT;i++)if(!strcmp(modules[i],text)){V m={5,i,0,0};x=e->modules[i];if(!x)x=e->modules[i]=node(e,m);push(e,x);return;}fail(e,11);break;
 case 'G':case 'r':name(e,arg,text);if(e->error)return;x=c=='G'?reference(e,0,text):resolve(e,text);push(e,x);break;
 case 'g':if(v.tag!=3||v.len!=2){fail(e,11);return;}{V m=e->nodes[e->edges[v.start]];if(m.tag!=5){fail(e,11);return;}name(e,e->edges[v.start+1],text);if(e->error)return;x=reference(e,m.start,text);push(e,x);}break;
 case 'a':case 'C':if(v.tag!=3||v.len<1||v.len>9){fail(e,12);return;}x=e->edges[v.start];if(c=='C'){name(e,x,text);if(e->error)return;x=reference(e,0,text);}if(!e->error)apply(e,x,e->edges+v.start+1,v.len-1);break;
 case 'k':if(v.tag!=3||v.len!=2){fail(e,13);return;}{double y=num(e,e->edges[v.start],1,13),xx=num(e,e->edges[v.start+1],1,13);int pc=coordinate(e,y,xx,13);if(e->error)return;if(e->rp==RC){fail(e,13);return;}e->ret_pc[e->rp]=next;e->ret_depth[e->rp]=e->depth;e->rp++;e->jump=pc;}break;
 default:fail(e,6);}
}
static int literal(E*e,int pool,int text){int id=text?e->strings[pool]:e->arrays[pool];if(id)return id;if(text)id=bytes(e,literals[pool].data,literals[pool].len);else{int ids[2048];for(int i=0;i<literals[pool].len;i++)ids[i]=character(e,literals[pool].data[i]);id=array(e,ids,literals[pool].len);}if(text)e->strings[pool]=id;else e->arrays[pool]=id;return id;}
static int readnode(E*e){if(e->stream_input){unsigned char*b=malloc((size_t)LC+2);if(!b){fail(e,2);return 0;}int n=0,c=EOF,any=0;while((c=getchar())!=EOF){any=1;e->input_total++;if(e->input_total>IC){fail(e,9);break;}if(c=='\n')break;if(n>=LC+1){fail(e,9);break;}b[n++]=(unsigned char)c;}if(ferror(stdin)||(!any&&c==EOF))fail(e,9);if(n>0&&b[n-1]=='\r')n--;if(n>LC)fail(e,9);int id=e->error?0:bytes(e,b,n);free(b);return id;}if(e->cursor>=e->input_len){fail(e,9);return 0;}size_t start=e->cursor;while(e->cursor<e->input_len&&e->input[e->cursor]!='\n')e->cursor++;size_t end=e->cursor;if(e->cursor<e->input_len)e->cursor++;if(end>start&&e->input[end-1]=='\r')end--;if(end-start>LC){fail(e,9);return 0;}return bytes(e,e->input+start,(int)(end-start));}
static int execute(E*e,uint32_t fuel){while(!e->error){if(e->pc<0||e->pc>=CODE_COUNT){fail(e,7);break;}I i=code[e->pc];if(!i.op)break;if(i.op==3){e->pc=i.next;continue;}
 int edge_need=e->sp;if(i.op==24&&literals[i.arg].len>edge_need)edge_need=literals[i.arg].len;
 if(e->nn-e->nfree>NC-16||e->ne>EC-(EC/2<edge_need?EC/2:edge_need)-16||e->nt>TC-(TC/2<OC?TC/2:OC)-16)collect(e);if(e->error)break;
 int peak=(i.op==23||i.op==25)?i.cost-4:i.cost-2;int min_peak=(i.op==23||i.op==25)?2:1;if(peak<min_peak)peak=min_peak;
 if(i.op>=23&&i.op<=26&&(fuel-e->steps<(uint32_t)i.cost||e->depth==FC||e->sp+peak>SC)){i.arg=i.op==26?1:0;i.op=5;i.next=e->pc+1;i.cost=1;}
 if((uint32_t)i.cost>fuel-e->steps){fail(e,8);break;}e->steps+=(uint32_t)i.cost;int next=i.next,a,b,x;double xx,yy,zz;
 switch(i.op){case 27:case 1:x=character(e,(unsigned char)i.arg);push(e,x);break;case 2:case 21:break;
 case 4:if(i.arg>255){fail(e,3);break;}x=character(e,i.arg=='n'?'\n':(unsigned char)i.arg);push(e,x);break;
 case 5:if(e->depth==FC){fail(e,2);break;}e->depth++;e->bases[e->depth]=e->sp;e->kinds[e->depth]=i.arg;break;
 case 6:x=closeframe(e,i.arg);if(!e->error&&i.arg==1){a=join(e,x,1);xx=num(e,a,1,4);x=number(e,xx,0);}push(e,x);break;
 case 7:x=pop(e);push(e,x);push(e,x);break;case 8:pop(e);break;
 case 9:case 10:case 11:case 12:a=pop(e);b=pop(e);if(e->error)break;{V av=e->nodes[a],bv=e->nodes[b];if(i.op==9&&av.tag==2&&bv.tag==2){if(av.len+bv.len>OC){fail(e,2);break;}unsigned char*t=malloc((size_t)(av.len+bv.len)+1);if(!t){fail(e,2);break;}memcpy(t,e->text+av.start,(size_t)av.len);memcpy(t+av.len,e->text+bv.start,(size_t)bv.len);x=bytes(e,t,av.len+bv.len);free(t);}else{yy=num(e,a,0,4);xx=num(e,b,0,4);if(e->error)break;if(i.op==12&&yy==0){fail(e,10);break;}zz=i.op==9?xx+yy:i.op==10?xx-yy:i.op==11?xx*yy:xx/yy;x=number(e,zz,av.tag==4&&bv.tag==4&&i.op!=12);}push(e,x);}break;
 case 13:a=pop(e);xx=num(e,a,0,4);x=number(e,-xx,e->nodes[a].tag==4);push(e,x);break;
 case 14:a=pop(e);if(!e->error)printnode(e,a);break;
 case 15:a=pop(e);if(e->error)break;{V v=e->nodes[a];if(v.tag!=3){fail(e,4);break;}for(int j=0;j<v.len;j++)push(e,e->edges[v.start+j]);}break;
 case 16:a=pop(e);b=pop(e);if(e->error)break;xx=num(e,a,1,5);if(e->error)break;if(fabs(xx)>2147483647.0){fail(e,5);break;}{int key=(int)xx;V v=e->nodes[b];if(v.tag!=2&&v.tag!=3){fail(e,5);break;}x=0;if(key>=0&&key<v.len){if(v.tag==3)x=e->edges[v.start+key];else if(v.tag==2)x=character(e,e->text[v.start+key]);else fail(e,5);}push(e,x);}break;
 case 17:at(e,next);break;case 18:x=readnode(e);push(e,x);break;
 case 19:case 20:a=pop(e);b=pop(e);xx=num(e,a,1,7);yy=num(e,b,1,7);if(e->error)break;x=1;if(i.op==20){a=pop(e);b=pop(e);if(e->error)break;int work=WORK;x=equal(e,a,b,&work,0);}if(x)next=coordinate(e,yy,xx,7);break;
 case 22:fail(e,6);break;case 23:x=refid(e,i.arg);push(e,x);break;case 24:case 25:x=literal(e,i.arg,i.op==25);push(e,x);break;
 case 26:x=number(e,i.value,0);push(e,x);break;default:fail(e,7);}
 if(e->error||e->halted)break;if(e->jump>=0){next=e->jump;e->jump=-1;}e->pc=next;
 }if(!e->error&&e->depth)fail(e,3);return e->error;}
static int utf8_width(const unsigned char*b,int at,int n){int c=b[at],need=c>=194&&c<=223?2:c>=224&&c<=239?3:c>=240&&c<=244?4:0;if(c<128)return 1;if(!need)return -1;int lo=c==224?160:c==240?144:128,hi=c==237?159:c==244?143:191;for(int k=1;k<need;k++){if(at+k>=n||b[at+k]<lo||b[at+k]>hi)return -k;lo=128;hi=191;}return need;}
static void json_bytes(const unsigned char*b,int n){putchar('"');for(int i=0;i<n;){unsigned char c=b[i];if(c=='"'||c=='\\'){putchar('\\');putchar(c);i++;}else if(c<32){printf("\\u%04x",c);i++;}else if(c<128){putchar(c);i++;}else{int w=utf8_width(b,i,n);if(w>0){fwrite(b+i,1,(size_t)w,stdout);i+=w;}else{fputs("\\ufffd",stdout);i-=w;}}}putchar('"');}
static void json_hex(const unsigned char*b,int n){static const char hex[]="0123456789abcdef";putchar('"');for(int i=0;i<n;i++){putchar(hex[b[i]>>4]);putchar(hex[b[i]&15]);}putchar('"');}
int main(int argc,char**argv){uint32_t fuel=1000000;int repeat=1,json=0,stream=0;for(int i=1;i<argc;i++){if(!strcmp(argv[i],"--json"))json=1;else if(!strcmp(argv[i],"--stream"))stream=1;else if(!strcmp(argv[i],"--fuel")&&i+1<argc){char*end;unsigned long n=strtoul(argv[++i],&end,10);if(*end||!n||n>2147483647UL)return 2;fuel=(uint32_t)n;}else if(!strcmp(argv[i],"--repeat")&&i+1<argc){char*end;long n=strtol(argv[++i],&end,10);if(*end||n<1||n>10000)return 2;repeat=(int)n;}else return 2;}
 if(stream&&(json||repeat>1))return 2;
 unsigned char*input=malloc(USES_INPUT&&repeat>1?IC+1:1);if(!input)return 2;size_t n=USES_INPUT&&repeat>1?fread(input,1,IC+1,stdin):0;if(ferror(stdin)){free(input);return 2;}if(n>IC){free(input);return 2;}E*e=NULL;int status=0;
 for(int k=0;k<repeat;k++){free(e);e=calloc(1,sizeof(E));if(!e){free(input);return 2;}e->nn=1;e->pc=ENTRY;e->jump=-1;e->input=input;e->input_len=n;e->stream_input=repeat==1;e->stream_output=stream;status=execute(e,fuel);}
 I last=code[e->pc>=0&&e->pc<CODE_COUNT?e->pc:0];if(json){printf("{\"status\":%d,\"output\":",status);json_bytes(e->output,e->no);fputs(",\"output_hex\":",stdout);json_hex(e->output,e->no);printf(",\"steps\":%u,\"line\":%d,\"column\":%d,\"collections\":%d,\"stack_depth\":%d}\n",e->steps,last.line,last.col,e->collections,e->sp);}else{if(!stream)fwrite(e->output,1,(size_t)e->no,stdout);if(status)fprintf(stderr,"Foundation P%03d at %d:%d\n",status,last.line,last.col);}free(e);free(input);return status?1:0;
}
