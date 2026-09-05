module urotif_lexer
  use urotif_types
  implicit none
  integer, parameter :: tk_eof=0, tk_word=1, tk_number=2, tk_text=3, tk_mark=4, tk_symbol=5
  type token
    integer :: kind = tk_eof, length = 0, line = 1, column = 1
    character(max_text) :: text = ''
    real(rk) :: number = 0.0_rk
  end type token
  type lexer_state
    integer :: pos = 1, line = 1, column = 1
  end type lexer_state
contains
  ! Nonadvancing records preserve spaces, blank lines, and a final token with
  ! no newline. No deferred-length CHARACTER or F2008 NEWUNIT is required.
  subroutine read_source(path, source, n, d)
    character(*), intent(in) :: path
    character(*), intent(out) :: source
    integer, intent(out) :: n
    type(diagnostic), intent(inout) :: d
    character(1024) :: chunk
    integer :: ios, got
    n = 0
    source = ''
    open(unit=21, file=path, status='old', action='read', iostat=ios)
    if (ios /= 0) then
      call fail(d, 'cannot open source file: '//trim(path), 1, 1)
      return
    end if
10  continue
    got = 0
    read(21, '(a)', advance='no', size=got, iostat=ios, eor=20, end=30, err=40) chunk
    call append_chunk()
    if (d%failed) goto 50
    goto 10
20  continue
    call append_chunk()
    if (d%failed) goto 50
    if (n == len(source)) then
      call fail(d, 'source exceeds '//trim(int_text(len(source)))//' bytes', 1, 1)
      goto 50
    end if
    n = n + 1
    source(n:n) = achar(10)
    goto 10
30  continue
    call append_chunk()
    goto 50
40  continue
    call fail(d, 'error reading source file', 1, 1)
50  continue
    close(21)
  contains
    subroutine append_chunk()
      if (n + got > len(source)) then
        call fail(d, 'source exceeds '//trim(int_text(len(source)))//' bytes', 1, 1)
        return
      end if
      if (got > 0) source(n+1:n+got) = chunk(1:got)
      n = n + got
    end subroutine append_chunk
  end subroutine read_source

  subroutine advance(s, ch)
    type(lexer_state), intent(inout) :: s
    character, intent(in) :: ch
    s%pos = s%pos + 1
    if (ch == achar(10)) then
      s%line = s%line + 1
      s%column = 1
    else
      s%column = s%column + 1
    end if
  end subroutine advance

  subroutine lex_next(source, n, s, t, d)
    character(*), intent(in) :: source
    integer, intent(in) :: n
    type(lexer_state), intent(inout) :: s
    type(token), intent(out) :: t
    type(diagnostic), intent(inout) :: d
    character :: ch, delimiter
    logical :: ok, closed
    t = token(tk_eof, 0, 1, 1, '', 0.0_rk)
    if (d%failed) return
    ! Skip separators and comments outside literals only.
    do while (s%pos <= n)
      ch = source(s%pos:s%pos)
      if (ch == '#') then
        do while (s%pos <= n)
          ch = source(s%pos:s%pos)
          if (ch == achar(10)) exit
          call advance(s, ch)
        end do
      else if (ch == ' ' .or. ch == achar(9) .or. ch == achar(10) .or. ch == achar(13) .or. ch == ';') then
        call advance(s, ch)
      else
        exit
      end if
    end do
    t%line = s%line
    t%column = s%column
    if (s%pos > n) return
    ch = source(s%pos:s%pos)
    if (ch == '=') then
      if (s%pos < n) then
        if (source(s%pos+1:s%pos+1) == ')') then
          t%kind = tk_mark
          t%text = '=)'
          t%length = 2
          call advance(s, '=')
          call advance(s, ')')
          return
        end if
      end if
      call fail(d, 'bare = is not defined; use eq and ifnz, or =) for a routine', t%line, t%column)
      return
    end if
    if (is_alpha(ch)) then
      t%kind = tk_word
      do while (s%pos <= n)
        ch = source(s%pos:s%pos)
        if (.not. (is_alpha(ch) .or. is_digit(ch) .or. ch == '_')) exit
        if (t%length == max_name) then
          call fail(d, 'identifier exceeds 63 bytes', t%line, t%column)
          return
        end if
        call put(ch)
        call advance(s, ch)
      end do
      return
    end if
    if (ch == '{') then
      t%kind = tk_number
      call advance(s, ch)
      closed = .false.
      do while (s%pos <= n)
        ch = source(s%pos:s%pos)
        call advance(s, ch)
        if (ch == '}') then
          closed = .true.
          exit
        end if
        call put(ch)
        if (d%failed) return
      end do
      if (.not. closed) then
        call fail(d, 'unterminated number; expected }', t%line, t%column)
        return
      end if
      call parse_decimal(t%text(1:t%length), t%number, ok)
      if (.not. ok) call fail(d, 'invalid or out-of-range decimal number', t%line, t%column)
      return
    end if
    if (ch == '[' .or. ch == '"' .or. ch == "'") then
      t%kind = tk_text
      delimiter = ch
      if (ch == '[') delimiter = ']'
      call advance(s, ch)
      closed = .false.
      do while (s%pos <= n)
        ch = source(s%pos:s%pos)
        call advance(s, ch)
        if (ch == delimiter) then
          closed = .true.
          exit
        end if
        if (ch == achar(92)) then
          if (s%pos > n) exit
          ch = source(s%pos:s%pos)
          call advance(s, ch)
          select case (ch)
          case ('n'); ch = achar(10)
          case ('r'); ch = achar(13)
          case ('t'); ch = achar(9)
          end select
        end if
        call put(ch)
        if (d%failed) return
      end do
      if (.not. closed) call fail(d, 'unterminated text literal', t%line, t%column)
      return
    end if
    if (index(':+-*|~%_$@^`', ch) > 0) then
      t%kind = tk_symbol
      t%text = ch
      t%length = 1
      call advance(s, ch)
      return
    end if
    call fail(d, 'unexpected character; numbers use {123}, text uses [text] or quotes', t%line, t%column)
  contains
    subroutine put(c)
      character, intent(in) :: c
      if (t%length == max_text) then
        call fail(d, 'literal exceeds 2048 bytes', t%line, t%column)
        return
      end if
      t%length = t%length + 1
      t%text(t%length:t%length) = c
    end subroutine put
  end subroutine lex_next
end module urotif_lexer
