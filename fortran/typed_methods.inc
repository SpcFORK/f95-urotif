  ! F95 marshalling: foreign code sees values, never VM handles/arena pointers.
  ! Native C pointers are constructed only in the separately linked adapter.
  subroutine apply_typed_reference(s,ref,args,n)
    type(prototype_state),intent(inout)::s
    integer,intent(in)::ref,args(0:7),n
    integer::kinds(0:7),starts(0:7),lengths(0:7),result_kind,status
    integer::i,j,a,child,nb,nv,bc,vc,outb,outv,id,ios,start,available
    real(rk)::numbers(0:7),number_result
    character,allocatable::bytes(:),result_bytes(:)
    real(rk),allocatable::vectors(:),result_vector(:)
    character(256)::message
    call uf_host_signature(s%nodes(ref)%start,kinds,result_kind,status,message)
    if(status/=0)then
      call proto_error(s,'P012: '//trim(message));return
    end if
    nb=0;nv=0;starts=0;lengths=0;numbers=0.0_rk
    do i=0,n-1
      a=args(i)
      select case(kinds(i))
      case(1)
        if(s%nodes(a)%tag/=pn_number.and.s%nodes(a)%tag/=pn_integer)then
          call proto_error(s,'P012: typed number argument requires explicit conversion');return
        end if
        numbers(i)=s%nodes(a)%number
      case(2)
        if(s%nodes(a)%tag/=pn_text)then
          call proto_error(s,'P012: typed bytes argument requires text/byte value');return
        end if
        lengths(i)=s%nodes(a)%length;starts(i)=nb
        if(lengths(i)>s%budget%text-nb)then
          call proto_error(s,'P002: aggregate foreign byte arguments exceed text budget');return
        end if
        nb=nb+lengths(i)
      case(3)
        if(s%nodes(a)%tag/=pn_array)then
          call proto_error(s,'P012: typed vector argument requires a numeric array');return
        end if
        lengths(i)=s%nodes(a)%length;starts(i)=nv
        if(lengths(i)>s%budget%edges-nv)then
          call proto_error(s,'P002: aggregate foreign vector arguments exceed edge budget');return
        end if
        do j=0,lengths(i)-1
          child=s%edges(s%nodes(a)%start+j)
          if(s%nodes(child)%tag/=pn_number.and.s%nodes(child)%tag/=pn_integer)then
            call proto_error(s,'P012: foreign vectors must be flat numeric arrays');return
          end if
        end do
        nv=nv+lengths(i)
      case default
        call proto_error(s,'P012: unsupported typed argument signature');return
      end select
    end do
    bc=0;vc=0
    if(result_kind==2)bc=min(s%budget%output,s%budget%text-s%text_length)
    if(result_kind==3)then
      available=s%budget%nodes-s%node_count+s%free_count-1
      vc=max(0,min(s%budget%output/8,s%budget%edges-s%edge_count,available))
    end if
    allocate(bytes(max(1,nb)),vectors(max(1,nv)),result_bytes(max(1,bc)),result_vector(max(1,vc)),stat=ios)
    if(ios/=0)then
      call proto_error(s,'P002: cannot allocate typed foreign work buffers');return
    end if
    do i=0,n-1
      a=args(i)
      if(kinds(i)==2)then
        bytes(starts(i)+1:starts(i)+lengths(i))=s%text(s%nodes(a)%start:s%nodes(a)%start+lengths(i)-1)
      else if(kinds(i)==3)then
        do j=0,lengths(i)-1
          child=s%edges(s%nodes(a)%start+j)
          vectors(starts(i)+j+1)=s%nodes(child)%number
        end do
      end if
    end do
    call uf_host_apply_typed(s%nodes(ref)%start,kinds,n,numbers,starts,lengths,bytes,nb,vectors,nv, &
      result_kind,number_result,result_bytes,bc,outb,result_vector,vc,outv,status,message)
    if(status/=0)then
      call proto_error(s,'P012: '//trim(message));return
    end if
    if(outb<0.or.outb>bc.or.outv<0.or.outv>vc)then
      call proto_error(s,'P012: typed adapter returned invalid result length');return
    end if
    select case(result_kind)
    case(1)
      if(.not.finite_number(number_result))then
        call proto_error(s,'P012: typed result is not finite');return
      end if
      id=new_number(s,number_result)
    case(2)
      id=new_bytes(s,result_bytes(:outb))
    case(3)
      do i=1,outv
        if(.not.finite_number(result_vector(i)))then
          call proto_error(s,'P012: typed vector result contains a non-finite number');return
        end if
      end do
      id=new_node(s,pn_array)
      if(s%error%failed)return
      start=s%edge_count;s%nodes(id)%start=start;s%nodes(id)%length=outv
      do i=1,outv
        child=new_number(s,result_vector(i))
        if(s%error%failed)return
        s%edges(start+i-1)=child
      end do
      s%edge_count=start+outv
    case default
      call proto_error(s,'P012: unsupported typed result signature');return
    end select
    call proto_push(s,id)
  end subroutine
