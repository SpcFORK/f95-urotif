/* Generic ABI-2 marshalling. New plugin functions need no new runtime cases. */
static void apply_typed(E*e,int slot,const int*ids,int n){
 UrotifTypedArg a[8];memset(a,0,sizeof(a));size_t nb=0,nv=0;
 if(slot<0||slot>=SYMBOL_COUNT||n!=symbols[slot].arity||n<0||n>8){fail(e,12);return;}
 for(int i=0;i<n;i++){
  V v=e->nodes[ids[i]];a[i].tag=typed_parameters[slot][i];
  switch(a[i].tag){
   case 1:if(v.tag!=1&&v.tag!=4){fail(e,12);return;}a[i].number=v.num;break;
   case 2:if(v.tag!=2){fail(e,12);return;}if((size_t)v.len>TC-nb){fail(e,2);return;}nb+=(size_t)v.len;a[i].bytes=v.len?e->text+v.start:NULL;a[i].length=(size_t)v.len;break;
   case 3:if(v.tag!=3){fail(e,12);return;}if((size_t)v.len>EC-nv){fail(e,2);return;}nv+=(size_t)v.len;for(int j=0;j<v.len;j++){V x=e->nodes[e->edges[v.start+j]];if(x.tag!=1&&x.tag!=4){fail(e,12);return;}}a[i].count=(size_t)v.len;break;
   default:fail(e,12);return;
  }
 }
 int result_type=typed_result_kind[slot];size_t bc=0,vc=0;
 if(result_type==2)bc=(size_t)(TC-e->nt<OC?TC-e->nt:OC);
 if(result_type==3){int available=NC-e->nn+e->nfree-1;if(available<0)available=0;vc=(size_t)available;if(vc>(size_t)(EC-e->ne))vc=(size_t)(EC-e->ne);if(vc>OC/8)vc=OC/8;}
 double*packed=calloc(nv?nv:1,sizeof(double));unsigned char*rb=calloc(bc?bc:1,1);double*rv=calloc(vc?vc:1,sizeof(double));
 if(!packed||!rb||!rv){free(packed);free(rb);free(rv);fail(e,2);return;}
 size_t at=0;for(int i=0;i<n;i++)if(a[i].tag==3){V v=e->nodes[ids[i]];a[i].vector=v.len?packed+at:NULL;for(int j=0;j<v.len;j++)packed[at++]=e->nodes[e->edges[v.start+j]].num;}
 UrotifTypedResult out={NAN,rb,bc,0,rv,vc,0};
 int status=foreign_typed(slot,a,(size_t)n,&out);
 if(out.bytes!=rb||out.vector!=rv||out.capacity!=bc||out.vector_capacity!=vc||status||out.length>bc||out.count>vc){fail(e,12);goto cleanup;}
 int id=0;
 if(result_type==1){if(!isfinite(out.number)){fail(e,12);goto cleanup;}id=number(e,out.number,0);}
 else if(result_type==2){id=bytes(e,rb,(int)out.length);}
 else if(result_type==3){
  for(size_t j=0;j<out.count;j++)if(!isfinite(rv[j])){fail(e,12);goto cleanup;}
  int*children=malloc((out.count?out.count:1)*sizeof(int));if(!children){fail(e,2);goto cleanup;}
  for(size_t j=0;j<out.count;j++)children[j]=number(e,rv[j],0);
  if(!e->error)id=array(e,children,(int)out.count);free(children);
 }else{fail(e,12);goto cleanup;}
 push(e,id);
cleanup:free(packed);free(rb);free(rv);
}
