! F95 decoded-IR executor. Included after generated urotif_tables and the
! shared value core. It does not read Urotif source or invoke the frontend.
module urotif_target
  use urotif_prototype
  use urotif_tables
  implicit none
contains
  integer function ir_coordinate(row,col) result(pc)
    integer,intent(in)::row,col
    pc=code_count-1
    if(row<0.or.row>=source_lines)return
    pc=line_start(row)+min(col,line_length(row))
  end function

  integer function cached_reference(s,slot) result(id)
    type(prototype_state),intent(inout)::s
    integer,intent(in)::slot
    id=s%ref_cache(slot)
    if(id/=0)return
    id=new_node(s,pn_ref)
    if(s%error%failed)return
    s%nodes(id)%start=slot;s%nodes(id)%length=symbol_arity(slot)
    s%nodes(id)%number=real(symbol_kind(slot),rk);s%ref_cache(slot)=id
  end function

  integer function cached_literal(s,pool,as_text) result(id)
    type(prototype_state),intent(inout)::s
    integer,intent(in)::pool
    logical,intent(in)::as_text
    integer::j,n,a,child
    character(2048)::text
    if(as_text)then
      id=s%literal_cache(pool)
    else
      id=s%array_cache(pool)
    end if
    if(id/=0)return
    a=literal_start(pool);n=literal_length(pool)
    if(as_text)then
      do j=0,n-1
        text(j+1:j+1)=achar(literal_bytes(a+j))
      end do
      id=new_text(s,text,n)
      s%literal_cache(pool)=id
    else
      if(s%edge_count+n>s%budget%edges)then
        call proto_error(s,'P002: cached array exceeds edge budget');return
      end if
      ! No collection within an instruction; these IDs remain live until the
      ! array is rooted. Character IDs are independently rooted by the cache.
      a=s%edge_count
      do j=0,n-1
        child=character_node(s,achar(literal_bytes(literal_start(pool)+j)))
        if(s%error%failed)return
        s%edges(a+j)=child
      end do
      id=new_node(s,pn_array)
      if(s%error%failed)return
      s%nodes(id)%start=a;s%nodes(id)%length=n;s%edge_count=a+n
      s%array_cache(pool)=id
    end if
  end function

  subroutine target_run(s,fuel,pc,input,stream)
    type(prototype_state),intent(inout)::s
    integer,intent(in)::fuel
    integer,intent(out)::pc
    character,target,optional,intent(in)::input(:)
    logical,optional,intent(in)::stream
    integer::op,arg,cost,next,peak,id,nl,nc
    character::ch,escape_byte
    logical::escaped,fast
    call proto_init(s,.true.,.true.,program_limits)
    if(present(input))s%replay=>input
    if(present(stream))s%live_output=stream
    pc=entry_pc
    do while(.not.s%error%failed)
      if(pc<0.or.pc>=code_count)then
        call proto_error(s,'P007: decoded instruction index outside program');exit
      end if
      s%line=ir_line(pc)-1;s%column=ir_column(pc)-1
      op=ir_op(pc);arg=ir_arg(pc);cost=ir_cost(pc);next=ir_next(pc)
      if(op==0)exit
      if(op==3)then
        pc=next;cycle
      end if
      if(op==24)then
        call maybe_collect(s,literal_length(arg))
      else
        call maybe_collect(s)
      end if
      if(s%error%failed)exit
      fast=op>=23.and.op<=26
      if(fast)then
        peak=max(1,cost-2)
        if(op==23.or.op==25)peak=max(2,cost-4)
        if(cost>fuel-s%steps.or.s%depth==s%budget%frames.or.peak>s%budget%stack-s%sp)then
          arg=0
          if(op==26)arg=1
          op=5;cost=1;next=pc+1;fast=.false.
        end if
      end if
      if(cost>fuel-s%steps)then
        call proto_error(s,'P008: instruction fuel exhausted');exit
      end if
      s%steps=s%steps+cost
      if(op==27)then
        id=character_node(s,achar(arg));call proto_push(s,id)
      else if(fast)then
        select case(op)
        case(23);id=cached_reference(s,arg)
        case(24,25);id=cached_literal(s,arg,op==25)
        case(26);id=new_number(s,ir_number(pc))
        end select
        call proto_push(s,id)
      else
        escaped=.true.;escape_byte=achar(0);ch=achar(0)
        select case(op)
        case(1);ch=achar(arg)
        case(4)
          ch=achar(92);escaped=arg<256
          if(escaped)escape_byte=achar(arg)
        case(5)
          ch='['
          if(arg==1)ch='{'
        case(6)
          ch=']'
          if(arg==1)ch='}'
        case(7);ch='%'
        case(8);ch='_'
        case(9);ch='+'
        case(10);ch='-'
        case(11);ch='*'
        case(12);ch='|'
        case(13);ch='~'
        case(14);ch='$'
        case(15);ch=':'
        case(16);ch=';'
        case(17);ch='@'
        case(18);ch='`'
        case(19);ch='^'
        case(20);ch='='
        case(21);ch='#'
        case(22);ch='&'
        end select
        nl=s%line;nc=s%column+1
        call prototype_step(s,ch,escape_byte,escaped,source_lines,nl,nc)
        if(op==19.or.op==20)next=ir_coordinate(nl,nc)
        if(s%pending_jump)then
          nl=s%jump_line;nc=s%jump_column;s%pending_jump=.false.
          if(nl<0.or.nl>=source_lines.or.nc<0.or.nc>s%budget%source)then
            call proto_error(s,'P007: call/return coordinate outside source')
          else
            next=ir_coordinate(nl,nc)
          end if
        end if
      end if
      if(s%error%failed.or.s%halted)exit
      pc=next
    end do
    if(.not.s%error%failed.and.s%depth/=0)call proto_error(s,'P003: unclosed construction frame')
  end subroutine

  subroutine target_report(s,pc)
    type(prototype_state),intent(in)::s
    integer,intent(in)::pc
    integer::status,ios
    status=0
    if(s%error%failed)then
      read(s%error%message(2:4),'(i3)',iostat=ios)status
      if(ios/=0)status=7
    end if
    write(*,'(a)',advance='no')'{"status":'//trim(int_text(status))//',"output":'
    call write_json_bytes(s%output(:s%output_length),s%output_length)
    write(*,'(a)',advance='no')',"output_hex":'
    call write_hex_bytes(s%output(:s%output_length))
    write(*,'(a)')',"steps":'//trim(int_text(s%steps))//',"line":'//trim(int_text(ir_line(pc)))// &
      ',"column":'//trim(int_text(ir_column(pc)))//',"collections":'//trim(int_text(s%collections))// &
      ',"stack_depth":'//trim(int_text(s%sp))//'}'
  end subroutine
end module urotif_target
