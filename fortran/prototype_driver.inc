  subroutine run_prototype_file(path,fuel,repairs,s,d,foundation,budget,stream)
    character(*), intent(in) :: path
    integer, intent(in) :: fuel
    logical, intent(in) :: repairs
    type(prototype_state), intent(inout) :: s
    type(diagnostic), intent(inout) :: d
    logical, optional, intent(in) :: foundation
    type(runtime_limits),optional,intent(in)::budget
    logical,optional,intent(in)::stream
    call proto_init(s,repairs,foundation,budget)
    if(present(stream))s%live_output=stream
    if(s%error%failed)then
      d=s%error;return
    end if
    call read_and_execute(path,fuel,s,d)
  end subroutine run_prototype_file

  subroutine read_and_execute(path,fuel,s,d)
    character(*),intent(in)::path
    integer,intent(in)::fuel
    type(prototype_state),intent(inout)::s
    type(diagnostic),intent(inout)::d
    character(s%budget%source),allocatable::source(:)
    integer::source_allocation_status
    integer::n
    allocate(source(1),stat=source_allocation_status)
    if(source_allocation_status/=0)then
      call fail(d,'cannot allocate source read buffer',1,1);s%error=d;return
    end if
    call read_source(path,source(1),n,d)
    if (d%failed) then
      s%error=d
      return
    end if
    call run_prototype_source(source(1),n,fuel,s)
    d=s%error
  end subroutine read_and_execute

  subroutine run_prototype_source(source,n,fuel,s)
    character(*), intent(in) :: source
    integer, intent(in) :: n,fuel
    type(prototype_state), intent(inout) :: s
    integer :: starts(0:n), lengths(0:n), nl, i, begin
    integer :: next_line,next_column,hi,lo,id
    character :: ch, escaped
    nl=0
    begin=1
    do i=1,n
      if (source(i:i) /= achar(10)) cycle
      starts(nl)=begin
      lengths(nl)=i-begin
      nl=nl+1
      begin=i+1
    end do
    starts(nl)=begin
    lengths(nl)=n-begin+1
    nl=nl+1
    if (n >= 2) then
      if (source(1:2) == '=)') s%line=1
    end if
    do while (s%line < nl .and. .not. s%error%failed)
      if (s%line < 0 .or. s%column < 0) then
        call proto_error(s,'P007: negative execution coordinate')
        exit
      end if
      if (s%column >= lengths(s%line)) then
        s%line=s%line+1
        s%column=0
        cycle
      end if
      if (s%steps >= fuel) then
        call proto_error(s,'P008: instruction fuel exhausted')
        exit
      end if
      if(s%foundation)then
        call maybe_collect(s)
      end if
      s%steps=s%steps+1
      i=starts(s%line)+s%column
      ch=source(i:i)
      next_line=s%line
      next_column=s%column+1
      escaped=achar(0)
      if(s%column+1<lengths(s%line))escaped=source(i+1:i+1)
      if(s%foundation.and.ch==achar(92).and.escaped=='x')then
        hi=-1;lo=-1
        if(s%column+3<lengths(s%line))then
          hi=hex_value(source(i+2:i+2));lo=hex_value(source(i+3:i+3))
        end if
        if(hi<0.or.lo<0)then
          call proto_error(s,'P003: hex escape requires two hexadecimal digits')
        else
          id=character_node(s,achar(16*hi+lo));call proto_push(s,id)
          next_column=s%column+4
        end if
      else
        call prototype_step(s,ch,escaped,s%column+1<lengths(s%line),nl,next_line,next_column)
      end if
      if(s%halted)exit
      if(s%pending_jump)then
        next_line=s%jump_line;next_column=s%jump_column;s%pending_jump=.false.
        if(next_line<0.or.next_line>=nl.or.next_column<0.or.next_column>s%budget%source) &
          call proto_error(s,'P007: call/return coordinate outside source')
      end if
      if (.not. s%error%failed) then
        s%line=next_line
        s%column=next_column
      end if
    end do
    if (.not. s%error%failed .and. s%depth /= 0) call proto_error(s,'P003: unclosed construction frame')
  end subroutine run_prototype_source

