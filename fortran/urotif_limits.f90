! Resource policy, shared by the native interpreter and every emitted target.
! Dynamic arrays in the value core remain standard Fortran 95 pointer arrays.
module urotif_limits
  use urotif_types, only: diagnostic, fail, parse_decimal, rk, int_text
  implicit none
  integer, parameter :: limit_count=11
  type runtime_limits
    integer :: nodes=32768, edges=32768, text=524288, output=262144
    integer :: stack=2048, frames=64, returns=1024, input_line=2048
    integer :: input=1048576, source=1048576, work=262144
  end type
contains
  subroutine limits_vector(b,v)
    type(runtime_limits),intent(in)::b
    integer,intent(out)::v(limit_count)
    v=(/b%nodes,b%edges,b%text,b%output,b%stack,b%frames,b%returns,b%input_line,b%input,b%source,b%work/)
  end subroutine
  subroutine set_limit(b,option,d)
    type(runtime_limits),intent(inout)::b
    character(*),intent(in)::option
    type(diagnostic),intent(inout)::d
    integer::p,n,lo,hi
    real(rk)::x
    logical::ok
    character(32)::name
    p=index(option,'=')
    if(p<2.or.p>len_trim(option)-1.or.p>len(name))then
      call fail(d,'limit must be NAME=INTEGER',1,1);return
    end if
    name=option(:p-1)
    call parse_decimal(option(p+1:),x,ok)
    if(.not.ok)then
      call fail(d,'invalid limit value',1,1);return
    end if
    select case(trim(name))
    case('nodes');lo=128;hi=1048576
    case('edges');lo=32;hi=4194304
    case('text');lo=256;hi=67108864
    case('output');lo=64;hi=33554432
    case('stack');lo=16;hi=1048576
    case('frames');lo=1;hi=1024
    case('returns');lo=1;hi=1048576
    case('input-line');lo=1;hi=16777216
    case('input');lo=1;hi=67108864
    case('source');lo=64;hi=8388608
    case('work');lo=1;hi=16777216
    case default
      call fail(d,'unknown resource limit: '//trim(name),1,1);return
    end select
    if(x<lo.or.x>hi.or.x/=aint(x))then
      call fail(d,trim(name)//' limit must be '//trim(int_text(lo))//'..'//trim(int_text(hi)),1,1);return
    end if
    n=int(x)
    select case(trim(name))
    case('nodes');b%nodes=n
    case('edges');b%edges=n
    case('text');b%text=n
    case('output');b%output=n
    case('stack');b%stack=n
    case('frames');b%frames=n
    case('returns');b%returns=n
    case('input-line');b%input_line=n
    case('input');b%input=n
    case('source');b%source=n
    case('work');b%work=n
    end select
  end subroutine
end module urotif_limits
