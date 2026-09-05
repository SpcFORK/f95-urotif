! Standalone F95 catalog implementation. Name matching is byte-exact, not
! Fortran's usual blank-padded equality ("int " must not resolve to "int").
subroutine uf_host_lookup(mode,module_id,name,id,arity,kind,status,message)
  use urotif_tables
  implicit none
  integer,intent(in)::mode,module_id
  character(*),intent(in)::name
  integer,intent(out)::id,arity,kind,status
  character(*),intent(out)::message
  integer::m,k,p,first,last
  id=-1;arity=0;kind=0;status=1;message='module or symbol not granted'
  if(mode<0.or.mode>2)return
  if(mode==0)then
    do k=0,module_count-1
      if(len(name)/=len_trim(module_names(k)))cycle
      if(name/=module_names(k))cycle
      id=k;status=0;message='';return
    end do
    return
  end if
  m=module_id;first=1;last=len(name)
  if(mode==2)then
    m=0;p=index(name,'.')
    if(p>0)then
      m=-1
      do k=0,module_count-1
        if(p-1/=len_trim(module_names(k)))cycle
        if(name(:p-1)/=module_names(k))cycle
        m=k;exit
      end do
      if(m<0)return
      first=p+1
    end if
  end if
  do k=0,symbol_count-1
    if(symbol_module(k)/=m)cycle
    if(last-first+1/=len_trim(symbol_names(k)))cycle
    if(name(first:last)/=symbol_names(k))cycle
    id=k;arity=symbol_arity(k);kind=symbol_kind(k);status=0;message='';return
  end do
end subroutine uf_host_lookup
