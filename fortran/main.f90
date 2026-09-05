! The host entry point is Fortran. Rust is linked as a library, not a driver.
program urotif_main
  use, intrinsic :: iso_fortran_env, only: error_unit
  use urotif_parser
  use urotif_vm
  use urotif_bridge
  use urotif_prototype
  use urotif_links
  use urotif_foundation_bridge
  use urotif_assembler
  implicit none
  type(runtime_limits) :: budget
  integer :: emit_flags
  logical :: custom_limits,stream
  type(program_ir) :: p
  type(diagnostic) :: d
  type(prototype_state) :: proto
  type(foundation_program) :: linked_program
  character(4096) :: command, path, output, arg
  integer :: argc, i, status, steps, fuel
  real(rk) :: fuel_real
  logical :: ok, core, repairs, foundation, optimize
  argc = command_argument_count()
  if (argc == 0) then
    call usage()
    stop
  end if
  call get_arg(1, command)
  if (command == '--help' .or. command == '-h') then
    call usage()
    stop
  end if
  if (command == '--version') then
    print '(a)', 'Urotif 0.4.0 | Fortran main + linked Rust chain | Foundation IR2'
    stop
  end if
  select case (trim(command))
  case ('run', 'probe', 'check', 'ir', 'wasm', 'wat', 'links', 'c', 'rust', 'fortran', 'assemble', 'recover')
  case default
    call cli_error('unknown command: '//trim(command))
  end select
  path=''
  if(command/='links')then
    if (argc < 2) call cli_error('expected a source file')
    call get_arg(2, path)
  end if
  emit_flags=0
  custom_limits=.false.;stream=.false.
  output = ''
  fuel = default_fuel
  core = .false.
  repairs = .false.
  foundation = .false.
  optimize = .true.
  i = 3
  if(command=='links')i=2
  do while (i <= argc)
    call get_arg(i, arg)
    select case (trim(arg))
    case ('--stream')
      stream=.true.
    case ('--limit')
      i=i+1
      if(i>argc)call cli_error('--limit requires NAME=INTEGER')
      call get_arg(i,arg)
      call set_limit(budget,trim(arg),d)
      call check_error()
      custom_limits=.true.
    case ('--embed-source')
      emit_flags=ior(emit_flags,1)
    case ('--f95')
      emit_flags=ior(emit_flags,2)
    case ('--no-opt')
      optimize=.false.
    case ('--extern-v2')
      i=i+1
      if(i>argc)call cli_error('--extern-v2 requires MODULE.SYMBOL/TYPES->TYPE')
      call get_arg(i,arg)
      call load_link(trim(arg),d,.true.,.true.)
      call check_error()
    case ('--extern')
      i=i+1
      if(i>argc)call cli_error('--extern requires MODULE.SYMBOL/ARITY')
      call get_arg(i,arg)
      call load_link(trim(arg),d,.true.)
      call check_error()
    case ('--foundation')
      foundation = .true.
    case ('--link')
      i = i + 1
      if(i>argc)call cli_error('--link requires a trusted native plugin path')
      call get_arg(i,arg)
      call load_link(trim(arg),d)
      call check_error()
    case ('--core')
      core = .true.
    case ('--repair')
      repairs = .true.
    case ('-o')
      i = i + 1
      if (i > argc) call cli_error('-o requires an output path')
      call get_arg(i, output)
    case ('--fuel')
      i = i + 1
      if (i > argc) call cli_error('--fuel requires a positive integer')
      call get_arg(i, arg)
      call parse_decimal(trim(arg), fuel_real, ok)
      if (.not. ok) call cli_error('invalid fuel value')
      if (fuel_real <= 0 .or. fuel_real > 2147483647.0_rk) call cli_error('fuel must be 1..2147483647')
      if (fuel_real /= aint(fuel_real)) call cli_error('fuel must be an integer')
      fuel = int(fuel_real)
    case default
      call cli_error('unknown option: '//trim(arg))
    end select
    i = i + 1
  end do
  if (command == 'wasm' .or. command == 'wat' .or. command == 'c' .or. command == 'rust' .or. command == 'fortran' .or. &
      command == 'assemble' .or. command == 'recover') then
    if (len_trim(output) == 0) call cli_error('emission requires -o OUTPUT; source files are not overwritten by default')
    if (trim(output) == trim(path)) call cli_error('output must differ from the source path')
  else
    if (len_trim(output) /= 0) call cli_error('-o is only valid for emission/assembly')
  end if
  if(stream.and.(command/='run'.or.core))call cli_error('--stream is for native character/Foundation run')
  if(iand(emit_flags,2)/=0.and.command/='fortran')call cli_error('--f95 is only for Fortran emission')
  if(custom_limits.and..not.foundation.and.command/='assemble')call cli_error('--limit requires --foundation')
  if(iand(emit_flags,1)/=0)then
    if(command/='c'.and.command/='rust'.and.command/='fortran'.and.command/='wasm') &
      call cli_error('--embed-source is only for emitted artifacts')
  end if
  if(command=='recover')then
    call foundation_recover(trim(path),trim(output),d)
    call check_error()
    stop
  end if
  if(command=='assemble')then
    if(core)call cli_error('assemble is the Foundation symbolic frontend')
    call assemble_foundation(trim(path),trim(output),d,budget)
    call check_error()
    stop
  end if
  if(command=='links')then
    call list_links()
    stop
  end if
  if(foundation)then
    if(radix(0.0_rk)/=2.or.digits(0.0_rk)/=53)call cli_error('Foundation requires IEEE binary64 numerics')
  end if
  if(core.and.foundation)call cli_error('--core and --foundation are distinct profiles')
  if (core .and. repairs) call cli_error('--repair is only for the reference interpreter')
  if (core .and. command == 'probe') call cli_error('probe is only for the reference interpreter')
  if(foundation.and.command/='run'.and.command/='probe')then
    if(command=='wat')call cli_error('Foundation emits C, Rust, or WASM; WAT remains an experimental --core target')
    call foundation_compile(trim(path),optimize,linked_program,d,budget)
    call check_error()
    select case(trim(command))
    case('check')
      print '(a,i0,a,i0)','OK: ',linked_program%count,' byte entries; fast paths ',linked_program%fused
    case('ir')
      call foundation_dump(linked_program)
    case('c');call foundation_emit(linked_program,trim(output),0,d,emit_flags)
    case('rust');call foundation_emit(linked_program,trim(output),1,d,emit_flags)
    case('fortran');call foundation_emit(linked_program,trim(output),3,d,emit_flags)
    case('wasm');call foundation_emit(linked_program,trim(output),2,d,emit_flags)
    end select
    call check_error()
    stop
  end if
  if(core.and.(command=='c'.or.command=='rust'.or.command=='fortran'))call cli_error('C/Rust emission uses --foundation')
  if (.not. core) then
    if (command /= 'run' .and. command /= 'probe') then
      call cli_error('reference-profile emission is not yet ported; '// &
        'select --foundation for the new profile or --core for the experiment')
    end if
    call run_prototype_file(trim(path), fuel, repairs, proto, d, foundation,budget,stream)
    if (command == 'probe') then
      call write_prototype_json(proto)
      if (d%failed) stop 1
    else
      if (proto%output_length > 0.and..not.stream) call write_bytes(proto%output(:proto%output_length))
      call check_error()
    end if
    stop
  end if
  call compile_file(trim(path), p, d)
  call check_error()
  select case (trim(command))
  case ('check')
    print '(a,i0,a,i0)', 'OK: ', p%count, ' instructions; entry PC ', p%entry
  case ('ir')
    call dump_ir(p)
  case ('run')
    call run_program(p, fuel, status, d, steps)
  case ('wasm', 'wat')
    call emit_webassembly(p, trim(output), command == 'wat', d)
    if (.not. d%failed) print '(a)', 'Wrote '//trim(output)
  end select
  call check_error()
contains
  subroutine usage()
    print '(a)', 'Urotif 0.4 -- Fortran main; reference + foundation profiles'
    print '(a)', '  --foundation selects imports, external references, checked application, and calls'
    print '(a)', '  --link PATH grants a TRUSTED native plugin before linking/execution'
    print '(a)', '  --extern-v2 MODULE.SYMBOL/TYPES->TYPE declares number/bytes/vector typed imports'
    print '(a)', '  --extern MODULE.SYMBOL/ARITY declares a host import without loading native code'
    print '(a)', '  urotif c|rust|fortran|wasm FILE --foundation -o OUTPUT [--no-opt]'
    print '(a)', '    [--limit stack=8192] [--embed-source] [--f95 (Fortran only)]'
    print '(a)', '  urotif check|ir FILE --foundation'
    print '(a)', '  urotif recover ARTIFACT -o FILE.utf  Recover optional source capsule (not decompile)'
    print '(a)', '  urotif assemble FILE.ufm -o FILE.utf  Resolve .label/.goto/.eq/.call/.return/.halt'
    print '(a)', '  urotif links [--link PATH]         Inspect the sealed symbol catalog'
    print '(a)', '  --stream flushes output as it is produced; input is read on demand'
    print '(a)', '  urotif run   FILE [--repair] [--fuel N]  Run the reference character language'
    print '(a)', '  urotif probe FILE [--repair] [--fuel N]  JSON output, final stack, and diagnostic'
    print '(a)', 'Experimental named/numeric-text compiler (not prototype-equivalent):'
    print '(a)', '  urotif run   FILE --core               Run the experimental Fortran VM'
    print '(a)', '  urotif check FILE --core         Lex, parse, and resolve names'
    print '(a)', '  urotif ir    FILE --core         Inspect resolved instruction IR'
    print '(a)', '  urotif wasm  FILE --core -o FILE.wasm Emit browser/Node WebAssembly'
    print '(a)', '  urotif wat   FILE --core -o FILE.wat Inspect the WASM text lowering'
    print '(a)', '  urotif --version'
  end subroutine usage
  subroutine get_arg(index, text)
    integer, intent(in) :: index
    character(*), intent(out) :: text
    integer :: ios
    call get_command_argument(index, text, status=ios)
    if (ios /= 0) call cli_error('missing or overlong command-line argument')
  end subroutine get_arg
  subroutine cli_error(message)
    character(*), intent(in) :: message
    write(error_unit, '(a)') 'urotif: '//message
    stop 1
  end subroutine cli_error
  subroutine check_error()
    if (.not. d%failed) return
    write(error_unit, '(a)') trim(path)//':'//trim(int_text(d%line))//':'// &
      trim(int_text(d%column))//': '//trim(d%message)
    stop 1
  end subroutine check_error
end program urotif_main
