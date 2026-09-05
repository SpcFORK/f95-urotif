module urotif_parser
  use urotif_lexer
  implicit none
contains
  subroutine compile_file(path, p, d)
    character(*), intent(in) :: path
    type(program_ir), intent(out) :: p
    type(diagnostic), intent(inout) :: d
    character(max_source) :: source
    integer :: n
    call read_source(path, source, n, d)
    if (.not. d%failed) call compile_source(source, n, p, d)
  end subroutine compile_file

  subroutine compile_source(source, n, p, d)
    character(*), intent(in) :: source
    integer, intent(in) :: n
    type(program_ir), intent(out) :: p
    type(diagnostic), intent(inout) :: d
    type(lexer_state) :: ls
    type(token) :: t, saved
    character(max_name) :: routine_names(0:max_routines-1), label_names(0:max_labels-1)
    character(max_name) :: references(0:max_code-1), name
    integer :: routine_pc(0:max_routines-1), label_pc(0:max_labels-1), label_scope(0:max_labels-1)
    integer :: reference_scope(0:max_code-1), nr, nl, scope, i, j, found
    logical :: explicit_routines
    p%count = 0
    p%entry = 0
    p%string_count = 0
    p%variable_count = 0
    ls%pos = 1
    ls%line = 1
    ls%column = 1
    references = ''
    reference_scope = -1
    nr = 0
    nl = 0
    scope = 0
    call next()
    if (t%kind /= tk_mark) then
      call fail(d, 'program must begin with =) urotif', t%line, t%column)
      return
    end if
    call next()
    if (t%kind /= tk_word .or. t%text /= 'urotif') then
      call fail(d, 'expected urotif after the header marker', t%line, t%column)
      return
    end if
    call next()
    explicit_routines = t%kind == tk_mark
    if (t%kind == tk_word) explicit_routines = t%text == 'sub' .or. t%text == 'subroutine'
    if (explicit_routines) then
      do while (t%kind /= tk_eof .and. .not. d%failed)
        if (t%kind /= tk_mark) then
          if (t%kind /= tk_word .or. (t%text /= 'sub' .and. t%text /= 'subroutine')) then
            call fail(d, 'expected a subroutine declaration; top-level code cannot be mixed with routines', t%line, t%column)
            exit
          end if
        end if
        call next()
        if (t%kind /= tk_word) then
          call fail(d, 'expected a subroutine name', t%line, t%column)
          exit
        end if
        if (nr == max_routines) then
          call fail(d, 'too many subroutines (limit 128)', t%line, t%column)
          exit
        end if
        name = t%text(1:max_name)
        do i = 0, nr-1
          if (routine_names(i) == name) call fail(d, 'duplicate subroutine: '//trim(name), t%line, t%column)
        end do
        if (d%failed) exit
        scope = nr
        routine_names(nr) = name
        routine_pc(nr) = p%count
        nr = nr + 1
        call next()
        do while (.not. d%failed)
          if (t%kind == tk_eof) then
            call fail(d, 'missing end for subroutine '//trim(name), t%line, t%column)
            exit
          end if
          if (t%kind == tk_word .and. t%text == 'end') exit
          call statement()
        end do
        if (d%failed) exit
        call emit(op_ret, 0, 0.0_rk, t%line, t%column)
        call next()
      end do
      found = -1
      do i = 0, nr-1
        if (routine_names(i) == 'main') found = routine_pc(i)
      end do
      if (found < 0) call fail(d, 'explicit-routine programs need a subroutine named main', 1, 1)
      p%entry = max(0, found)
    else
      nr = 1
      routine_names(0) = 'main'
      routine_pc(0) = 0
      do while (t%kind /= tk_eof .and. .not. d%failed)
        call statement()
      end do
      call emit(op_halt, 0, 0.0_rk, t%line, t%column)
    end if
    if (d%failed) return
    ! Second pass: resolve forward calls globally and labels within a routine.
    do i = 0, p%count-1
      if (len_trim(references(i)) == 0) cycle
      found = -1
      if (p%code(i)%op == op_call) then
        do j = 0, nr-1
          if (routine_names(j) == references(i)) found = routine_pc(j)
        end do
        if (found < 0) call fail(d, 'unknown subroutine: '//trim(references(i)), p%code(i)%line, p%code(i)%column)
      else
        do j = 0, nl-1
          if (label_scope(j) == reference_scope(i) .and. label_names(j) == references(i)) found = label_pc(j)
        end do
        if (found < 0) call fail(d, 'unknown local label: '//trim(references(i)), p%code(i)%line, p%code(i)%column)
      end if
      p%code(i)%arg = found
    end do
  contains
    subroutine next()
      call lex_next(source, n, ls, t, d)
    end subroutine next

    subroutine emit(op, arg, number, line, column)
      integer, intent(in) :: op, arg, line, column
      real(rk), intent(in) :: number
      if (d%failed) return
      if (p%count == max_code) then
        call fail(d, 'too many instructions (limit 8192)', line, column)
        return
      end if
      p%code(p%count)%op = op
      p%code(p%count)%arg = arg
      p%code(p%count)%number = number
      p%code(p%count)%line = line
      p%code(p%count)%column = column
      p%count = p%count + 1
    end subroutine emit

    subroutine literal(tok)
      type(token), intent(in) :: tok
      integer :: k, id
      if (tok%kind == tk_number) then
        call emit(op_num, 0, tok%number, tok%line, tok%column)
      else if (tok%kind == tk_text) then
        id = -1
        do k = 0, p%string_count-1
          if (p%string_lengths(k) /= tok%length) cycle
          if (p%strings(k) == tok%text) then
            id = k
            exit
          end if
        end do
        if (id < 0) then
          if (p%string_count == max_strings) then
            call fail(d, 'too many text constants (limit 1024)', tok%line, tok%column)
            return
          end if
          id = p%string_count
          p%strings(id) = tok%text
          p%string_lengths(id) = tok%length
          p%string_count = id + 1
        end if
        call emit(op_text, id, 0.0_rk, tok%line, tok%column)
      else
        call fail(d, 'push expects {number} or a text literal', tok%line, tok%column)
      end if
    end subroutine literal

    subroutine define_label(tok)
      type(token), intent(in) :: tok
      integer :: k
      if (tok%kind /= tk_word) then
        call fail(d, 'expected a label name', tok%line, tok%column)
        return
      end if
      do k = 0, nl-1
        if (label_scope(k) == scope .and. label_names(k) == tok%text) then
          call fail(d, 'duplicate local label: '//trim(tok%text), tok%line, tok%column)
          return
        end if
      end do
      if (nl == max_labels) then
        call fail(d, 'too many labels (limit 1024)', tok%line, tok%column)
        return
      end if
      label_names(nl) = tok%text(1:max_name)
      label_pc(nl) = p%count
      label_scope(nl) = scope
      nl = nl + 1
    end subroutine define_label

    subroutine target_instruction(op, origin)
      integer, intent(in) :: op
      type(token), intent(in) :: origin
      integer :: at
      if (t%kind /= tk_word) then
        call fail(d, 'expected a named target (coordinate jumps are not part of core 0.1)', t%line, t%column)
        return
      end if
      at = p%count
      call emit(op, 0, 0.0_rk, origin%line, origin%column)
      if (d%failed) return
      references(at) = t%text(1:max_name)
      reference_scope(at) = scope
      call next()
    end subroutine target_instruction

    subroutine variable_instruction(op, origin)
      integer, intent(in) :: op
      type(token), intent(in) :: origin
      integer :: k, id
      if (t%kind /= tk_word) then
        call fail(d, 'expected a register name', t%line, t%column)
        return
      end if
      id = -1
      do k = 0, p%variable_count-1
        if (p%variable_names(k) == t%text) id = k
      end do
      if (id < 0) then
        if (p%variable_count == max_vars) then
          call fail(d, 'too many global registers (limit 256)', t%line, t%column)
          return
        end if
        id = p%variable_count
        p%variable_names(id) = t%text(1:max_name)
        p%variable_count = id + 1
      end if
      call emit(op, id, 0.0_rk, origin%line, origin%column)
      call next()
    end subroutine variable_instruction

    subroutine statement()
      integer :: op
      ! saved is shared only within this nonrecursive parser; the parsed
      ! language's recursion is represented by op_call, not parser recursion.
      saved = t
      call next()
      if (d%failed) return
      if (saved%kind == tk_number .or. saved%kind == tk_text) then
        if (saved%kind == tk_text .and. saved%length == 1 .and. t%text == '@' .and. t%kind == tk_symbol) then
          if (saved%text == 'p' .or. saved%text == 'P') then
            op = op_print
            if (saved%text == 'P') op = op_println
            call emit(op, 0, 0.0_rk, saved%line, saved%column)
            call next()
            return
          end if
        end if
        call literal(saved)
        return
      end if
      if (saved%kind == tk_word .and. t%kind == tk_symbol .and. t%text == ':' .and. &
          saved%line == t%line .and. t%column == saved%column+saved%length) then
        call define_label(saved)
        call next()
        return
      end if
      if (saved%kind == tk_mark) then
        call fail(d, 'nested subroutines or missing end are not allowed', saved%line, saved%column)
        return
      end if
      op = -1
      select case (trim(saved%text))
      case ('push')
        call literal(t)
        call next()
        return
      case (':', 'label')
        call define_label(t)
        call next()
        return
      case ('goto', '^')
        call target_instruction(op_jump, saved)
        return
      case ('ifz')
        call target_instruction(op_jz, saved)
        return
      case ('ifnz')
        call target_instruction(op_jnz, saved)
        return
      case ('call')
        call target_instruction(op_call, saved)
        return
      case ('store')
        call variable_instruction(op_store, saved)
        return
      case ('load')
        call variable_instruction(op_load, saved)
        return
      case ('p', 'P')
        if (t%kind /= tk_symbol .or. t%text /= '@') then
          call fail(d, 'p and P must be followed by @; otherwise use print or println', saved%line, saved%column)
          return
        end if
        op = op_print
        if (saved%text == 'P') op = op_println
        call next()
      case ('halt'); op = op_halt
      case ('return', 'ret'); op = op_ret
      case ('dup', '%'); op = op_dup
      case ('drop', '_'); op = op_drop
      case ('swap'); op = op_swap
      case ('over'); op = op_over
      case ('rot'); op = op_rot
      case ('add', '+'); op = op_add
      case ('sub', '-'); op = op_sub
      case ('mul', '*'); op = op_mul
      case ('div', '|'); op = op_div
      case ('mod'); op = op_mod
      case ('neg', '~'); op = op_neg
      case ('print', '$'); op = op_print
      case ('println'); op = op_println
      case ('eq'); op = op_eq
      case ('ne'); op = op_ne
      case ('lt'); op = op_lt
      case ('le'); op = op_le
      case ('gt'); op = op_gt
      case ('ge'); op = op_ge
      case ('read', '`'); op = op_read
      case default
        call fail(d, 'unknown instruction: '//trim(saved%text), saved%line, saved%column)
        return
      end select
      call emit(op, 0, 0.0_rk, saved%line, saved%column)
    end subroutine statement
  end subroutine compile_source

  subroutine dump_ir(p)
    type(program_ir), intent(in) :: p
    integer :: i
    print '(a,i0)', 'entry = ', p%entry
    do i = 0, p%count-1
      write(*, '(i5,2x,a12,2x,i6,2x,a,2x,a,i0,a,i0)') i, opcode_name(p%code(i)%op), &
        p%code(i)%arg, trim(number_text(p%code(i)%number)), '@', p%code(i)%line, ':', p%code(i)%column
    end do
  end subroutine dump_ir
end module urotif_parser
