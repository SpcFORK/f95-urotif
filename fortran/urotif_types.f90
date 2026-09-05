! Urotif 0.1 core -- compiled with -std=f95 -pedantic-errors.
module urotif_types
  implicit none
  integer, parameter :: rk = selected_real_kind(15, 307)
  integer, parameter :: max_source = 262144, max_code = 8192
  integer, parameter :: max_text = 2048, max_strings = 1024, max_name = 63
  integer, parameter :: max_routines = 128, max_labels = 1024, max_vars = 256
  integer, parameter :: stack_cap = 2048, call_cap = 1024
  integer, parameter :: default_fuel = 1000000

  ! Stable IR ABI 1. Keep include/urotif_backend.h and Rust in sync.
  integer, parameter :: op_halt=0, op_num=1, op_text=2, op_dup=3, op_drop=4
  integer, parameter :: op_swap=5, op_over=6, op_add=7, op_sub=8, op_mul=9
  integer, parameter :: op_div=10, op_neg=11, op_print=12, op_println=13
  integer, parameter :: op_jump=14, op_jz=15, op_jnz=16, op_call=17, op_ret=18
  integer, parameter :: op_eq=19, op_ne=20, op_lt=21, op_le=22, op_gt=23, op_ge=24
  integer, parameter :: op_store=25, op_load=26, op_read=27, op_mod=28, op_rot=29

  type diagnostic
    logical :: failed = .false.
    integer :: line = 1, column = 1
    character(256) :: message = ''
  end type diagnostic

  type instruction
    integer :: op = op_halt, arg = 0, line = 1, column = 1
    real(rk) :: number = 0.0_rk
  end type instruction

  type program_ir
    type(instruction) :: code(0:max_code-1)
    integer :: count = 0, entry = 0, string_count = 0, variable_count = 0
    character(max_text) :: strings(0:max_strings-1)
    integer :: string_lengths(0:max_strings-1)
    character(max_name) :: variable_names(0:max_vars-1)
  end type program_ir

  type value
    ! tag = -1: unset; 0: number; 1: interned immutable text.
    integer :: tag = -1, text_id = 0
    real(rk) :: number = 0.0_rk
  end type value

contains
  integer function hex_value(c) result(n)
    character,intent(in)::c
    integer::x
    x=iachar(c);n=-1
    if(x>=48.and.x<=57)n=x-48
    if(x>=65.and.x<=70)n=x-65+10
    if(x>=97.and.x<=102)n=x-97+10
  end function
  subroutine fail(d, message, line, column)
    type(diagnostic), intent(inout) :: d
    character(*), intent(in) :: message
    integer, intent(in) :: line, column
    if (d%failed) return
    d%failed = .true.
    d%line = line
    d%column = column
    d%message = message
  end subroutine fail

  function int_text(i) result(s)
    integer, intent(in) :: i
    character(32) :: s
    write(s, '(i12)') i
    s = adjustl(s)
  end function int_text

  logical function is_digit(c)
    character, intent(in) :: c
    is_digit = c >= '0' .and. c <= '9'
  end function is_digit

  logical function is_alpha(c)
    character, intent(in) :: c
    is_alpha = (c >= 'a' .and. c <= 'z') .or. (c >= 'A' .and. c <= 'Z')
  end function is_alpha

  logical function finite_number(x)
    real(rk), intent(in) :: x
    finite_number = abs(x) <= huge(x)
  end function finite_number

  ! Validate decimal syntax before list-directed conversion. In particular,
  ! commas, repeats, NaN, Inf, and list-directed trailing junk are not numbers.
  subroutine parse_decimal(raw, x, ok)
    character(*), intent(in) :: raw
    real(rk), intent(out) :: x
    logical, intent(out) :: ok
    character(len(raw)),allocatable::s(:)
    integer::s_allocation_status
    integer :: i, n, digits, ios
    allocate(s(1),stat=s_allocation_status)
    if(s_allocation_status/=0)then
      x=0.0_rk;ok=.false.;return
    end if
    s(1) = trim(adjustl(raw))
    n = len_trim(s(1))
    i = 1
    x = 0.0_rk
    ok = .false.
    if (n == 0) return
    if (s(1)(i:i) == '+' .or. s(1)(i:i) == '-') i = i + 1
    digits = 0
    do while (i <= n)
      if (.not. is_digit(s(1)(i:i))) exit
      digits = digits + 1
      i = i + 1
    end do
    if (i <= n) then
      if (s(1)(i:i) == '.') then
        i = i + 1
        do while (i <= n)
          if (.not. is_digit(s(1)(i:i))) exit
          digits = digits + 1
          i = i + 1
        end do
      end if
    end if
    if (digits == 0) return
    if (i <= n) then
      if (s(1)(i:i) == 'e' .or. s(1)(i:i) == 'E') then
        i = i + 1
        if (i <= n) then
          if (s(1)(i:i) == '+' .or. s(1)(i:i) == '-') i = i + 1
        end if
        digits = 0
        do while (i <= n)
          if (.not. is_digit(s(1)(i:i))) exit
          digits = digits + 1
          i = i + 1
        end do
        if (digits == 0) return
      end if
    end if
    if (i /= n+1) return
    read(s(1), *, iostat=ios) x
    if (ios /= 0) return
    ok = finite_number(x)
  end subroutine parse_decimal

  ! Number output contract shared by the JS host: small integral values use
  ! decimal integers; other values use ES with 15 fractional digits, E+ddd.
  function number_text(x) result(s)
    real(rk), intent(in) :: x
    character(64) :: s
    integer :: n
    if (x == 0.0_rk) then
      s = '0'
    else if (abs(x) < 1.0e15_rk .and. x == aint(x)) then
      write(s, '(f32.0)') x
      s = adjustl(s)
      n = len_trim(s)
      if (n > 0) then
        if (s(n:n) == '.') s(n:n) = ' '
      end if
    else
      write(s, '(es24.15e3)') x
      s = adjustl(s)
    end if
  end function number_text

  function opcode_name(op) result(s)
    integer, intent(in) :: op
    character(12) :: s
    character(12), parameter :: names(0:29) = (/ &
      'halt        ', 'number      ', 'text        ', 'dup         ', &
      'drop        ', 'swap        ', 'over        ', 'add         ', &
      'sub         ', 'mul         ', 'div         ', 'neg         ', &
      'print       ', 'println     ', 'goto        ', 'ifz         ', &
      'ifnz        ', 'call        ', 'return      ', 'eq          ', &
      'ne          ', 'lt          ', 'le          ', 'gt          ', &
      'ge          ', 'store       ', 'load        ', 'read        ', &
      'mod         ', 'rot         ' /)
    s = 'invalid'
    if (op >= 0 .and. op <= 29) s = names(op)
  end function opcode_name
end module urotif_types
