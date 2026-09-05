! F2003 command-line adapter only. The preceding value/IR core is F95.
program urotif_transpiled
  use, intrinsic::iso_fortran_env, only:error_unit
  use urotif_target
  implicit none
  type(prototype_state)::s
  character(128)::arg
  integer::i,j,ios,fuel,repeat,pc,n
  real(rk)::value
  logical::json,ok,failed,stream
  character,pointer::input(:)=>null()
  fuel=1000000;repeat=1;json=.false.;stream=.false.;i=1;n=0
  do while(i<=command_argument_count())
    call get_command_argument(i,arg,status=ios)
    if(ios/=0)stop 2
    select case(trim(arg))
    case('--json');json=.true.
    case('--stream');stream=.true.
    case('--fuel','--repeat')
      j=0
      if(arg=='--repeat')j=1
      i=i+1
      call get_command_argument(i,arg,status=ios)
      if(ios/=0)stop 2
      call parse_decimal(trim(arg),value,ok)
      if(.not.ok)stop 2
      if(value<1.or.value>2147483647.0_rk.or.value/=aint(value))stop 2
      if(j==1)then
        if(value>10000)stop 2
        repeat=int(value)
      else
        fuel=int(value)
      end if
    case default
      write(error_unit,'(a)')'unknown option: '//trim(arg)
      stop 2
    end select
    i=i+1
  end do
  if(stream.and.(json.or.repeat>1))stop 2
  if(repeat>1.and.uses_input)then
    call read_replay_input(input,n,program_limits%input,failed)
    if(failed)then
      write(error_unit,'(a)')'cannot buffer input within configured budget';stop 2
    end if
  end if
  do i=1,repeat
    if(associated(input))then
      call target_run(s,fuel,pc,input(:n),stream)
    else
      call target_run(s,fuel,pc,stream=stream)
    end if
  end do
  if(json)then
    call target_report(s,pc)
  else
    if(s%output_length>0.and..not.stream)call write_bytes(s%output(:s%output_length))
    if(s%error%failed)write(error_unit,'(a)')trim(s%error%message)//' at '// &
      trim(int_text(s%error%line))//':'//trim(int_text(s%error%column))
  end if
  failed=s%error%failed
  call proto_release(s)
  if(associated(input))deallocate(input)
  if(failed)stop 1
end program urotif_transpiled
