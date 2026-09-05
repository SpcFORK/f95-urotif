! Reference-first, character-level interpreter. Fortran 95 only.
! This module does not use the experimental word lexer: spaces, digits, [, ],
! ; and @ must retain their Oak-prototype roles. Repairs are opt-in.
module urotif_prototype
  use urotif_types, only: rk, diagnostic, fail, int_text, number_text, finite_number, &
    parse_decimal, max_source, hex_value
  use urotif_lexer, only: read_source
  use urotif_host_api
  use urotif_limits
  implicit none
  integer, parameter :: pn_null=0, pn_number=1, pn_text=2, pn_array=3, pn_integer=4, pn_module=5, pn_ref=6
  integer, parameter :: node_cap=32768, edge_cap=32768, proto_stack_cap=2048, frame_cap=64
  integer, parameter :: text_cap=524288, output_cap=262144, line_cap=65536
  type proto_node
    integer :: tag=pn_null, start=1, length=0
    real(rk) :: number=0.0_rk
  end type proto_node
  type prototype_state
    type(runtime_limits) :: budget
    type(proto_node),pointer :: nodes(:)=>null()
    integer,pointer :: edges(:)=>null(), stack(:)=>null()
    integer,pointer :: bases(:)=>null(), frame_kind(:)=>null()
    character,pointer :: text(:)=>null(), output(:)=>null()
    integer :: node_count=1, edge_count=0, text_length=0, output_length=0
    integer :: sp=0, depth=0, line=0, column=0, steps=0
    logical :: live_output=.false.
    logical :: repairs=.false., foundation=.false., halted=.false., pending_jump=.false.
    integer :: ref_cache(0:255), module_cache(0:31)
    integer :: char_cache(0:255), free_count=0, collections=0, comparison_work=0
    integer,pointer :: free_nodes(:)=>null()
    integer :: array_cache(0:1023), literal_cache(0:1023)
    integer,pointer :: return_line(:)=>null(), return_column(:)=>null(), return_depth(:)=>null()
    integer :: rp=0, input_used=0, input_cursor=1
    character,pointer :: replay(:)=>null()
    integer :: jump_line=0, jump_column=0
    type(diagnostic) :: error
  end type prototype_state
