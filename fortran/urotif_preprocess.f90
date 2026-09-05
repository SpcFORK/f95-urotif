! F95 source-level conveniences. New library words expand to existing byte
! instructions; no per-target compiler/runtime changes are needed for a .define.
module urotif_preprocess
  use urotif_types
  use urotif_limits
  use urotif_lexer,only:read_source
  implicit none
  type macro_entry
    character(max_name)::name=''
    integer::start=0,length=0
  end type
  type expansion_state
    type(macro_entry),pointer::words(:)=>null()
    character,pointer::pool(:)=>null()
    integer::count=0,used=0,read_bytes=0
    character(4096)::include_stack(0:31)
    type(runtime_limits)::budget
  end type
contains
  logical function word_name(name)
    character(*),intent(in)::name
    integer::i
    word_name=.false.
    if(len(name)<1.or.len(name)>max_name)return
    do i=1,len(name)
      if(is_alpha(name(i:i)).or.name(i:i)=='_')cycle
      if(i>1.and.is_digit(name(i:i)))cycle
      return
    end do
    word_name=.true.
  end function

  subroutine expand_foundation(path,output,n,budget,d)
    character(*),intent(in)::path
    character(*),intent(out)::output
    integer,intent(out)::n
    type(runtime_limits),intent(in)::budget
    type(diagnostic),intent(inout)::d
    type(expansion_state)::s
    integer::ios
    s%budget=budget;n=0
    allocate(s%words(0:63),s%pool(budget%source),stat=ios)
    if(ios/=0)then
      call fail(d,'cannot allocate source expansion buffers',1,1)
    else
      call expand_file(path,s,output,n,0,d)
    end if
    if(associated(s%words))deallocate(s%words)
    if(associated(s%pool))deallocate(s%pool)
  end subroutine

  subroutine append_line(output,n,text,d,row)
    character(*),intent(inout)::output
    integer,intent(inout)::n
    character(*),intent(in)::text
    type(diagnostic),intent(inout)::d
    integer,intent(in)::row
    integer::k
    if(d%failed)return
    k=len(text)
    if(k+1>len(output)-n)then
      call fail(d,'expanded source exceeds configured source budget',row,1);return
    end if
    output(n+1:n+k)=text;n=n+k+1;output(n:n)=achar(10)
  end subroutine

  function literal(text,number,command) result(out)
    character(*),intent(in)::text
    logical,intent(in)::number
    character,optional,intent(in)::command
    character(4*len(text)+6)::out
    character(*),parameter::safe='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 <>,./'//achar(34)//achar(39)
    character(2)::hex
    integer::i,n
    out='';out(1:1)='['
    if(number)out(1:1)='{'
    n=1
    do i=1,len(text)
      if(index(safe,text(i:i))>0)then
        n=n+1;out(n:n)=text(i:i)
      else
        write(hex,'(z2.2)')iachar(text(i:i))
        out(n+1:n+4)=achar(92)//'x'//hex;n=n+4
      end if
    end do
    if(number)then
      out(n+1:n+1)='}'
    else
      out(n+1:n+3)=']S@'
      if(present(command))out(n+2:n+2)=command
    end if
  end function

  function macro_text(s,k) result(text)
    type(expansion_state),intent(in)::s
    integer,intent(in)::k
    character(s%words(k)%length)::text
    integer::i
    do i=1,len(text)
      text(i:i)=s%pool(s%words(k)%start+i-1)
    end do
  end function

  subroutine define_word(s,name,text,d,row)
    type(expansion_state),intent(inout)::s
    character(*),intent(in)::name,text
    type(diagnostic),intent(inout)::d
    integer,intent(in)::row
    type(macro_entry),pointer::larger(:)
    integer::i,ios
    if(.not.word_name(name))then
      call fail(d,'expected macro identifier (ASCII, 1..63 bytes)',row,1);return
    end if
    do i=0,s%count-1
      if(s%words(i)%name==name)then
        call fail(d,'duplicate macro: '//name,row,1);return
      end if
    end do
    if(len(text)>0)then
      if(text(1:1)=='.')then
        call fail(d,'macro bodies contain primitive byte code, not directives',row,1);return
      end if
    end if
    if(len(text)>size(s%pool)-s%used)then
      call fail(d,'macro body pool exceeds source budget',row,1);return
    end if
    if(s%count==size(s%words))then
      allocate(larger(0:2*size(s%words)-1),stat=ios)
      if(ios/=0)then
        call fail(d,'cannot grow macro table',row,1);return
      end if
      larger(:s%count-1)=s%words
      deallocate(s%words);s%words=>larger
    end if
    s%words(s%count)%name=name;s%words(s%count)%start=s%used+1;s%words(s%count)%length=len(text)
    do i=1,len(text)
      s%pool(s%used+i)=text(i:i)
    end do
    s%used=s%used+len(text);s%count=s%count+1
  end subroutine

  recursive subroutine expand_file(path,s,output,ng,depth,d)
    character(*),intent(in)::path
    type(expansion_state),intent(inout)::s
    character(*),intent(inout)::output
    integer,intent(inout)::ng
    integer,intent(in)::depth
    type(diagnostic),intent(inout)::d
    character(s%budget%source),allocatable::arg(:)
    integer::arg_allocation_status
    character(s%budget%source),allocatable::raw(:)
    integer::raw_allocation_status
    character(4096)::child
    character(32)::command
    character(8)::alias
    character(4*s%budget%source+6),allocatable::hextext(:)
    integer::hextext_allocation_status
    integer::n,i,a,row,sep,k,j,start,h,hi,lo
    logical::ok,number
    real(rk)::x
    allocate(hextext(1),stat=hextext_allocation_status)
    if(hextext_allocation_status/=0)then
      call fail(d,'cannot allocate literal buffer',1,1);return
    end if
    allocate(arg(1),stat=arg_allocation_status)
    if(arg_allocation_status/=0)then
      call fail(d,'cannot allocate directive buffer',1,1);return
    end if
    allocate(raw(1),stat=raw_allocation_status)
    if(raw_allocation_status/=0)then
      call fail(d,'cannot allocate included source buffer',1,1);return
    end if
    if(depth>=32)then
      call fail(d,'include depth guard: 32 (no recursive includes)',1,1);return
    end if
    if(len(path)>4096)then
      call fail(d,'include path exceeds 4096 bytes',1,1);return
    end if
    do i=0,depth-1
      if(s%include_stack(i)==path)then
        call fail(d,'recursive include: '//path,1,1);return
      end if
    end do
    s%include_stack(depth)=path
    call read_source(path,raw(1),n,d)
    if(d%failed)return
    if(n>s%budget%source-s%read_bytes)then
      call fail(d,'total included source exceeds configured source budget',1,1);return
    end if
    s%read_bytes=s%read_bytes+n;a=1;row=0
    do i=1,n
      if(raw(1)(i:i)/=achar(10))cycle
      row=row+1
      if(row==1.and.i-a>=2)then
        if(raw(1)(a:a+1)=='=)')then
          a=i+1;cycle
        end if
      end if
      command='';arg(1)='';start=i
      if(i>a)then
        if(raw(1)(a:a)=='.')then
          sep=index(raw(1)(a:i-1),' ')
          if(sep==0)sep=i-a+1
          if(sep-1<=len(command))command=raw(1)(a:a+sep-2)
          start=min(i,a+sep)
          arg(1)=raw(1)(start:i-1)
        end if
      end if
      select case(trim(command))
      case('.include')
        if(len_trim(arg(1))==0)then
          call fail(d,'include requires a local file path',row,1);return
        end if
        if(len_trim(arg(1))>4096)then
          call fail(d,'include path exceeds 4096 bytes',row,1);return
        end if
        if(arg(1)(1:1)=='/')then
          child=trim(arg(1))
        else
          k=scan(path,'/'//achar(92),back=.true.)
          if(k+len_trim(arg(1))>len(child))then
            call fail(d,'include path exceeds 4096 bytes',row,1);return
          end if
          child=path(:k)//trim(arg(1))
        end if
        call expand_file(trim(child),s,output,ng,depth+1,d)
      case('.define')
        k=index(trim(arg(1)),' ')
        if(k==0)then
          call fail(d,'define requires NAME followed by primitive byte code',row,1);return
        end if
        call define_word(s,arg(1)(:k-1),arg(1)(k+1:len_trim(arg(1))),d,row)
      case('.use')
        if(.not.word_name(trim(arg(1))))then
          call fail(d,'use requires one macro identifier',row,1);return
        end if
        k=0
        do while(k<s%count)
          if(s%words(k)%name==arg(1))exit
          k=k+1
        end do
        if(k==s%count)then
          call fail(d,'undefined macro: '//trim(arg(1)),row,1);return
        end if
        call append_line(output,ng,macro_text(s,k),d,row)
      case('.text','.number','.ref','.import','.pack')
        if(command=='.pack'.and.len_trim(arg(1))==0)then
          call append_line(output,ng,'b@',d,row)
        else
          number=command=='.number'.or.command=='.pack'
          if(number)then
            call parse_decimal(trim(arg(1)),x,ok)
            if(.not.ok)then
              call fail(d,'number requires a finite decimal',row,1);return
            end if
            if(command=='.pack')then
              if(x<0.or.x/=aint(x))then
                call fail(d,'pack count must be a nonnegative integer',row,1);return
              end if
            end if
          end if
          if(command=='.text')then
            call append_line(output,ng,trim(literal(raw(1)(start:i-1),.false.)),d,row)
          else if(command=='.pack')then
            call append_line(output,ng,trim(literal(trim(arg(1)),.true.))//'b@',d,row)
          else if(command=='.ref')then
            call append_line(output,ng,trim(literal(trim(arg(1)),.false.,'r')),d,row)
          else if(command=='.import')then
            call append_line(output,ng,trim(literal(trim(arg(1)),.false.,'i')),d,row)
          else
            call append_line(output,ng,trim(literal(trim(arg(1)),number)),d,row)
          end if
        end if
      case('.bytes')
        hextext(1)='[';h=1;hi=-1
        do j=1,len_trim(arg(1))
          if(arg(1)(j:j)==' '.or.arg(1)(j:j)==achar(9))cycle
          lo=hex_value(arg(1)(j:j))
          if(lo<0)then
            call fail(d,'bytes requires hexadecimal octets',row,1);return
          end if
          if(hi<0)then
            hi=j
          else
            hextext(1)(h+1:h+4)=achar(92)//'x'//arg(1)(hi:hi)//arg(1)(j:j);h=h+4;hi=-1
          end if
        end do
        if(hi>=0)then
          call fail(d,'bytes requires complete hexadecimal octets',row,1);return
        end if
        hextext(1)(h+1:h+3)=']S@'
        call append_line(output,ng,hextext(1)(:h+3),d,row)
      case('.dup','.drop','.swap','.over','.rot','.depth','.print','.println','.read')
        if(len_trim(arg(1))>0)then
          call fail(d,'stack/I/O directive takes no argument',row,1);return
        end if
        select case(trim(command))
        case('.dup');alias='%'
        case('.drop');alias='_'
        case('.swap');alias='x@'
        case('.over');alias='o@'
        case('.rot');alias='t@'
        case('.depth');alias='d@'
        case('.print');alias='$'
        case('.println');alias='$'//achar(92)//'n$'
        case('.read');alias='`'
        end select
        call append_line(output,ng,trim(alias),d,row)
      case default
        call append_line(output,ng,raw(1)(a:i-1),d,row)
      end select
      if(d%failed)return
      a=i+1
    end do
  end subroutine
end module urotif_preprocess
