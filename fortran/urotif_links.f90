! Only this adapter requires F2003 ISO_C_BINDING.
module urotif_links
  use, intrinsic :: iso_c_binding
  use urotif_types
  implicit none
  interface
    function host_load(path,n,err,cap) bind(C,name='urotif_host_load') result(status)
      import c_char,c_size_t,c_int32_t
      character(kind=c_char),intent(in)::path(*)
      integer(c_size_t),value::n,cap
      character(kind=c_char),intent(out)::err(*)
      integer(c_int32_t)::status
    end function
    function host_declare(path,n,err,cap) bind(C,name='urotif_host_declare') result(status)
      import c_char,c_size_t,c_int32_t
      character(kind=c_char),intent(in)::path(*)
      integer(c_size_t),value::n,cap
      character(kind=c_char),intent(out)::err(*)
      integer(c_int32_t)::status
    end function
    function host_declare_v2(path,n,err,cap) bind(C,name='urotif_host_declare_v2') result(status)
      import c_char,c_size_t,c_int32_t
      character(kind=c_char),intent(in)::path(*)
      integer(c_size_t),value::n,cap
      character(kind=c_char),intent(out)::err(*)
      integer(c_int32_t)::status
    end function
    function host_lookup(mode,module_id,name,n,id,arity,kind,err,cap) &
        bind(C,name='urotif_host_lookup') result(status)
      import c_char,c_size_t,c_int32_t
      integer(c_int32_t),value::mode,module_id
      character(kind=c_char),intent(in)::name(*)
      integer(c_size_t),value::n,cap
      integer(c_int32_t),intent(out)::id,arity,kind
      character(kind=c_char),intent(out)::err(*)
      integer(c_int32_t)::status
    end function
    function host_call(id,args,n,value,err,cap) bind(C,name='urotif_host_call') result(status)
      import c_char,c_size_t,c_int32_t,c_double
      integer(c_int32_t),value::id
      real(c_double),intent(in)::args(*)
      integer(c_size_t),value::n,cap
      real(c_double),intent(out)::value
      character(kind=c_char),intent(out)::err(*)
      integer(c_int32_t)::status
    end function
    function host_catalog(text,cap) bind(C,name='urotif_host_catalog') result(status)
      import c_char,c_size_t,c_int32_t
      character(kind=c_char),intent(out)::text(*)
      integer(c_size_t),value::cap
      integer(c_int32_t)::status
    end function
  end interface
contains
  subroutine c_message(bytes,message)
    character(kind=c_char),intent(in)::bytes(:)
    character(*),intent(out)::message
    integer::i
    message=''
    do i=1,min(size(bytes),len(message))
      if(bytes(i)==c_null_char)exit
      message(i:i)=achar(iachar(bytes(i)))
    end do
  end subroutine
  subroutine load_link(path,d,declaration,typed)
    character(*),intent(in)::path
    type(diagnostic),intent(inout)::d
    logical,optional,intent(in)::declaration,typed
    logical::declare_only,is_typed
    character(kind=c_char)::buf(4096),err(1024)
    character(1024)::msg
    integer::i,n
    integer(c_int32_t)::status
    n=len_trim(path)
    if(n>size(buf))then
      call fail(d,'plugin path exceeds 4096 bytes',1,1)
      return
    end if
    do i=1,n
      buf(i)=char(iachar(path(i:i)),kind=c_char)
    end do
    declare_only=.false.;is_typed=.false.
    if(present(typed))is_typed=typed
    if(present(declaration))declare_only=declaration
    if(declare_only.and.is_typed)then
      status=host_declare_v2(buf,int(n,c_size_t),err,int(size(err),c_size_t))
    else if(declare_only)then
      status=host_declare(buf,int(n,c_size_t),err,int(size(err),c_size_t))
    else
      status=host_load(buf,int(n,c_size_t),err,int(size(err),c_size_t))
    end if
    if(status/=0)then
      call c_message(err,msg)
      call fail(d,'link: '//trim(msg),1,1)
    end if
  end subroutine
  subroutine list_links()
    character(kind=c_char)::buf(65536)
    character(65536)::text
    integer(c_int32_t)::status
    status=host_catalog(buf,int(size(buf),c_size_t))
    if(status==0)then
      call c_message(buf,text)
      write(*,'(a)',advance='no')trim(text)
    end if
  end subroutine
end module urotif_links

subroutine uf_host_lookup(mode,module_id,name,id,arity,kind,status,message)
  use urotif_links
  implicit none
  integer,intent(in)::mode,module_id
  character(*),intent(in)::name
  integer,intent(out)::id,arity,kind,status
  character(*),intent(out)::message
  character(kind=c_char)::buf(4096),err(1024)
  integer(c_int32_t)::ci,ca,ck,cs
  integer::i,n
  n=len(name)
  id=-1;arity=0;kind=0;ci=-1;ca=0;ck=0
  if(n>size(buf))then
    status=1;message='name too long';return
  end if
  do i=1,n
    buf(i)=char(iachar(name(i:i)),kind=c_char)
  end do
  cs=host_lookup(int(mode,c_int32_t),int(module_id,c_int32_t),buf,int(n,c_size_t),ci,ca,ck,err, &
    int(size(err),c_size_t))
  status=int(cs);id=int(ci);arity=int(ca);kind=int(ck)
  call c_message(err,message)
end subroutine
subroutine uf_host_apply(id,args,n,result,status,message)
  use urotif_links
  implicit none
  integer,intent(in)::id,n
  real(rk),intent(in)::args(*)
  real(rk),intent(out)::result
  integer,intent(out)::status
  character(*),intent(out)::message
  real(c_double)::ca(8),c_result
  character(kind=c_char)::err(1024)
  integer(c_int32_t)::cs
  integer::i
  result=0.0_rk;c_result=0.0_c_double
  if(n<0.or.n>8)then
    status=1;message='arity must be 0..8';return
  end if
  do i=1,n
    ca(i)=real(args(i),c_double)
  end do
  cs=host_call(int(id,c_int32_t),ca,int(n,c_size_t),c_result,err,int(size(err),c_size_t))
  status=int(cs);result=real(c_result,rk)
  call c_message(err,message)
end subroutine

subroutine uf_flush_output()
  use,intrinsic::iso_fortran_env,only:output_unit
  implicit none
  flush(output_unit)
end subroutine
