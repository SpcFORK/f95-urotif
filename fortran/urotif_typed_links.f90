! Native implementations behind the shared F95-facing ABI-2 adapter.
subroutine uf_host_signature(id,kinds,result_kind,status,message)
  use urotif_links,only:c_message
  use,intrinsic::iso_c_binding
  implicit none
  integer,intent(in)::id
  integer,intent(out)::kinds(0:7),result_kind,status
  character(*),intent(out)::message
  integer(c_int32_t)::types(8),result,cs
  character(kind=c_char)::err(1024)
  interface
    function signature(id,types,result,err,cap) bind(C,name='urotif_host_signature') result(status)
      import c_int32_t,c_char,c_size_t
      integer(c_int32_t),value::id
      integer(c_int32_t),intent(out)::types(*),result
      character(kind=c_char),intent(out)::err(*)
      integer(c_size_t),value::cap
      integer(c_int32_t)::status
    end function
  end interface
  types=0;result=0;err=c_null_char
  cs=signature(int(id,c_int32_t),types,result,err,int(size(err),c_size_t))
  kinds=int(types);result_kind=int(result);status=int(cs)
  call c_message(err,message)
end subroutine

subroutine uf_typed_dispatch(id,args,n,result,status,message)
  use urotif_typed_abi,only:typed_arg,typed_result,c_char,c_int32_t,c_size_t,c_null_char
  use urotif_links,only:c_message
  implicit none
  integer,intent(in)::id,n
  type(typed_arg),intent(in)::args(*)
  type(typed_result),intent(inout)::result
  integer,intent(out)::status
  character(*),intent(out)::message
  character(kind=c_char)::err(1024)
  integer(c_int32_t)::cs
  interface
    function typed_call(id,args,n,result,err,cap) bind(C,name='urotif_host_call_v2') result(status)
      import typed_arg,typed_result,c_int32_t,c_size_t,c_char
      integer(c_int32_t),value::id
      type(typed_arg),intent(in)::args(*)
      integer(c_size_t),value::n,cap
      type(typed_result),intent(inout)::result
      character(kind=c_char),intent(out)::err(*)
      integer(c_int32_t)::status
    end function
  end interface
  err=c_null_char
  cs=typed_call(int(id,c_int32_t),args,int(n,c_size_t),result,err,int(size(err),c_size_t))
  status=int(cs);call c_message(err,message)
end subroutine
