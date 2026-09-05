! Strict F95-only entry point: standard input supplies the command and path.
! printf 'run\nexamples/hello.utf\n' | bin/urotif95
program urotif95_main
  use urotif_parser
  use urotif_vm
  use urotif_prototype
  implicit none
  type(program_ir) :: p
  type(diagnostic) :: d
  type(prototype_state) :: proto
  character(4096) :: command, path
  integer :: ios, status, steps
  read(*, '(a)', iostat=ios) command
  if (ios /= 0) stop 1
  read(*, '(a)', iostat=ios) path
  if (ios /= 0) stop 1
  if (command /= 'run' .and. command /= 'check' .and. command /= 'ir' .and. command /= 'probe' .and. command /= 'core-run') then
    print '(a)', 'F95 driver accepts run, check, or ir, then a path on the next line.'
    stop 1
  end if
  if (command == 'run' .or. command == 'probe') then
    call run_prototype_file(trim(path), default_fuel, .false., proto, d)
    if (command == 'probe') then
      call write_prototype_json(proto)
    else
      if (proto%output_length > 0) call write_bytes(proto%output(:proto%output_length))
    end if
    if (d%failed) stop 1
    stop
  end if
  call compile_file(trim(path), p, d)
  if (.not. d%failed) then
    select case (trim(command))
    case ('core-run'); call run_program(p, default_fuel, status, d, steps)
    case ('ir'); call dump_ir(p)
    case ('check'); print '(a)', 'OK'
    end select
  end if
  if (d%failed) then
    print '(a)', trim(path)//':'//trim(int_text(d%line))//':'//trim(int_text(d%column))//': '//trim(d%message)
    stop 1
  end if
end program urotif95_main
