module urotif_foundation_bridge
  use, intrinsic :: iso_c_binding
  use urotif_foundation_ir
  implicit none
  type,bind(C)::foundation_wire
    integer(c_int32_t)::op,arg,next,cost,line,column
    real(c_double)::number
  end type
  type,bind(C)::literal_wire
    integer(c_int32_t)::offset,length
  end type
  interface
    function source_recover(input,input_len,output,output_len,err,cap) &
        bind(C,name='urotif_source_recover') result(status)
      import c_char,c_size_t,c_int32_t
      character(kind=c_char),intent(in)::input(*),output(*)
      integer(c_size_t),value::input_len,output_len,cap
      character(kind=c_char),intent(out)::err(*)
      integer(c_int32_t)::status
    end function
    function emit_foundation(abi,code,count,entry,bytes,byte_count,spans,text_count,path,path_len,format, &
        limits,source,source_len,flags,err,cap) &
        bind(C,name='urotif_foundation_emit_v3') result(status)
      import c_int32_t,c_size_t,c_char,foundation_wire,literal_wire
      integer(c_int32_t),value::abi,entry,format,flags
      integer(c_int32_t),intent(in)::limits(*)
      type(foundation_wire),intent(in)::code(*)
      integer(c_size_t),value::count,byte_count,text_count,path_len,source_len,cap
      character(kind=c_char),intent(in)::bytes(*),path(*),source(*)
      type(literal_wire),intent(in)::spans(*)
      character(kind=c_char),intent(out)::err(*)
      integer(c_int32_t)::status
    end function
  end interface
contains
  subroutine foundation_recover(path,output,d)
    character(*),intent(in)::path,output
    type(diagnostic),intent(inout)::d
    character(kind=c_char)::a(len(path)),b(len(output)),err(4096)
    character(4096)::message
    integer(c_int32_t)::status
    integer::i
    do i=1,len(path)
      a(i)=char(iachar(path(i:i)),kind=c_char)
    end do
    do i=1,len(output)
      b(i)=char(iachar(output(i:i)),kind=c_char)
    end do
    err=c_null_char
    status=source_recover(a,int(len(path),c_size_t),b,int(len(output),c_size_t),err,int(size(err),c_size_t))
    if(status/=0)then
      message=''
      do i=1,size(err)
        if(err(i)==c_null_char)exit
        message(i:i)=achar(iachar(err(i)))
      end do
      call fail(d,'source recovery: '//trim(message),1,1)
    end if
  end subroutine
  subroutine foundation_emit(p,path,format,d,flags)
    type(foundation_program),intent(in)::p
    character(*),intent(in)::path
    integer,intent(in)::format
    integer,optional,intent(in)::flags
    type(diagnostic),intent(inout)::d
    type(foundation_wire),allocatable::code(:)
    type(literal_wire),allocatable::spans(:)
    character(kind=c_char),allocatable::bytes(:),cpath(:),source(:)
    character(kind=c_char)::err(4096)
    character(4096)::message
    integer::i,j,n,at,pathlen,v(limit_count),f
    integer(c_int32_t)::limits(limit_count)
    integer(c_int32_t)::status
    f=0
    if(present(flags))f=flags
    call limits_vector(p%budget,v)
    limits=int(v,c_int32_t)
    allocate(source(max(1,size(p%source))))
    do i=1,size(p%source)
      source(i)=char(iachar(p%source(i)),kind=c_char)
    end do
    n=0
    do i=0,p%string_count-1
      n=n+p%lengths(i)
    end do
    pathlen=len_trim(path)
    allocate(code(0:p%count-1),spans(0:max(1,p%string_count)-1),bytes(max(1,n)),cpath(max(1,pathlen)))
    do i=0,p%count-1
      code(i)%op=int(p%code(i)%op,c_int32_t);code(i)%arg=int(p%code(i)%arg,c_int32_t)
      code(i)%next=int(p%code(i)%next,c_int32_t);code(i)%cost=int(p%code(i)%cost,c_int32_t)
      code(i)%line=int(p%code(i)%line,c_int32_t);code(i)%column=int(p%code(i)%column,c_int32_t)
      code(i)%number=real(p%code(i)%number,c_double)
    end do
    at=0
    do i=0,p%string_count-1
      spans(i)%offset=int(at,c_int32_t);spans(i)%length=int(p%lengths(i),c_int32_t)
      do j=1,p%lengths(i)
        at=at+1;bytes(at)=char(iachar(p%strings(i)(j:j)),kind=c_char)
      end do
    end do
    do i=1,pathlen
      cpath(i)=char(iachar(path(i:i)),kind=c_char)
    end do
    err=c_null_char
    status=emit_foundation(3_c_int32_t,code,int(p%count,c_size_t),int(p%entry,c_int32_t),bytes, &
      int(n,c_size_t),spans,int(p%string_count,c_size_t),cpath,int(pathlen,c_size_t),int(format,c_int32_t), &
      limits,source,int(size(p%source),c_size_t),int(f,c_int32_t),err,int(size(err),c_size_t))
    if(status/=0)then
      message=''
      do i=1,size(err)
        if(err(i)==c_null_char)exit
        message(i:i)=achar(iachar(err(i)))
      end do
      call fail(d,'Foundation chain: '//trim(message),1,1)
    end if
    deallocate(code,spans,bytes,cpath,source)
  end subroutine
end module urotif_foundation_bridge
