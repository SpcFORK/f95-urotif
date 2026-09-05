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
