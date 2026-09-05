! F95 signature catalog for the generated program; no foreign pointers here.
subroutine uf_host_signature(id,kinds,result_kind,status,message)
  use urotif_tables
  implicit none
  integer,intent(in)::id
  integer,intent(out)::kinds(0:7),result_kind,status
  character(*),intent(out)::message
  integer::i
  kinds=0;result_kind=0;status=1;message='not a typed reference'
  if(id<0.or.id>=symbol_count)return
  if(symbol_kind(id)/=7)return
  do i=0,7
    kinds(i)=symbol_parameters(8*id+i)
  end do
  result_kind=symbol_result(id);status=0;message=''
end subroutine
