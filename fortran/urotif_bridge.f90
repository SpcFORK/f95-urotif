! This boundary, and ONLY the command-line driver, require Fortran 2003.
! The language core does not USE ISO_C_BINDING.
module urotif_bridge
  use, intrinsic :: iso_c_binding
  use urotif_types
  implicit none
  type, bind(C) :: c_instruction
    integer(c_int32_t) :: op, arg, line, column
    real(c_double) :: number
  end type c_instruction
  type, bind(C) :: c_text_span
    integer(c_int32_t) :: offset, length
  end type c_text_span
  interface
    function backend_emit(abi, code, count, entry, bytes, byte_count, texts, text_count, &
                          path, path_length, format, error, error_capacity) &
                          bind(C, name='urotif_backend_emit') result(status)
      import c_int32_t, c_size_t, c_char, c_instruction, c_text_span
      integer(c_int32_t), value :: abi, entry, format
      type(c_instruction), intent(in) :: code(*)
      integer(c_size_t), value :: count, byte_count, text_count, path_length, error_capacity
      character(kind=c_char), intent(in) :: bytes(*), path(*)
      type(c_text_span), intent(in) :: texts(*)
      character(kind=c_char), intent(out) :: error(*)
      integer(c_int32_t) :: status
    end function backend_emit
  end interface
contains
  subroutine emit_webassembly(p, path, as_wat, d)
    type(program_ir), intent(in) :: p
    character(*), intent(in) :: path
    logical, intent(in) :: as_wat
    type(diagnostic), intent(inout) :: d
    type(c_instruction), allocatable :: wire(:)
    type(c_text_span), allocatable :: spans(:)
    character(kind=c_char), allocatable :: bytes(:), cpath(:)
    character(kind=c_char) :: error(1024)
    character(1024) :: message
    integer :: i, j, n, at, pathlen
    integer(c_int32_t) :: status, format
    if (d%failed) return
    n = 0
    do i = 0, p%string_count-1
      n = n + p%string_lengths(i)
    end do
    pathlen = len_trim(path)
    allocate(wire(0:p%count-1), spans(0:max(1,p%string_count)-1))
    allocate(bytes(0:max(1,n)-1), cpath(0:max(1,pathlen)-1))
    do i = 0, p%count-1
      wire(i)%op = int(p%code(i)%op, c_int32_t)
      wire(i)%arg = int(p%code(i)%arg, c_int32_t)
      wire(i)%line = int(p%code(i)%line, c_int32_t)
      wire(i)%column = int(p%code(i)%column, c_int32_t)
      wire(i)%number = real(p%code(i)%number, c_double)
    end do
    at = 0
    do i = 0, p%string_count-1
      spans(i)%offset = int(at, c_int32_t)
      spans(i)%length = int(p%string_lengths(i), c_int32_t)
      do j = 1, p%string_lengths(i)
        bytes(at) = char(iachar(p%strings(i)(j:j)), kind=c_char)
        at = at + 1
      end do
    end do
    do i = 1, pathlen
      cpath(i-1) = char(iachar(path(i:i)), kind=c_char)
    end do
    error = c_null_char
    format = 0_c_int32_t
    if (as_wat) format = 1_c_int32_t
    status = backend_emit(1_c_int32_t, wire, int(p%count,c_size_t), int(p%entry,c_int32_t), &
      bytes, int(n,c_size_t), spans, int(p%string_count,c_size_t), cpath, int(pathlen,c_size_t), &
      format, error, int(size(error),c_size_t))
    if (status /= 0) then
      message = ''
      do i = 1, size(error)
        if (error(i) == c_null_char) exit
        message(i:i) = achar(iachar(error(i)))
      end do
      call fail(d, 'Rust chain: '//trim(message), 1, 1)
    end if
    deallocate(wire, spans, bytes, cpath)
  end subroutine emit_webassembly
end module urotif_bridge