contains
  ! States own their pointers. Do not copy a state with intrinsic assignment.
  subroutine proto_release(s)
    type(prototype_state),intent(inout)::s
    if(associated(s%nodes))deallocate(s%nodes)
    if(associated(s%edges))deallocate(s%edges)
    if(associated(s%stack))deallocate(s%stack)
    if(associated(s%bases))deallocate(s%bases)
    if(associated(s%frame_kind))deallocate(s%frame_kind)
    if(associated(s%free_nodes))deallocate(s%free_nodes)
    if(associated(s%text))deallocate(s%text)
    if(associated(s%output))deallocate(s%output)
    if(associated(s%return_line))deallocate(s%return_line)
    if(associated(s%return_column))deallocate(s%return_column)
    if(associated(s%return_depth))deallocate(s%return_depth)
  end subroutine

  function byte_string(bytes) result(text)
    character,intent(in)::bytes(:)
    character(size(bytes))::text
    integer::i
    do i=1,size(bytes)
      text(i:i)=bytes(i)
    end do
  end function

  subroutine store_bytes(bytes,start,text)
    character,intent(inout)::bytes(:)
    integer,intent(in)::start
    character(*),intent(in)::text
    integer::i
    do i=1,len(text)
      bytes(start+i-1)=text(i:i)
    end do
  end subroutine

  subroutine proto_error(s, message)
    type(prototype_state), intent(inout) :: s
    character(*), intent(in) :: message
    call fail(s%error, message, s%line+1, s%column+1)
  end subroutine proto_error

  subroutine proto_init(s, repairs, foundation, budget)
    type(prototype_state), intent(inout) :: s
    logical, intent(in) :: repairs
    logical, optional, intent(in) :: foundation
    type(runtime_limits),optional,intent(in)::budget
    type(runtime_limits)::defaults
    integer::ios
    call proto_release(s)
    nullify(s%replay)
    s%input_cursor=1;s%live_output=.false.
    s%budget=defaults
    if(present(budget))s%budget=budget
    s%error%failed=.false.
    s%sp=0;s%depth=0;s%output_length=0;s%line=0;s%column=0;s%steps=0
    allocate(s%nodes(0:s%budget%nodes-1),s%edges(0:s%budget%edges-1),s%stack(0:s%budget%stack-1), &
      s%bases(0:s%budget%frames),s%frame_kind(0:s%budget%frames),s%free_nodes(0:s%budget%nodes-1), &
      s%text(s%budget%text),s%output(s%budget%output),s%return_line(0:s%budget%returns-1), &
      s%return_column(0:s%budget%returns-1),s%return_depth(0:s%budget%returns-1),stat=ios)
    if(ios/=0)then
      call proto_error(s,'P002: cannot allocate configured runtime arenas');return
    end if
    s%array_cache=0;s%literal_cache=0;s%input_used=0
    s%node_count=1
    s%edge_count=0
    s%text_length=0
    s%output_length=0
    s%sp=0
    s%depth=0
    s%line=0
    s%column=0
    s%steps=0
    s%bases(0)=0
    s%frame_kind(0)=0
    s%repairs=repairs
    s%foundation=.false.
    if(present(foundation))s%foundation=foundation
    if(s%foundation)s%repairs=.true.
    s%char_cache=0;s%ref_cache=0;s%module_cache=0;s%free_count=0;s%collections=0;s%comparison_work=0;s%rp=0
    s%halted=.false.;s%pending_jump=.false.
    s%error%failed=.false.
    s%error%line=1
    s%error%column=1
    s%error%message=''
    s%nodes(0)%tag=pn_null
    s%nodes(0)%length=0
  end subroutine proto_init

  integer function new_node(s, tag) result(id)
    type(prototype_state), intent(inout) :: s
    integer, intent(in) :: tag
    id=0
    if (s%error%failed) return
    if(s%foundation.and.s%free_count>0)then
      s%free_count=s%free_count-1
      id=s%free_nodes(s%free_count)
    else
    if (s%node_count == s%budget%nodes) then
      call proto_error(s, 'P002: value arena budget exhausted')
      return
    end if
    id=s%node_count
    s%node_count=id+1
    end if
    s%nodes(id)%tag=tag
    s%nodes(id)%start=1
    s%nodes(id)%length=0
    s%nodes(id)%number=0.0_rk
  end function new_node

  integer function new_text(s, text, n) result(id)
    type(prototype_state), intent(inout) :: s
    character(*), intent(in) :: text
    integer, intent(in) :: n
    id=0
    if (s%text_length+n > s%budget%text) then
      call proto_error(s, 'P002: text arena budget exhausted')
      return
    end if
    id=new_node(s, pn_text)
    if (s%error%failed) return
    s%nodes(id)%start=s%text_length+1
    s%nodes(id)%length=n
    if (n > 0) call store_bytes(s%text,s%text_length+1,text(1:n))
    s%text_length=s%text_length+n
  end function new_text

  integer function new_number(s, x, integer_result) result(id)
    type(prototype_state), intent(inout) :: s
    real(rk), intent(in) :: x
    logical, optional, intent(in) :: integer_result
    id=0
    if (.not. finite_number(x)) then
      call proto_error(s, 'P010: non-finite numeric result')
      return
    end if
    if(present(integer_result))then
    if(s%foundation)then
      if(integer_result.and.abs(x)>9007199254740991.0_rk)then
        call proto_error(s,'P010: exact portable integer range exceeded');return
      end if
    end if
    end if
    id=new_node(s, pn_number)
    if (.not. s%error%failed) then
      s%nodes(id)%number=x
      if (present(integer_result)) then
        if (integer_result) s%nodes(id)%tag=pn_integer
      end if
    end if
  end function new_number

  subroutine proto_push(s, id)
    type(prototype_state), intent(inout) :: s
    integer, intent(in) :: id
    if (s%error%failed) return
    if (s%sp == s%budget%stack) then
      call proto_error(s, 'P002: data stack budget exhausted')
      return
    end if
    s%stack(s%sp)=id
    s%sp=s%sp+1
  end subroutine proto_push

  integer function proto_pop(s) result(id)
    type(prototype_state), intent(inout) :: s
    id=0
    if (s%error%failed) return
    if (s%sp == s%bases(s%depth)) then
      ! Oak happens to produce ? here. The port deliberately reports underflow
      ! rather than relying on negative indexing or silently printing null.
      call proto_error(s, 'P001: empty active stack (Oak would yield null here)')
      return
    end if
    s%sp=s%sp-1
    id=s%stack(s%sp)
  end function proto_pop

  subroutine open_frame(s, kind)
    type(prototype_state), intent(inout) :: s
    integer, intent(in) :: kind
    if (s%depth == s%budget%frames) then
      call proto_error(s, 'P002: construction depth budget exhausted')
      return
    end if
    s%depth=s%depth+1
    s%bases(s%depth)=s%sp
    s%frame_kind(s%depth)=kind
  end subroutine open_frame

  integer function close_frame(s, kind) result(id)
    type(prototype_state), intent(inout) :: s
    integer, intent(in) :: kind
    integer :: n, i
    id=0
    if (s%depth == 0) then
      call proto_error(s, 'P003: closing delimiter without a construction frame')
      return
    end if
    if (s%frame_kind(s%depth) /= kind) then
      call proto_error(s, 'P003: mismatched construction delimiters')
      return
    end if
    n=s%sp-s%bases(s%depth)
    if (s%edge_count+n > s%budget%edges) then
      call proto_error(s, 'P002: array arena budget exhausted')
      return
    end if
    id=new_node(s, pn_array)
    if (s%error%failed) return
    s%nodes(id)%start=s%edge_count
    s%nodes(id)%length=n
    do i=0,n-1
      s%edges(s%edge_count+i)=s%stack(s%bases(s%depth)+i)
    end do
    s%edge_count=s%edge_count+n
    s%sp=s%bases(s%depth)
    s%depth=s%depth-1
  end function close_frame

  subroutine output_append(s, text, n)
    type(prototype_state), intent(inout) :: s
    character(*), intent(in) :: text
    integer, intent(in) :: n
    if (s%error%failed) return
    if (s%output_length+n > s%budget%output) then
      call proto_error(s, 'P002: output budget exhausted')
      return
    end if
    if (n > 0) call store_bytes(s%output,s%output_length+1,text(1:n))
    s%output_length=s%output_length+n
    if(s%live_output)then
      if(n>0)write(*,'(a)',advance='no')text(:n)
      call uf_flush_output()
    end if
  end subroutine output_append

  function proto_number_text(x) result(out)
    real(rk), intent(in) :: x
    character(64) :: out
    integer :: n
    out=number_text(x)
    if (abs(x) >= 1.0e-12_rk .and. abs(x) < 1.0e15_rk) then
      write(out, '(f48.15)') x
      out=adjustl(out)
      n=len_trim(out)
      do while (n > 0)
        if (out(n:n) /= '0') exit
        out(n:n)=' '
        n=n-1
      end do
      if (n > 0) then
        if (out(n:n) == '.') out(n:n)=' '
      end if
    end if
  end function proto_number_text

  subroutine repr_put(out, n, text)
    character(*), intent(inout) :: out
    integer, intent(inout) :: n
    character(*), intent(in) :: text
    integer :: count
    count=len(text)
    if (n+count > len(out)) then
      n=len(out)+1
      return
    end if
    out(n+1:n+count)=text
    n=n+count
  end subroutine repr_put

  recursive subroutine node_repr(s, id, out, n, quote_text, depth)
    type(prototype_state), intent(in) :: s
    integer, intent(in) :: id, depth
    character(*), intent(inout) :: out
    integer, intent(inout) :: n
    logical, intent(in) :: quote_text
    integer :: i, start, count
    character :: ch
    if (n > len(out)) return
    if (depth > s%budget%frames) then
      if(s%foundation)then
        n=len(out)+1
      else
        call repr_put(out,n,'<depth-limit>')
      end if
      return
    end if
    start=s%nodes(id)%start
    count=s%nodes(id)%length
    select case (s%nodes(id)%tag)
    case (pn_null)
      call repr_put(out,n,'?')
    case (pn_number,pn_integer)
      call repr_put(out,n,trim(proto_number_text(s%nodes(id)%number)))
    case (pn_text)
      if (quote_text) call repr_put(out,n,"'")
      do i=0,count-1
        ch=s%text(start+i)
        if (quote_text) then
          select case (ch)
          case (achar(10)); call repr_put(out,n,achar(92)//'n'); cycle
          case (achar(13)); call repr_put(out,n,achar(92)//'r'); cycle
          case (achar(9)); call repr_put(out,n,achar(92)//'t'); cycle
          case (achar(92), "'"); call repr_put(out,n,achar(92))
          end select
        end if
        call repr_put(out,n,ch)
      end do
      if (quote_text) call repr_put(out,n,"'")
    case(pn_module)
      call repr_put(out,n,'<module:'//trim(int_text(start))//'>')
    case(pn_ref)
      call repr_put(out,n,'<external:'//trim(int_text(start))//'>')
    case (pn_array)
      call repr_put(out,n,'[')
      do i=0,count-1
        if (i > 0) call repr_put(out,n,', ')
        call node_repr(s,s%edges(start+i),out,n,.true.,depth+1)
      end do
      call repr_put(out,n,']')
    end select
  end subroutine node_repr

  subroutine print_node(s, id)
    type(prototype_state), intent(inout) :: s
    integer, intent(in) :: id
    character(s%budget%output),allocatable::out(:)
    integer::out_allocation_status
    integer :: n,a
    character(64)::numeric
    if(s%error%failed)return
    select case(s%nodes(id)%tag)
    case(pn_text)
      a=s%nodes(id)%start;n=s%nodes(id)%length
      call output_append_bytes(s,s%text(a:a+n-1));return
    case(pn_number,pn_integer)
      numeric=proto_number_text(s%nodes(id)%number)
      call output_append(s,trim(numeric),len_trim(numeric));return
    end select
    allocate(out(1),stat=out_allocation_status)
    if(out_allocation_status/=0)then
      call proto_error(s,'P002: cannot allocate runtime work buffer');return
    end if
    n=0
    call node_repr(s,id,out(1),n,.false.,0)
    if (n > len(out(1))) then
      call proto_error(s,'P002: value representation exceeds output limit')
      return
    end if
    call output_append(s,out(1),n)
  end subroutine print_node

  integer function join_node(s, id, stringify) result(joined)
    type(prototype_state), intent(inout) :: s
    integer, intent(in) :: id
    logical, intent(in) :: stringify
    character(s%budget%output),allocatable::out(:)
    integer::out_allocation_status
    integer :: i, child, n, start, count, a, b
    joined=0
    allocate(out(1),stat=out_allocation_status)
    if(out_allocation_status/=0)then
      call proto_error(s,'P002: cannot allocate runtime work buffer');return
    end if
    n=0
    if (s%nodes(id)%tag /= pn_array) then
      call proto_error(s,'P004: join expects an array')
      return
    end if
    start=s%nodes(id)%start
    count=s%nodes(id)%length
    do i=0,count-1
      child=s%edges(start+i)
      if (stringify) then
        call node_repr(s,child,out(1),n,.false.,0)
      else
        if (s%nodes(child)%tag /= pn_text) then
          call proto_error(s,'P004: S@ expects text elements')
          return
        end if
        a=s%nodes(child)%start
        b=s%nodes(child)%length
        call repr_put_bytes(out(1),n,s%text(a:a+b-1))
      end if
      if (n > len(out(1))) then
        call proto_error(s,'P002: joined text exceeds limit')
        return
      end if
    end do
    joined=new_text(s,out(1),n)
  end function join_node

  subroutine node_number(s, id, convert_text, x, ok)
    type(prototype_state), intent(in) :: s
    integer, intent(in) :: id
    logical, intent(in) :: convert_text
    real(rk), intent(out) :: x
    logical, intent(out) :: ok
    integer :: a, n
    x=0.0_rk
    ok=.false.
    if (s%nodes(id)%tag == pn_number .or. s%nodes(id)%tag == pn_integer) then
      x=s%nodes(id)%number
      ok=.true.
    else if (convert_text .and. s%nodes(id)%tag == pn_text) then
      a=s%nodes(id)%start
      n=s%nodes(id)%length
      call decimal_bytes(s%text(a:a+n-1),x,ok)
    end if
  end subroutine node_number

  recursive logical function nodes_equal(s,a,b,depth) result(same)
    type(prototype_state), intent(inout) :: s
    integer, intent(in) :: a,b,depth
    integer :: i, ax, bx, n
    same=.false.
    if(s%foundation)then
      s%comparison_work=s%comparison_work+1
      if(s%comparison_work>s%budget%work)then
        call proto_error(s,'P002: comparison work budget exceeded');return
      end if
      if(a==b)then
        same=.true.;return
      end if
      if(depth>s%budget%frames)then
        call proto_error(s,'P002: comparison depth budget exhausted');return
      end if
    end if
    if ((s%nodes(a)%tag == pn_number .or. s%nodes(a)%tag == pn_integer) .and. &
        (s%nodes(b)%tag == pn_number .or. s%nodes(b)%tag == pn_integer)) then
      same=s%nodes(a)%number == s%nodes(b)%number
      return
    end if
    if (s%nodes(a)%tag /= s%nodes(b)%tag) return
    select case (s%nodes(a)%tag)
    case (pn_null)
      same=.true.
    case (pn_number,pn_integer)
      same=s%nodes(a)%number == s%nodes(b)%number
    case (pn_text)
      n=s%nodes(a)%length
      if (n /= s%nodes(b)%length) return
      ax=s%nodes(a)%start
      bx=s%nodes(b)%start
      same=all(s%text(ax:ax+n-1) == s%text(bx:bx+n-1))
    case(pn_module,pn_ref)
      same=s%nodes(a)%start==s%nodes(b)%start
    case (pn_array)
      if (depth > s%budget%frames) return
      n=s%nodes(a)%length
      if (n /= s%nodes(b)%length) return
      ax=s%nodes(a)%start
      bx=s%nodes(b)%start
      do i=0,n-1
        if (.not. nodes_equal(s,s%edges(ax+i),s%edges(bx+i),depth+1)) return
      end do
      same=.true.
    end select
  end function nodes_equal

  integer function index_node(s,container,key,convert_text) result(id)
    type(prototype_state), intent(inout) :: s
    integer, intent(in) :: container,key
    logical, intent(in) :: convert_text
    real(rk) :: x
    logical :: ok
    integer :: index, start
    character :: ch
    id=0
    if(s%foundation.and.s%nodes(container)%tag/=pn_array.and.s%nodes(container)%tag/=pn_text)then
      call proto_error(s,'P005: indexing requires an array or text');return
    end if
    if (.not. convert_text .and. s%nodes(key)%tag /= pn_integer) then
      call proto_error(s,'P005: Oak indexing requires an integer-typed key, not text, array, or brace float')
      return
    end if
    call node_number(s,key,convert_text,x,ok)
    if (.not. ok) then
      call proto_error(s,'P005: indexing requires an integer key; original ; uses top as container')
      return
    end if
    if (abs(x) > 2147483647.0_rk) then
      call proto_error(s,'P005: index outside supported range')
      return
    end if
    if (.not. convert_text) then
      if (x /= aint(x)) then
        call proto_error(s,'P005: fractional index')
        return
      end if
    end if
    index=int(x)
    if (index < 0 .or. index >= s%nodes(container)%length) return
    start=s%nodes(container)%start
    select case (s%nodes(container)%tag)
    case (pn_array)
      id=s%edges(start+index)
    case (pn_text)
      ch=s%text(start+index)
      id=new_text(s,ch,1)
    case default
      call proto_error(s,'P005: cannot index this value')
    end select
  end function index_node

  subroutine replay_text_node(s,id)
    type(prototype_state),intent(inout)::s
    integer,intent(out)::id
    integer::a,b,n
    id=0;a=s%input_cursor
    if(a>size(s%replay))then
      call proto_error(s,'P009: input exhausted');return
    end if
    b=a
    do while(b<=size(s%replay))
      if(s%replay(b)==achar(10))exit
      b=b+1
    end do
    s%input_cursor=min(b+1,size(s%replay)+1)
    n=b-a
    if(n>0)then
      if(s%replay(b-1)==achar(13))n=n-1
    end if
    if(n>s%budget%input_line)then
      call proto_error(s,'P009: input line budget exhausted');return
    end if
    id=new_bytes(s,s%replay(a:a+n-1))
  end subroutine

  subroutine read_replay_input(buffer,n,cap,failed)
    character,pointer::buffer(:)
    integer,intent(out)::n
    integer,intent(in)::cap
    logical,intent(out)::failed
    character(1024)::raw
    integer::got,ios
    n=0;failed=.false.
    allocate(buffer(cap+1),stat=ios)
    if(ios/=0)then
      failed=.true.;return
    end if
10  continue
    got=0
    read(*,'(a)',advance='no',size=got,iostat=ios,eor=20,end=30,err=40)raw
    call append()
    if(failed)return
    goto 10
20  continue
    call append()
    if(n==cap)failed=.true.
    if(failed)return
    n=n+1;buffer(n)=achar(10)
    goto 10
30  continue
    call append()
    return
40  continue
    failed=.true.
  contains
    subroutine append()
      if(got>cap-n)then
        failed=.true.;return
      end if
      call store_bytes(buffer,n+1,raw(:got));n=n+got
    end subroutine
  end subroutine

  subroutine read_text_node(s,id)
    type(prototype_state), intent(inout) :: s
    integer, intent(out) :: id
    character(s%budget%input_line+1),allocatable::raw(:)
    integer::raw_allocation_status
    integer :: got, ios
    id=0
    allocate(raw(1),stat=raw_allocation_status)
    if(raw_allocation_status/=0)then
      call proto_error(s,'P002: cannot allocate runtime work buffer');return
    end if
    id=0
    if(associated(s%replay))then
      call replay_text_node(s,id);return
    end if
    got=0
    read(*,'(a)',advance='no',size=got,iostat=ios,eor=10,end=20,err=30) raw(1)
    call proto_error(s,'P009: input line budget exhausted')
    return
10  continue
    if (got > s%budget%input_line) then
      call proto_error(s,'P009: input line budget exhausted')
      return
    end if
    s%input_used=s%input_used+got+1
    if(s%input_used>s%budget%input)then
      call proto_error(s,'P009: input byte budget exhausted');return
    end if
    id=new_text(s,raw(1),got)
    return
20  continue
    if (got > 0) then
      s%input_used=s%input_used+got
      if(s%input_used>s%budget%input)then
        call proto_error(s,'P009: input byte budget exhausted');return
      end if
      id=new_text(s,raw(1),got)
    else
      call proto_error(s,'P009: input exhausted (Oak would push null)')
    end if
    return
30  continue
    call proto_error(s,'P009: input read failed')
  end subroutine read_text_node

  subroutine at_call(s)
    type(prototype_state), intent(inout) :: s
    integer :: sym, arg, id, i, start, count, first, argid, a, n
    character :: command
    character(s%budget%output),allocatable::repr(:)
    integer::repr_allocation_status
    real(rk) :: x
    logical :: ok
    sym=proto_pop(s)
    if(s%foundation)then
      if(s%error%failed)return
      if(s%nodes(sym)%tag==pn_ref)then
        call apply_direct_reference(s,sym)
        return
      end if
      if(s%nodes(sym)%tag==pn_text.and.s%nodes(sym)%length==1)then
        command=s%text(s%nodes(sym)%start)
        if(index('xotdb',command)>0)then
          call stack_command(s,command);return
        end if
        if(command=='h')then
          s%halted=.true.;return
        else if(command=='R')then
          if(s%rp==0)then
            call proto_error(s,'P013: return stack underflow');return
          end if
          s%rp=s%rp-1
          if(s%depth/=s%return_depth(s%rp))then
            call proto_error(s,'P013: subroutine returned with unmatched construction depth');return
          end if
          s%pending_jump=.true.
          s%jump_line=s%return_line(s%rp);s%jump_column=s%return_column(s%rp)
          return
        end if
      end if
      if(s%nodes(sym)%tag/=pn_text.or.s%nodes(sym)%length/=1)then
        call proto_error(s,'P006: @ requires a reference or one-character command');return
      end if
    end if
    arg=proto_pop(s)
    if (s%error%failed) return
    if (s%nodes(sym)%tag /= pn_text .or. s%nodes(sym)%length /= 1) then
      call proto_error(s,'P006: only single-character @ commands are in this ablation')
      return
    end if
    command=s%text(s%nodes(sym)%start)
    if(s%foundation)then
      select case(command)
      case('i','g','G','r','a','C','k')
        call foundation_at(s,command,arg)
        return
      end select
    end if
    select case (command)
    case ('p','P')
      select case (s%nodes(arg)%tag)
      case (pn_array)
        start=s%nodes(arg)%start
        count=s%nodes(arg)%length
        do i=0,count-1
          id=s%edges(start+i)
          if (s%nodes(id)%tag /= pn_text) then
            call proto_error(s,'P004: Oak printFx passes each item to print, which requires text')
            exit
          end if
          call print_node(s,id)
        end do
      case (pn_text)
        call print_node(s,arg)
      case default
        call proto_error(s,'P004: p@/P@ expect an array or text')
      end select
      if (command == 'P') call output_append(s,achar(10),1)
    case ('S')
      id=join_node(s,arg,.false.)
      call proto_push(s,id)
    case ('s')
    allocate(repr(1),stat=repr_allocation_status)
    if(repr_allocation_status/=0)then
      call proto_error(s,'P002: cannot allocate runtime work buffer');return
    end if

      n=0
      call node_repr(s,arg,repr(1),n,.false.,0)
      if (n > len(repr(1))) then
        call proto_error(s,'P002: string representation exceeds limit')
        return
      end if
      id=new_text(s,repr(1),n)
      call proto_push(s,id)
    case ('C')
      if (.not. s%repairs) then
        call proto_error(s,'P006: source C@ calls Ctx instead of sc; use --repair to test std.int')
        return
      end if
      if (s%nodes(arg)%tag /= pn_array .or. s%nodes(arg)%length /= 2) then
        call proto_error(s,'P006: repaired C@ currently supports [name, argument] only')
        return
      end if
      first=s%edges(s%nodes(arg)%start)
      argid=s%edges(s%nodes(arg)%start+1)
      a=s%nodes(first)%start
      n=s%nodes(first)%length
      if (s%nodes(first)%tag /= pn_text) then
        call proto_error(s,'P006: C@ function name must be text')
        return
      end if
      if (byte_string(s%text(a:a+n-1)) /= 'int') then
        call proto_error(s,'P006: repaired C@ only implements std.int in this milestone')
        return
      end if
      call node_number(s,argid,.true.,x,ok)
      if (.not. ok) then
        ! std.int returns null when it cannot convert. Preserve that result.
        id=0
      else
        id=new_number(s,aint(x),.true.)
      end if
      call proto_push(s,id)
    case default
      call proto_error(s,'P006: @ command not yet ported: '//command)
    end select
  end subroutine at_call

  ! A single value-operation implementation, shared by native byte execution
  ! and the predecoded-IR Fortran target. No file/source parsing occurs here.
  subroutine prototype_step(s,ch,escape_byte,escape_available,nl,next_line,next_column)
    type(prototype_state),intent(inout)::s
    character,intent(in)::ch,escape_byte
    logical,intent(in)::escape_available
    integer,intent(in)::nl
    integer,intent(inout)::next_line,next_column
    integer::a,b,id,j,aa,bb,an,bn
    character::escaped
    character(s%budget%output),allocatable::scratch(:)
    integer::scratch_allocation_status
    character(*),parameter::pushables='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 <>,./'// &
      achar(34)//achar(39)
    real(rk)::x,y,z
    logical::ok,ok2,taken,integer_result,integer_coordinates
    escaped=escape_byte
  if (index(pushables,ch) > 0) then
    id=character_node(s,ch)
    call proto_push(s,id)
  else
    select case (ch)
    case ('[')
      call open_frame(s,0)
    case ('{')
      call open_frame(s,1)
    case (']')
      id=close_frame(s,0)
      call proto_push(s,id)
    case ('}')
      a=close_frame(s,1)
      if (.not. s%error%failed) then
        b=join_node(s,a,.true.)
        call node_number(s,b,.true.,x,ok)
        if (.not. ok) then
          call proto_error(s,'P004: brace construction is not a decimal number')
        else
          id=new_number(s,x)
          call proto_push(s,id)
        end if
      end if
    case (achar(92))
      if (.not.escape_available) then
        call proto_error(s,'P003: trailing escape at end of line')
      else
        if (escaped == 'n') escaped=achar(10)
        id=character_node(s,escaped)
        call proto_push(s,id)
        next_column=next_column+1
      end if
    case ('_')
      a=proto_pop(s)
    case ('%')
      a=proto_pop(s)
      call proto_push(s,a)
      call proto_push(s,a)
    case ('`')
      call read_text_node(s,id)
      call proto_push(s,id)
    case ('$', '@')
      if (ch == '@') then
        call at_call(s)
      else
        a=proto_pop(s)
        call print_node(s,a)
      end if
    case ('+', '-', '*', '|')
      a=proto_pop(s)
      b=proto_pop(s)
      if (s%error%failed) return
      if (ch == '+' .and. s%nodes(a)%tag == pn_text .and. s%nodes(b)%tag == pn_text) then
        aa=s%nodes(a)%start
        an=s%nodes(a)%length
        bb=s%nodes(b)%start
        bn=s%nodes(b)%length
        if (an+bn > s%budget%output) then
          call proto_error(s,'P002: concatenation exceeds limit')
          return
        end if
    allocate(scratch(1),stat=scratch_allocation_status)
    if(scratch_allocation_status/=0)then
      call proto_error(s,'P002: cannot allocate runtime work buffer');return
    end if
        call string_from_bytes(scratch(1)(1:an),s%text(aa:aa+an-1))
        call string_from_bytes(scratch(1)(an+1:an+bn),s%text(bb:bb+bn-1))
        id=new_text(s,scratch(1),an+bn)
        call proto_push(s,id)
      else
        call node_number(s,a,.false.,y,ok)
        call node_number(s,b,.false.,x,ok2)
        if (.not. ok .or. .not. ok2) then
          call proto_error(s,'P004: arithmetic operands have incompatible types')
          return
        end if
        z=0.0_rk
        select case (ch)
        case ('+'); z=y+x
        case ('-'); z=x-y
        case ('*'); z=x*y
        case ('|')
          if (y == 0.0_rk) then
            call proto_error(s,'P010: division by zero (safe-port diagnostic)')
            return
          end if
          z=x/y
        end select
        integer_result=s%nodes(a)%tag == pn_integer .and. s%nodes(b)%tag == pn_integer
        if (ch == '|') integer_result=.false.
        id=new_number(s,z,integer_result)
        call proto_push(s,id)
      end if
    case ('~')
      a=proto_pop(s)
      call node_number(s,a,.false.,x,ok)
      if (.not. ok) then
        call proto_error(s,'P004: negation requires a number')
      else
        integer_result=s%nodes(a)%tag == pn_integer
        id=new_number(s,-x,integer_result)
        call proto_push(s,id)
      end if
    case (':')
      a=proto_pop(s)
      if (s%nodes(a)%tag /= pn_array) then
        call proto_error(s,'P004: : expects an array')
      else
        do j=0,s%nodes(a)%length-1
          call proto_push(s,s%edges(s%nodes(a)%start+j))
        end do
      end if
    case (';')
      a=proto_pop(s)
      b=proto_pop(s)
      if (s%error%failed) return
      if (s%repairs) then
        id=index_node(s,b,a,.true.)
      else
        id=index_node(s,a,b,.false.)
      end if
      call proto_push(s,id)
    case ('^','=')
      a=proto_pop(s)
      b=proto_pop(s)
      call node_number(s,a,s%repairs,x,ok)
      call node_number(s,b,s%repairs,y,ok2)
      if (.not. ok .or. .not. ok2) then
        call proto_error(s,'P007: gotoVec subtracts from text; numeric coordinates required without --repair')
        return
      end if
      integer_coordinates=s%nodes(a)%tag == pn_integer .and. s%nodes(b)%tag == pn_integer
      taken=.true.
      if (ch == '=') then
        a=proto_pop(s)
        b=proto_pop(s)
        s%comparison_work=0
        taken=nodes_equal(s,a,b,0)
      end if
      if (taken) then
        if (.not. s%repairs .and. .not. integer_coordinates) then
          call proto_error(s,'P007: Oak execution indices require integers; brace numbers are floats')
          return
        end if
        if (x /= aint(x) .or. y /= aint(y) .or. x < 0 .or. x > s%budget%source .or. y < 1 .or. y > nl) then
          call proto_error(s,'P007: invalid coordinate; line is 1-based, effective column is 0-based')
          return
        end if
        next_line=int(y)-1
        next_column=int(x)
      end if
    case ('#')
      ! Match source's line++ then unconditional char++ (not the docs).
      next_line=s%line+1
      if(s%foundation)next_column=0
    case ('&')
      call proto_error(s,'P006: objects are outside the current ablation')
    case default
      ! Undefined characters are ignored by Oak's Env lookup.
    end select
  end if
  end subroutine prototype_step

  include 'prototype_driver.inc'

  subroutine write_json_string(text,n)
    character(*),intent(in)::text
    integer,intent(in)::n
    character::bytes(n)
    integer::i
    do i=1,n
      bytes(i)=text(i:i)
    end do
    call write_json_bytes(bytes,n)
  end subroutine write_json_string

  recursive subroutine write_node_json(s,id,depth,work,truncated)
    type(prototype_state), intent(in) :: s
    integer, intent(in) :: id,depth
    integer,intent(inout)::work
    logical,intent(inout)::truncated
    integer :: i,a,n
    if(depth>s%budget%frames.or.work<=0)then
      write(*,'(a)',advance='no')'"<diagnostic-limit>"';truncated=.true.;return
    end if
    work=work-1
    select case (s%nodes(id)%tag)
    case (pn_null)
      write(*,'(a)',advance='no') 'null'
    case (pn_number,pn_integer)
      write(*,'(a)',advance='no') trim(number_text(s%nodes(id)%number))
    case (pn_text)
      a=s%nodes(id)%start
      n=s%nodes(id)%length
      call write_json_bytes(s%text(a:a+n-1),n)
    case(pn_module)
      write(*,'(a)',advance='no') '{"module":'//trim(int_text(s%nodes(id)%start))//'}'
    case(pn_ref)
      write(*,'(a)',advance='no') '{"external":'//trim(int_text(s%nodes(id)%start))// &
        ',"arity":'//trim(int_text(s%nodes(id)%length))//'}'
    case (pn_array)
      write(*,'(a)',advance='no') '['
      do i=0,s%nodes(id)%length-1
        if (i > 0) write(*,'(a)',advance='no') ','
        call write_node_json(s,s%edges(s%nodes(id)%start+i),depth+1,work,truncated)
        if(work<=0)exit
      end do
      write(*,'(a)',advance='no') ']'
    end select
  end subroutine write_node_json

  subroutine write_prototype_json(s)
    type(prototype_state), intent(in) :: s
    integer :: i,work
    logical::truncated
    work=s%budget%work;truncated=.false.
    if(s%foundation)then
      write(*,'(a)',advance='no') '{"mode":"foundation","repairs":'
    else
      write(*,'(a)',advance='no') '{"mode":"prototype","repairs":'
    end if
    if (s%repairs) then
      write(*,'(a)',advance='no') 'true'
    else
      write(*,'(a)',advance='no') 'false'
    end if
    write(*,'(a)',advance='no') ',"ok":'
    if (s%error%failed) then
      write(*,'(a)',advance='no') 'false'
    else
      write(*,'(a)',advance='no') 'true'
    end if
    write(*,'(a)',advance='no') ',"steps":'//trim(int_text(s%steps))//',"output":'
    call write_json_bytes(s%output(:s%output_length),s%output_length)
    if(s%foundation)then
      write(*,'(a)',advance='no')',"output_hex":'
      call write_hex_bytes(s%output(:s%output_length))
    end if
    write(*,'(a)',advance='no') ',"stack":['
    do i=0,s%sp-1
      if (i > 0) write(*,'(a)',advance='no') ','
      call write_node_json(s,s%stack(i),0,work,truncated)
      if(work<=0)then
        truncated=.true.;exit
      end if
    end do
    write(*,'(a)',advance='no') '],"open_frames":'//trim(int_text(s%depth))//',"error":'
    if (s%error%failed) then
      call write_json_string(trim(s%error%message),len_trim(s%error%message))
      write(*,'(a)',advance='no') ',"line":'//trim(int_text(s%error%line))// &
        ',"column":'//trim(int_text(s%error%column))
    else
      write(*,'(a)',advance='no') 'null'
    end if
    if(s%foundation)then
      write(*,'(a)',advance='no')',"collections":'//trim(int_text(s%collections))// &
        ',"stack_depth":'//trim(int_text(s%sp))//',"stack_truncated":'
      if(truncated)then
        write(*,'(a)',advance='no')'true'
      else
        write(*,'(a)',advance='no')'false'
      end if
    end if
    write(*,'(a)') '}'
  end subroutine write_prototype_json
  include 'byte_helpers.inc'
  include 'foundation_methods.inc'
  include 'typed_methods.inc'
end module urotif_prototype
