! F95 front end: source-byte-stable IR. Every source byte retains an entry,
! even inside a fused constant, so arbitrary character jumps remain possible.
module urotif_foundation_ir
  use urotif_types
  use urotif_lexer, only: read_source
  use urotif_host_api
  use urotif_limits
  implicit none
  type foundation_instruction
    integer::op=0,arg=0,next=0,cost=0,line=1,column=1
    real(rk)::number=0.0_rk
  end type
  type foundation_program
    type(foundation_instruction),pointer::code(:)=>null()
    character,pointer::source(:)=>null()
    type(runtime_limits)::budget
    integer::count=0,entry=0,string_count=0,fused=0
    character(max_text)::strings(0:max_strings-1)
    integer::lengths(0:max_strings-1)
  end type
contains
  logical function pushable(c)
    character,intent(in)::c
    character(*),parameter::chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 <>,./'//achar(34)//achar(39)
    pushable=index(chars,c)>0
  end function
  subroutine foundation_compile(path,optimize,p,d,budget)
    character(*),intent(in)::path
    logical,intent(in)::optimize
    type(foundation_program),intent(inout)::p
    type(diagnostic),intent(inout)::d
    type(runtime_limits),optional,intent(in)::budget
    type(runtime_limits)::defaults
    p%budget=defaults
    if(present(budget))p%budget=budget
    if(associated(p%code))deallocate(p%code)
    if(associated(p%source))deallocate(p%source)
    call foundation_compile_buffer(path,optimize,p,d)
  end subroutine

  subroutine foundation_compile_buffer(path,optimize,p,d)
    character(*),intent(in)::path
    logical,intent(in)::optimize
    type(foundation_program),intent(inout)::p
    type(diagnostic),intent(inout)::d
    character(p%budget%source),allocatable::source(:)
    integer::source_allocation_status
    integer::n,i,row,col,j,k,op,a,cost,lenbuf,pool,id,arity,kind,status,total_literals,ios,hi,lo
    character::c,endchar,x
    character(max_text)::buffer
    character(256)::message
    real(rk)::numeric
    logical::closed,ok
    allocate(source(1),stat=source_allocation_status)
    if(source_allocation_status/=0)then
      call fail(d,'cannot allocate source read buffer',1,1);return
    end if
    call read_source(path,source(1),n,d)
    if(d%failed)return
    allocate(p%code(0:n),p%source(n),stat=ios)
    if(ios/=0)then
      call fail(d,'cannot allocate source-sized Foundation IR',1,1);return
    end if
    do i=1,n
      p%source(i)=source(1)(i:i)
    end do
    p%count=n+1;p%entry=0;p%string_count=0;p%fused=0;row=1;col=1
    do i=0,n-1
      c=source(1)(i+1:i+1);op=2;a=0
      if(pushable(c))then
        op=1;a=iachar(c)
      else
        select case(c)
        case(achar(10));op=3
        case(achar(92));op=4;a=256
        case('[');op=5;a=0
        case('{');op=5;a=1
        case(']');op=6;a=0
        case('}');op=6;a=1
        case('%');op=7
        case('_');op=8
        case('+');op=9
        case('-');op=10
        case('*');op=11
        case('|');op=12
        case('~');op=13
        case('$');op=14
        case(':');op=15
        case(';');op=16
        case('@');op=17
        case('`');op=18
        case('^');op=19
        case('=');op=20
        case('#');op=21
        case('&');op=22
        end select
      end if
      p%code(i)%op=op;p%code(i)%arg=a;p%code(i)%line=row;p%code(i)%column=col
      p%code(i)%next=i+1;p%code(i)%cost=1;p%code(i)%number=0.0_rk
      if(op==3)then
        p%code(i)%cost=0;row=row+1;col=1
      else
        col=col+1
      end if
    end do
    p%code(n)=foundation_instruction(0,0,n,0,row,col,0.0_rk)
    do i=0,n-1
      if(p%code(i)%op==4.and.i+1<n)then
        if(p%code(i+1)%op/=3)then
          p%code(i)%arg=iachar(source(1)(i+2:i+2));p%code(i)%next=i+2
          if(source(1)(i+2:i+2)=='x')then
            hi=-1;lo=-1
            if(i+3<n)then
              hi=hex_value(source(1)(i+3:i+3));lo=hex_value(source(1)(i+4:i+4))
            end if
            if(hi>=0.and.lo>=0)then
              p%code(i)%op=27;p%code(i)%arg=16*hi+lo;p%code(i)%next=i+4
            else
              p%code(i)%arg=256
            end if
          end if
        end if
      else if(p%code(i)%op==21)then
        j=i+1
        do while(j<n)
          if(p%code(j)%op==3)exit
          j=j+1
        end do
        p%code(i)%next=min(j+1,n)
      end if
    end do
    if(n>=2)then
      if(source(1)(1:2)=='=)')then
        do i=0,n-1
          if(p%code(i)%op==3)then
            p%entry=i+1;exit
          end if
        end do
      end if
    end if
    if(.not.optimize)return
    total_literals=0
    do i=p%entry,n-1
      if(p%code(i)%op/=5)cycle
      endchar=']'
      if(p%code(i)%arg==1)endchar='}'
      j=i+1;lenbuf=0;cost=1;closed=.false.;buffer=''
      do while(j<n)
        c=source(1)(j+1:j+1)
        if(c==endchar)then
          cost=cost+1;closed=.true.;exit
        end if
        if(c==achar(10))then
          j=j+1;cycle
        end if
        x=c
        if(c==achar(92))then
          if(j+1>=n)exit
          if(source(1)(j+2:j+2)==achar(10))exit
          if(p%code(j)%op==27)then
            x=achar(p%code(j)%arg);j=j+3
          else
            if(p%code(j)%arg==256)exit
            x=source(1)(j+2:j+2);if(x=='n')x=achar(10)
            j=j+1
          end if
        else if(.not.pushable(c))then
          exit
        end if
        if(lenbuf==max_text)exit
        lenbuf=lenbuf+1;buffer(lenbuf:lenbuf)=x;cost=cost+1;j=j+1
      end do
      if(.not.closed)cycle
      op=24;k=j+1;id=0
      if(endchar=='}')then
        call parse_decimal(buffer(1:lenbuf),numeric,ok)
        if(.not.ok)cycle
        op=26
      else if(j+2<n)then
        if(source(1)(j+3:j+3)=='@')then
          x=source(1)(j+2:j+2)
          if(x=='S')then
            op=25;k=j+3;cost=cost+2
          else if(x=='r'.or.x=='G')then
            a=2;if(x=='G')a=1
            call uf_host_lookup(a,0,buffer(1:lenbuf),id,arity,kind,status,message)
            if(status==0)then
              op=23;k=j+3;cost=cost+2
            end if
          end if
        end if
      end if
      if(op==24.or.op==25)then
        pool=-1
        do a=0,p%string_count-1
          if(p%lengths(a)==lenbuf.and.p%strings(a)==buffer)then
            pool=a;exit
          end if
        end do
        if(pool<0)then
          ! Bound the lifetime of cached constants, leaving arena headroom.
          if(p%string_count==max_strings.or.total_literals+lenbuf>8192)cycle
          pool=p%string_count;p%string_count=pool+1
          p%strings(pool)=buffer;p%lengths(pool)=lenbuf;total_literals=total_literals+lenbuf
        end if
        id=pool
      end if
      p%code(i)%op=op;p%code(i)%arg=id;p%code(i)%next=k;p%code(i)%cost=cost
      if(op==26)p%code(i)%number=numeric
      p%fused=p%fused+1
    end do
  end subroutine
  subroutine foundation_dump(p)
    type(foundation_program),intent(in)::p
    integer::i
    print '(a,i0,a,i0,a,i0)','Foundation IR2: ',p%count,' byte entries; ',p%fused,' fast paths; entry ',p%entry
    do i=0,p%count-1
      write(*,'(i6,2x,5(i6,1x),a,i0,a,i0)')i,p%code(i)%op,p%code(i)%arg,p%code(i)%next,p%code(i)%cost, &
        0,' @',p%code(i)%line,':',p%code(i)%column
    end do
  end subroutine
end module urotif_foundation_ir
