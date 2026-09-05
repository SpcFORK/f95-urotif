  subroutine maybe_collect(s,extra_edges)
    type(prototype_state),intent(inout)::s
    integer,optional,intent(in)::extra_edges
    integer::needed
    needed=s%sp
    if(present(extra_edges))needed=max(needed,extra_edges)
    if(s%node_count-s%free_count>s%budget%nodes-16.or. &
       s%edge_count>s%budget%edges-min(s%budget%edges/2,needed)-16.or. &
       s%text_length>s%budget%text-min(s%budget%text/2,s%budget%output)-16)call collect_values(s)
  end subroutine

  integer function character_node(s,ch) result(id)
    type(prototype_state),intent(inout)::s
    character,intent(in)::ch
    integer::code
    code=iachar(ch)
    if(s%foundation)then
      id=s%char_cache(code)
      if(id/=0)return
    end if
    id=new_text(s,ch,1)
    if(s%foundation)s%char_cache(code)=id
  end function

  subroutine collect_values(s)
    type(prototype_state),intent(inout)::s
    logical::marked(0:s%budget%nodes-1)
    integer::work(0:s%budget%nodes-1),fresh_edges(0:s%budget%edges-1),head,tail,id,i,j,a,n,ec,tc
    character::fresh_text(s%budget%text)
    marked=.false.;marked(0)=.true.;head=0;tail=0
    do i=0,s%sp-1
      call visit(s%stack(i))
    end do
    do i=0,255
      call visit(s%char_cache(i))
      call visit(s%ref_cache(i))
    end do
    do i=0,31
      call visit(s%module_cache(i))
    end do
    do i=0,1023
      call visit(s%array_cache(i));call visit(s%literal_cache(i))
    end do
    do while(head<tail)
      id=work(head);head=head+1
      if(s%nodes(id)%tag==pn_array)then
        a=s%nodes(id)%start
        do j=0,s%nodes(id)%length-1
          call visit(s%edges(a+j))
        end do
      end if
    end do
    ec=0;tc=0;s%free_count=0
    do id=1,s%node_count-1
      if(.not.marked(id))then
        s%free_nodes(s%free_count)=id;s%free_count=s%free_count+1
        s%nodes(id)%tag=pn_null
        cycle
      end if
      a=s%nodes(id)%start;n=s%nodes(id)%length
      if(s%nodes(id)%tag==pn_array)then
        fresh_edges(ec:ec+n-1)=s%edges(a:a+n-1)
        s%nodes(id)%start=ec;ec=ec+n
      else if(s%nodes(id)%tag==pn_text)then
        if(n>0)fresh_text(tc+1:tc+n)=s%text(a:a+n-1)
        s%nodes(id)%start=tc+1;tc=tc+n
      end if
    end do
    s%edges(0:ec-1)=fresh_edges(0:ec-1)
    if(tc>0)s%text(1:tc)=fresh_text(1:tc)
    s%edge_count=ec;s%text_length=tc;s%collections=s%collections+1
  contains
    subroutine visit(value_id)
      integer,intent(in)::value_id
      if(marked(value_id))return
      marked(value_id)=.true.;work(tail)=value_id;tail=tail+1
    end subroutine
  end subroutine collect_values

  subroutine external_name(s,id,name,n)
    type(prototype_state),intent(inout)::s
    integer,intent(in)::id
    character(*),intent(out)::name
    integer,intent(out)::n
    integer::i,child,a,b
    name='';n=0
    if(s%nodes(id)%tag==pn_text)then
      n=s%nodes(id)%length;a=s%nodes(id)%start
      if(n>len(name))then
        call proto_error(s,'P011: external name exceeds 127 bytes');return
      end if
      name(1:n)=byte_string(s%text(a:a+n-1))
    else if(s%nodes(id)%tag==pn_array)then
      do i=0,s%nodes(id)%length-1
        child=s%edges(s%nodes(id)%start+i)
        if(s%nodes(child)%tag/=pn_text)then
          call proto_error(s,'P011: external names must contain text only');return
        end if
        a=s%nodes(child)%start;b=s%nodes(child)%length
        if(n+b>len(name))then
          call proto_error(s,'P011: external name exceeds 127 bytes');return
        end if
        name(n+1:n+b)=byte_string(s%text(a:a+b-1));n=n+b
      end do
    else
      call proto_error(s,'P011: expected external name as text or character array')
    end if
  end subroutine

  integer function resolve_reference(s,mode,module_id,name_id) result(ref)
    type(prototype_state),intent(inout)::s
    integer,intent(in)::mode,module_id,name_id
    character(128)::name
    character(256)::message
    integer::n,id,arity,kind,status
    ref=0
    call external_name(s,name_id,name,n)
    if(s%error%failed)return
    call uf_host_lookup(mode,module_id,name(1:n),id,arity,kind,status,message)
    if(status/=0)then
      call proto_error(s,'P011: '//trim(message));return
    end if
    ref=s%ref_cache(id)
    if(ref/=0)return
    ref=new_node(s,pn_ref)
    if(s%error%failed)return
    s%nodes(ref)%start=id;s%nodes(ref)%length=arity;s%nodes(ref)%number=real(kind,rk)
    s%ref_cache(id)=ref
  end function

  subroutine apply_reference(s,ref,args,n)
    type(prototype_state),intent(inout)::s
    integer,intent(in)::ref,args(0:7),n
    integer::kind,id,first,i,status,outlen
    real(rk)::values(8),x
    logical::ok
    character(256)::message
    character(s%budget%output),allocatable::repr(:)
    integer::repr_allocation_status
    if(s%error%failed)return
    if(s%nodes(ref)%tag/=pn_ref)then
      call proto_error(s,'P012: application requires an external reference');return
    end if
    if(n/=s%nodes(ref)%length.or.n>8.or.n<0)then
      call proto_error(s,'P012: external arity mismatch');return
    end if
    kind=int(s%nodes(ref)%number)
    if(kind==7)then
      call apply_typed_reference(s,ref,args,n);return
    end if
    if(kind/=0)then
      first=args(0)
      select case(kind)
      case(1,2)
        call node_number(s,first,.true.,x,ok)
        if(.not.ok)then
          call proto_error(s,'P012: numeric conversion requires a finite decimal');return
        end if
        if(kind==1)then
          if(abs(x)>9007199254740991.0_rk)then
            call proto_error(s,'P012: int exceeds the exact portable integer range');return
          end if
          id=new_number(s,aint(x),.true.)
        else
          id=new_number(s,x)
        end if
      case(3)
    allocate(repr(1),stat=repr_allocation_status)
    if(repr_allocation_status/=0)then
      call proto_error(s,'P002: cannot allocate conversion buffer');return
    end if

        outlen=0
        call node_repr(s,first,repr(1),outlen,.false.,0)
        if(outlen>len(repr(1)))then
          call proto_error(s,'P002: string conversion exceeds limit');return
        end if
        id=new_text(s,repr(1),outlen)
      case(4)
        if(s%nodes(first)%tag/=pn_text.and.s%nodes(first)%tag/=pn_array)then
          call proto_error(s,'P012: len requires text or array');return
        end if
        id=new_number(s,real(s%nodes(first)%length,rk),.true.)
      case default
        call proto_error(s,'P012: unknown standard operation');return
      end select
    else
      do i=0,n-1
        call node_number(s,args(i),.false.,values(i+1),ok)
        if(.not.ok)then
          call proto_error(s,'P012: foreign numeric arguments require explicit conversion');return
        end if
      end do
      call uf_host_apply(s%nodes(ref)%start,values,n,x,status,message)
      if(status/=0)then
        call proto_error(s,'P012: '//trim(message));return
      end if
      id=new_number(s,x)
    end if
    call proto_push(s,id)
  end subroutine

  subroutine apply_direct_reference(s,ref)
    type(prototype_state),intent(inout)::s
    integer,intent(in)::ref
    integer::args(0:7),n,i
    n=s%nodes(ref)%length
    if(n<0.or.n>8)then
      call proto_error(s,'P012: invalid external signature');return
    end if
    do i=n-1,0,-1
      args(i)=proto_pop(s)
    end do
    call apply_reference(s,ref,args,n)
  end subroutine

  subroutine foundation_at(s,command,arg)
    type(prototype_state),intent(inout)::s
    character,intent(in)::command
    integer,intent(in)::arg
    integer::n,a,b,ref,id,arity,kind,status,args(0:7),i
    character(128)::name
    character(256)::message
    real(rk)::x,y
    logical::ok,ok2
    select case(command)
    case('i')
      call external_name(s,arg,name,n)
      if(s%error%failed)return
      call uf_host_lookup(0,0,name(1:n),id,arity,kind,status,message)
      if(status/=0)then
        call proto_error(s,'P011: '//trim(message));return
      end if
      ref=s%module_cache(id)
      if(ref==0)then
        ref=new_node(s,pn_module)
        if(s%error%failed)return
        s%nodes(ref)%start=id;s%module_cache(id)=ref
      end if
      call proto_push(s,ref)
    case('G','r')
      n=1
      if(command=='r')n=2
      ref=resolve_reference(s,n,0,arg)
      call proto_push(s,ref)
    case('g')
      if(s%nodes(arg)%tag/=pn_array.or.s%nodes(arg)%length/=2)then
        call proto_error(s,'P011: g@ requires [module, name]');return
      end if
      a=s%edges(s%nodes(arg)%start);b=s%edges(s%nodes(arg)%start+1)
      if(s%nodes(a)%tag/=pn_module)then
        call proto_error(s,'P011: g@ first item must be an imported module');return
      end if
      ref=resolve_reference(s,1,s%nodes(a)%start,b)
      call proto_push(s,ref)
    case('C','a')
      if(s%nodes(arg)%tag/=pn_array)then
        call proto_error(s,'P012: application requires an argument array');return
      end if
      n=s%nodes(arg)%length-1
      if(n<0.or.n>8)then
        call proto_error(s,'P012: application array supports 0..8 arguments');return
      end if
      ref=s%edges(s%nodes(arg)%start)
      if(command=='C')ref=resolve_reference(s,1,0,ref)
      do i=0,n-1
        args(i)=s%edges(s%nodes(arg)%start+1+i)
      end do
      call apply_reference(s,ref,args,n)
    case('k')
      if(s%nodes(arg)%tag/=pn_array.or.s%nodes(arg)%length/=2)then
        call proto_error(s,'P013: k@ requires [line, column]');return
      end if
      a=s%edges(s%nodes(arg)%start);b=s%edges(s%nodes(arg)%start+1)
      call node_number(s,a,.true.,y,ok)
      call node_number(s,b,.true.,x,ok2)
      if(.not.ok.or..not.ok2)then
        call proto_error(s,'P013: call coordinates must be integral');return
      end if
      if(x<0.or.x>s%budget%source.or.y<1.or.y>s%budget%source.or.x/=aint(x).or.y/=aint(y))then
        call proto_error(s,'P013: invalid call coordinates');return
      end if
      if(s%rp==s%budget%returns)then
        call proto_error(s,'P013: return stack budget exhausted');return
      end if
      s%return_line(s%rp)=s%line;s%return_column(s%rp)=s%column+1;s%return_depth(s%rp)=s%depth
      s%rp=s%rp+1;s%pending_jump=.true.;s%jump_line=int(y)-1;s%jump_column=int(x)
    end select
  end subroutine

  ! Foundation stack vocabulary. Active construction frames remain isolated.
  ! x@ swap; o@ over; t@ rotate; d@ depth; b@ pack N values in source order.
  subroutine stack_command(s,command)
    type(prototype_state),intent(inout)::s
    character,intent(in)::command
    integer::active,a,b,c,n,id,i,start
    real(rk)::x
    logical::ok
    active=s%sp-s%bases(s%depth)
    select case(command)
    case('x','o','t')
      n=2
      if(command=='t')n=3
      if(active<n)then
        call proto_error(s,'P001: stack operation crosses active frame');return
      end if
      a=s%stack(s%sp-n);b=s%stack(s%sp-n+1)
      select case(command)
      case('x')
        s%stack(s%sp-2)=b;s%stack(s%sp-1)=a
      case('o')
        call proto_push(s,a)
      case('t')
        c=s%stack(s%sp-1)
        s%stack(s%sp-3)=b;s%stack(s%sp-2)=c;s%stack(s%sp-1)=a
      end select
    case('d')
      id=new_number(s,real(active,rk),.true.);call proto_push(s,id)
    case('b')
      a=proto_pop(s)
      if(s%error%failed)return
      call node_number(s,a,.false.,x,ok)
      if(.not.ok)then
        call proto_error(s,'P004: pack count must be numeric');return
      end if
      if(x<0.or.x/=aint(x))then
        call proto_error(s,'P004: pack count must be a nonnegative integer');return
      end if
      if(x>s%sp-s%bases(s%depth))then
        call proto_error(s,'P001: pack crosses active frame');return
      end if
      n=int(x)
      if(n>s%budget%edges-s%edge_count)then
        call proto_error(s,'P002: packed array exceeds edge budget');return
      end if
      id=new_node(s,pn_array)
      if(s%error%failed)return
      start=s%edge_count;s%nodes(id)%start=start;s%nodes(id)%length=n
      do i=0,n-1
        s%edges(start+i)=s%stack(s%sp-n+i)
      end do
      s%edge_count=start+n;s%sp=s%sp-n
      call proto_push(s,id)
    end select
  end subroutine
