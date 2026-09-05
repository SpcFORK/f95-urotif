! Native reference execution is Fortran, not a call into a Rust interpreter.
module urotif_vm
  use urotif_types
  implicit none
contains
  function runtime_message(status) result(s)
    integer, intent(in) :: status
    character(96) :: s
    select case (status)
    case (0); s = 'success'
    case (1); s = 'data stack underflow'
    case (2); s = 'data stack overflow (2048 values)'
    case (3); s = 'numeric operand required'
    case (4); s = 'division by zero'
    case (5); s = 'return stack overflow (1024 calls)'
    case (6); s = 'read of an uninitialized global register'
    case (7); s = 'invalid instruction or program counter'
    case (8); s = 'instruction fuel exhausted'
    case (9); s = 'read requires one finite decimal number per input line'
    case (10); s = 'non-finite arithmetic result'
    case default; s = 'unknown runtime error'
    end select
  end function runtime_message

  subroutine read_number(x, ok)
    real(rk), intent(out) :: x
    logical, intent(out) :: ok
    character(max_text+1) :: raw
    integer :: got, ios
    got = 0
    ok = .false.
    x = 0.0_rk
    read(*, '(a)', advance='no', size=got, iostat=ios, eor=10, end=10, err=20) raw
    ! A complete buffer means the record is longer than the allowed limit.
    return
10  continue
    if (got <= max_text) call parse_decimal(raw(1:got), x, ok)
20  continue
  end subroutine read_number

  subroutine run_program(p, fuel, status, d, steps)
    type(program_ir), intent(in) :: p
    integer, intent(in) :: fuel
    integer, intent(out) :: status, steps
    type(diagnostic), intent(inout) :: d
    type(value) :: stack(0:stack_cap-1), vars(0:max_vars-1), a, b, c
    integer :: returns(0:call_cap-1), sp, rp, pc, next_pc, need, i
    real(rk) :: x, y, z, q
    logical :: same, ok
    type(instruction) :: ins
    sp = 0
    rp = 0
    pc = p%entry
    steps = 0
    status = 0
    vars%tag = -1
    ins%line = 1
    ins%column = 1
    do
      if (pc < 0 .or. pc >= p%count) then
        status = 7
        exit
      end if
      ins = p%code(pc)
      if (steps >= fuel) then
        status = 8
        exit
      end if
      steps = steps + 1
      next_pc = pc + 1
      need = 0
      select case (ins%op)
      case (op_dup, op_drop, op_neg, op_print, op_println, op_jz, op_jnz, op_store)
        need = 1
      case (op_swap, op_over, op_add, op_sub, op_mul, op_div, op_mod, op_eq, op_ne, op_lt, op_le, op_gt, op_ge)
        need = 2
      case (op_rot)
        need = 3
      end select
      if (sp < need) then
        status = 1
        exit
      end if
      select case (ins%op)
      case (op_num, op_text, op_dup, op_over, op_load, op_read)
        if (sp == stack_cap) then
          status = 2
          exit
        end if
      end select
      if (need >= 1) a = stack(sp-1)
      if (need >= 2) b = stack(sp-2)
      select case (ins%op)
      case (op_halt)
        exit
      case (op_num, op_text)
        a%tag = 0
        a%number = ins%number
        a%text_id = ins%arg
        if (ins%op == op_text) a%tag = 1
        stack(sp) = a
        sp = sp + 1
      case (op_dup)
        stack(sp) = a
        sp = sp + 1
      case (op_drop)
        sp = sp - 1
      case (op_swap)
        stack(sp-1) = b
        stack(sp-2) = a
      case (op_over)
        stack(sp) = b
        sp = sp + 1
      case (op_rot)
        c = stack(sp-3)
        stack(sp-3) = b
        stack(sp-2) = a
        stack(sp-1) = c
      case (op_add, op_sub, op_mul, op_div, op_mod, op_lt, op_le, op_gt, op_ge)
        if (a%tag /= 0 .or. b%tag /= 0) then
          status = 3
          exit
        end if
        x = b%number
        y = a%number
        if (ins%op == op_div .or. ins%op == op_mod) then
          if (y == 0.0_rk) then
            status = 4
            exit
          end if
        end if
        z = 0.0_rk
        select case (ins%op)
        case (op_add); z = x + y
        case (op_sub); z = x - y
        case (op_mul); z = x * y
        case (op_div); z = x / y
        case (op_mod)
          q = x / y
          if (.not. finite_number(q)) then
            status = 10
            exit
          end if
          z = x - aint(q) * y
        case (op_lt); if (x < y) z = 1.0_rk
        case (op_le); if (x <= y) z = 1.0_rk
        case (op_gt); if (x > y) z = 1.0_rk
        case (op_ge); if (x >= y) z = 1.0_rk
        end select
        if (.not. finite_number(z)) then
          status = 10
          exit
        end if
        b%number = z
        stack(sp-2) = b
        sp = sp - 1
      case (op_eq, op_ne)
        same = .false.
        if (a%tag == b%tag) then
          if (a%tag == 0) then
            same = a%number == b%number
          else
            same = a%text_id == b%text_id
          end if
        end if
        if (ins%op == op_ne) same = .not. same
        b%tag = 0
        b%number = 0.0_rk
        if (same) b%number = 1.0_rk
        stack(sp-2) = b
        sp = sp - 1
      case (op_neg)
        if (a%tag /= 0) then
          status = 3
          exit
        end if
        stack(sp-1)%number = -a%number
      case (op_print, op_println)
        sp = sp - 1
        if (a%tag == 0) then
          write(*, '(a)', advance='no') trim(number_text(a%number))
        else
          i = p%string_lengths(a%text_id)
          if (i > 0) write(*, '(a)', advance='no') p%strings(a%text_id)(1:i)
        end if
        if (ins%op == op_println) write(*, '(a)') ''
      case (op_jump)
        next_pc = ins%arg
      case (op_jz, op_jnz)
        if (a%tag /= 0) then
          status = 3
          exit
        end if
        sp = sp - 1
        if (ins%op == op_jz .and. a%number == 0.0_rk) next_pc = ins%arg
        if (ins%op == op_jnz .and. a%number /= 0.0_rk) next_pc = ins%arg
      case (op_call)
        if (rp == call_cap) then
          status = 5
          exit
        end if
        returns(rp) = pc + 1
        rp = rp + 1
        next_pc = ins%arg
      case (op_ret)
        if (rp == 0) exit
        rp = rp - 1
        next_pc = returns(rp)
      case (op_store)
        vars(ins%arg) = a
        sp = sp - 1
      case (op_load)
        if (vars(ins%arg)%tag == -1) then
          status = 6
          exit
        end if
        stack(sp) = vars(ins%arg)
        sp = sp + 1
      case (op_read)
        call read_number(x, ok)
        if (.not. ok) then
          status = 9
          exit
        end if
        a%tag = 0
        a%number = x
        stack(sp) = a
        sp = sp + 1
      case default
        status = 7
        exit
      end select
      pc = next_pc
    end do
    if (status /= 0) then
      call fail(d, 'runtime E'//trim(int_text(status))//': '//trim(runtime_message(status)), ins%line, ins%column)
    end if
  end subroutine run_program
end module urotif_vm
