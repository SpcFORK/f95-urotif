! Optional symbolic conveniences. This F95 assembler emits the primitive
! character language; labels do not add runtime operations or a second VM.
module urotif_assembler
  use urotif_types
  use urotif_preprocess
  implicit none
contains
  logical function assembly_name(s)
    character(*),intent(in)::s
    integer::i,n
    n=len_trim(s);assembly_name=.false.
    if(n<1.or.n>max_name)return
    do i=1,n
      if(is_alpha(s(i:i)).or.s(i:i)=='_')cycle
      if(i>1.and.is_digit(s(i:i)))cycle
      return
    end do
    assembly_name=.true.
  end function
  subroutine assemble_foundation(path,output,d,budget)
    character(*),intent(in)::path,output
    type(diagnostic),intent(inout)::d
    type(runtime_limits),optional,intent(in)::budget
    type(runtime_limits)::b
    if(present(budget))b=budget
    call assemble_buffer(path,output,d,b)
  end subroutine
  subroutine assemble_buffer(path,output,d,budget)
    character(*),intent(in)::path,output
    type(diagnostic),intent(inout)::d
    type(runtime_limits),intent(in)::budget
    character(budget%source),allocatable::generated(:)
    integer::generated_allocation_status
    character(budget%source),allocatable::source(:)
    integer::source_allocation_status
    character(max_name),allocatable::labels(:)
    character(max_name)::argument
    integer,allocatable::addresses(:)
    integer::label_count,n,pass,i,begin,row,outrow,ng,k,sep,ios,unit,lines
    character(16)::command
    character(96)::expansion
    allocate(generated(1),stat=generated_allocation_status)
    if(generated_allocation_status/=0)then
      call fail(d,'cannot allocate assembly output buffer',1,1);return
    end if
    allocate(source(1),stat=source_allocation_status)
    if(source_allocation_status/=0)then
      call fail(d,'cannot allocate assembly read buffer',1,1);return
    end if
    call expand_foundation(path,source(1),n,budget,d)
    if(d%failed)return
    lines=1
    do i=1,n
      if(source(1)(i:i)==achar(10))lines=lines+1
    end do
    allocate(labels(0:lines-1),addresses(0:lines-1),stat=ios)
    if(ios/=0)then
      call fail(d,'cannot allocate source-sized label table',1,1);return
    end if
    label_count=0;ng=0
    do pass=1,2
      begin=1;row=0;outrow=2
      if(pass==2)call append_line('=) urotif')
      do i=1,n
        if(source(1)(i:i)/=achar(10))cycle
        row=row+1;command='';argument=''
        if(i>begin)then
          if(source(1)(begin:begin)=='.')then
            sep=index(source(1)(begin:i-1),' ')
            if(sep==0)sep=i-begin+1
            if(sep-1>len(command))then
              call fail(d,'Unknown assembly directive',row,1);return
            end if
            command=source(1)(begin:begin+sep-2)
            if(i-begin-sep>max_name)then
              call fail(d,'Assembly argument exceeds 63 bytes',row,1);return
            end if
            argument=trim(adjustl(source(1)(begin+sep:i-1)))
          end if
        end if
        if(row==1.and.i-begin>=2)then
          if(source(1)(begin:begin+1)=='=)')then
            begin=i+1;cycle
          end if
        end if
        select case(trim(command))
        case('.label','.goto','.eq','.call')
          if(.not.assembly_name(argument))then
            call fail(d,'Expected an ASCII label identifier',row,1);return
          end if
        case('.return','.halt')
          if(len_trim(argument)>0)then
            call fail(d,'This assembly directive takes no arguments',row,1);return
          end if
        case('')
        case default
          call fail(d,'Unknown assembly directive: '//trim(command),row,1);return
        end select
        if(command=='.label')then
          if(pass==1)then
            do k=0,label_count-1
              if(labels(k)==argument)then
                call fail(d,'Duplicate assembly label: '//trim(argument),row,1);return
              end if
            end do
            labels(label_count)=argument;addresses(label_count)=outrow;label_count=label_count+1
          end if
        else
          if(pass==2)then
            select case(trim(command))
            case('.goto','.eq','.call')
              k=0
              do while(k<label_count)
                if(labels(k)==argument)exit
                k=k+1
              end do
              if(k==label_count)then
                call fail(d,'Unresolved assembly label: '//trim(argument),row,1);return
              end if
              expansion='{'//trim(int_text(addresses(k)))//'}{0}'
              if(command=='.goto')expansion=trim(expansion)//'^'
              if(command=='.eq')expansion=trim(expansion)//'='
              if(command=='.call')expansion='['//trim(expansion)//']k@'
              call append_line(trim(expansion))
            case('.return');call append_line('R@')
            case('.halt');call append_line('h@')
            case('');call append_line(source(1)(begin:i-1))
            end select
            if(d%failed)return
          end if
          outrow=outrow+1
        end if
        begin=i+1
      end do
    end do
    unit=61
    open(unit=unit,file=output,status='replace',action='write',iostat=ios)
    if(ios/=0)then
      call fail(d,'Cannot open assembler output',1,1);return
    end if
    begin=1
    do i=1,ng
      if(generated(1)(i:i)/=achar(10))cycle
      write(unit,'(a)',iostat=ios)generated(1)(begin:i-1)
      if(ios/=0)exit
      begin=i+1
    end do
    close(unit)
    if(ios/=0)call fail(d,'Cannot write assembler output',1,1)
  contains
    subroutine append_line(text)
      character(*),intent(in)::text
      integer::length
      length=len(text)
      if(ng+length+1>len(generated(1)))then
        call fail(d,'assembled source exceeds configured source budget',1,1);return
      end if
      generated(1)(ng+1:ng+length)=text;ng=ng+length+1;generated(1)(ng:ng)=achar(10)
    end subroutine
  end subroutine
end module urotif_assembler
