! Satisfy the F95-only executable without linking any Rust/C services.
subroutine uf_host_lookup(mode,module_id,name,id,arity,kind,status,message)
  implicit none
  integer,intent(in)::mode,module_id
  character(*),intent(in)::name
  integer,intent(out)::id,arity,kind,status
  character(*),intent(out)::message
  id=-1;arity=0;kind=0;status=1
  message='Foundation links require the mixed-language executable'
end subroutine uf_host_lookup
subroutine uf_host_apply(id,args,n,result,status,message)
  use urotif_types, only: rk
  implicit none
  integer,intent(in)::id,n
  real(rk),intent(in)::args(*)
  real(rk),intent(out)::result
  integer,intent(out)::status
  character(*),intent(out)::message
  result=0.0_rk;status=1
  message='Foundation links require the mixed-language executable'
end subroutine uf_host_apply

! Strict F95 has no standardized FLUSH statement; its CLI has no --stream.
subroutine uf_flush_output()
end subroutine

subroutine uf_host_signature(id,kinds,result_kind,status,message)
  implicit none
  integer,intent(in)::id
  integer,intent(out)::kinds(0:7),result_kind,status
  character(*),intent(out)::message
  kinds=0;result_kind=0;status=1;message='typed links unavailable in this F95 host'
end subroutine
subroutine uf_host_apply_typed(id,kinds,n,numbers,starts,lengths,bytes,nb,vectors,nv, &
    result_kind,number_result,result_bytes,bc,outb,result_vector,vc,outv,status,message)
  use urotif_types,only:rk
  implicit none
  integer,intent(in)::id,kinds(0:7),n,starts(0:7),lengths(0:7),nb,nv,result_kind,bc,vc
  real(rk),intent(in)::numbers(0:7),vectors(*)
  character,intent(in)::bytes(*)
  real(rk),intent(out)::number_result,result_vector(*)
  character,intent(out)::result_bytes(*)
  integer,intent(out)::outb,outv,status
  character(*),intent(out)::message
  number_result=0.0_rk;outb=0;outv=0;status=1;message='typed links unavailable in this F95 host'
end subroutine
