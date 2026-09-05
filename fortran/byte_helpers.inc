  ! No giant automatic CHARACTER result is needed for these bulk operations.
  subroutine string_from_bytes(text,bytes)
    character(*),intent(out)::text
    character,intent(in)::bytes(:)
    integer::i
    do i=1,min(len(text),size(bytes))
      text(i:i)=bytes(i)
    end do
  end subroutine

  subroutine write_bytes(bytes)
    character,intent(in)::bytes(:)
    character(4096)::chunk
    integer::a,n
    do a=1,size(bytes),len(chunk)
      n=min(len(chunk),size(bytes)-a+1)
      call string_from_bytes(chunk(:n),bytes(a:a+n-1))
      write(*,'(a)',advance='no')chunk(:n)
    end do
  end subroutine

  subroutine output_append_bytes(s,bytes)
    type(prototype_state),intent(inout)::s
    character,intent(in)::bytes(:)
    integer::n
    if(s%error%failed)return
    n=size(bytes)
    if(n>s%budget%output-s%output_length)then
      call proto_error(s,'P002: output budget exhausted');return
    end if
    s%output(s%output_length+1:s%output_length+n)=bytes
    s%output_length=s%output_length+n
    if(s%live_output)then
      call write_bytes(bytes);call uf_flush_output()
    end if
  end subroutine

  integer function new_bytes(s,bytes) result(id)
    type(prototype_state),intent(inout)::s
    character,intent(in)::bytes(:)
    integer::n
    id=0;n=size(bytes)
    if(n>s%budget%text-s%text_length)then
      call proto_error(s,'P002: text arena budget exhausted');return
    end if
    id=new_node(s,pn_text)
    if(s%error%failed)return
    s%nodes(id)%start=s%text_length+1;s%nodes(id)%length=n
    s%text(s%text_length+1:s%text_length+n)=bytes
    s%text_length=s%text_length+n
  end function

  subroutine repr_put_bytes(out,n,bytes)
    character(*),intent(inout)::out
    integer,intent(inout)::n
    character,intent(in)::bytes(:)
    integer::k
    k=size(bytes)
    if(k>len(out)-n)then
      n=len(out)+1;return
    end if
    call string_from_bytes(out(n+1:n+k),bytes);n=n+k
  end subroutine

  subroutine decimal_bytes(bytes,x,ok)
    character,intent(in)::bytes(:)
    real(rk),intent(out)::x
    logical,intent(out)::ok
    character(size(bytes)),allocatable::text(:)
    integer::ios
    x=0.0_rk;ok=.false.
    allocate(text(1),stat=ios)
    if(ios/=0)return
    call string_from_bytes(text(1),bytes)
    call parse_decimal(text(1),x,ok)
  end subroutine

  ! Positive width: valid UTF-8. Negative width: one invalid maximal subpart.
  ! This matches Rust from_utf8_lossy / JavaScript's UTF-8 replacement decoder.
  integer function utf8_width(bytes,at,n) result(width)
    character,intent(in)::bytes(:)
    integer,intent(in)::at,n
    integer::c,d,k,need,lo,hi
    c=iachar(bytes(at));width=1
    if(c<128)return
    need=0;lo=128;hi=191
    if(c>=194.and.c<=223)need=2
    if(c>=224.and.c<=239)need=3
    if(c>=240.and.c<=244)need=4
    if(c==224)lo=160
    if(c==237)hi=159
    if(c==240)lo=144
    if(c==244)hi=143
    width=-1
    if(need==0)return
    do k=1,need-1
      if(at+k>n)then
        width=-k;return
      end if
      d=iachar(bytes(at+k))
      if(d<lo.or.d>hi)then
        width=-k;return
      end if
      lo=128;hi=191
    end do
    width=need
  end function

  subroutine write_json_bytes(bytes,n)
    character,intent(in)::bytes(:)
    integer,intent(in)::n
    integer::i,c,w
    character(4)::hex
    write(*,'(a)',advance='no')'"'
    i=1
    do while(i<=n)
      c=iachar(bytes(i))
      if(c==34.or.c==92)then
        write(*,'(a)',advance='no')achar(92)//bytes(i)
        i=i+1
      else if(c<32)then
        write(hex,'(z4.4)')c
        write(*,'(a)',advance='no')achar(92)//'u'//hex
        i=i+1
      else if(c<128)then
        write(*,'(a)',advance='no')bytes(i)
        i=i+1
      else
        w=utf8_width(bytes,i,n)
        if(w>0)then
          call write_bytes(bytes(i:i+w-1));i=i+w
        else
          write(*,'(a)',advance='no')achar(92)//'ufffd';i=i-w
        end if
      end if
    end do
    write(*,'(a)',advance='no')'"'
  end subroutine

  subroutine write_hex_bytes(bytes)
    character,intent(in)::bytes(:)
    character(*),parameter::digits='0123456789abcdef'
    character(4096)::chunk
    integer::a,n,i,v
    write(*,'(a)',advance='no')'"'
    do a=1,size(bytes),len(chunk)/2
      n=min(len(chunk)/2,size(bytes)-a+1)
      do i=1,n
        v=iachar(bytes(a+i-1))
        chunk(2*i-1:2*i)=digits(v/16+1:v/16+1)//digits(mod(v,16)+1:mod(v,16)+1)
      end do
      write(*,'(a)',advance='no')chunk(:2*n)
    end do
    write(*,'(a)',advance='no')'"'
  end subroutine
