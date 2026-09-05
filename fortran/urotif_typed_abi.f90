! F2003-only boundary. The value runtime and procedure-facing API remain F95.
! This adapter is also embedded in Fortran target programs that use ABI 2.
module urotif_typed_abi
  use,intrinsic::iso_c_binding
  use,intrinsic::ieee_arithmetic,only:ieee_value,ieee_quiet_nan
  use urotif_types,only:rk,finite_number
  implicit none
  type,bind(C)::typed_arg
    integer(c_int32_t)::tag,reserved
    real(c_double)::number
    type(c_ptr)::bytes
    integer(c_size_t)::length
    type(c_ptr)::vector
    integer(c_size_t)::count
  end type
  type,bind(C)::typed_result
    real(c_double)::number
    type(c_ptr)::bytes
    integer(c_size_t)::capacity,length
    type(c_ptr)::vector
    integer(c_size_t)::vector_capacity,count
  end type
  interface
    subroutine uf_typed_dispatch(id,args,n,result,status,message)
      import typed_arg,typed_result
      integer,intent(in)::id,n
      type(typed_arg),intent(in)::args(*)
      type(typed_result),intent(inout)::result
      integer,intent(out)::status
      character(*),intent(out)::message
    end subroutine
  end interface
end module urotif_typed_abi

subroutine uf_host_apply_typed(id,kinds,n,numbers,starts,lengths,bytes,nb,vectors,nv, &
    result_kind,number_result,result_bytes,bc,outb,result_vector,vc,outv,status,message)
  use urotif_typed_abi
  implicit none
  integer,intent(in)::id,kinds(0:7),n,starts(0:7),lengths(0:7),nb,nv,result_kind,bc,vc
  real(rk),intent(in)::numbers(0:7),vectors(*)
  character,intent(in)::bytes(*)
  real(rk),intent(out)::number_result,result_vector(*)
  character,intent(out)::result_bytes(*)
  integer,intent(out)::outb,outv,status
  character(*),intent(out)::message
  type(typed_arg)::args(8)
  type(typed_result)::result
  character(kind=c_char),allocatable,target::cb(:),rb(:)
  real(c_double),allocatable,target::cv(:),rv(:)
  integer::i,j,ios
  number_result=0.0_rk;outb=0;outv=0;status=1;message='invalid typed buffers/signature'
  if(n<0.or.n>8.or.nb<0.or.nv<0.or.bc<0.or.vc<0.or.result_kind<1.or.result_kind>3)return
  do i=0,n-1
    if(kinds(i)<1.or.kinds(i)>3.or.starts(i)<0.or.lengths(i)<0)return
    if(kinds(i)==2)then
      if(starts(i)>nb.or.lengths(i)>nb-starts(i))return
    else if(kinds(i)==3)then
      if(starts(i)>nv.or.lengths(i)>nv-starts(i))return
    end if
  end do
  allocate(cb(max(1,nb)),cv(max(1,nv)),rb(max(1,bc)),rv(max(1,vc)),stat=ios)
  if(ios/=0)then
    message='cannot allocate C-interoperable typed buffers';return
  end if
  do i=1,nb
    cb(i)=char(iachar(bytes(i)),kind=c_char)
  end do
  do i=1,nv
    cv(i)=real(vectors(i),c_double)
  end do
  rb=c_null_char;rv=0.0_c_double
  do i=0,n-1
    j=i+1
    args(j)%tag=int(kinds(i),c_int32_t);args(j)%reserved=0
    args(j)%number=real(numbers(i),c_double)
    args(j)%bytes=c_null_ptr;args(j)%length=0
    args(j)%vector=c_null_ptr;args(j)%count=0
    if(kinds(i)==2)then
      if(lengths(i)>0)args(j)%bytes=c_loc(cb(starts(i)+1))
      args(j)%length=int(lengths(i),c_size_t)
    else if(kinds(i)==3)then
      if(lengths(i)>0)args(j)%vector=c_loc(cv(starts(i)+1))
      args(j)%count=int(lengths(i),c_size_t)
    end if
  end do
  result%number=ieee_value(0.0_c_double,ieee_quiet_nan)
  result%bytes=c_loc(rb(1));result%capacity=int(bc,c_size_t);result%length=0
  result%vector=c_loc(rv(1));result%vector_capacity=int(vc,c_size_t);result%count=0
  call uf_typed_dispatch(id,args,n,result,status,message)
  if(.not.c_associated(result%bytes,c_loc(rb(1))).or..not.c_associated(result%vector,c_loc(rv(1))).or. &
     result%capacity/=int(bc,c_size_t).or.result%vector_capacity/=int(vc,c_size_t))then
    status=1;message='plugin changed caller-owned buffers/capacities';return
  end if
  if(status/=0)return
  status=1
  if(result%length<0.or.result%length>int(bc,c_size_t).or. &
     result%count<0.or.result%count>int(vc,c_size_t))then
    message='typed result exceeds caller capacity';return
  end if
  select case(result_kind)
  case(1)
    number_result=real(result%number,rk)
    if(.not.finite_number(number_result))then
      message='typed service returned non-finite number';return
    end if
  case(2)
    outb=int(result%length)
    do i=1,outb
      result_bytes(i)=achar(iachar(rb(i)))
    end do
  case(3)
    outv=int(result%count)
    do i=1,outv
      result_vector(i)=real(rv(i),rk)
      if(.not.finite_number(result_vector(i)))then
        message='typed service returned non-finite vector';return
      end if
    end do
  end select
  status=0;message=''
end subroutine uf_host_apply_typed
