//! Standalone Fortran emission from the already decoded Fortran-owned IR.
//! Shares the actual F95 value/GC/primitive routines with native execution.
use crate::{
    foundation::{lines, Inst},
    host,
    limits::Limits,
};
use std::fmt::Write;

fn data(s: &mut String, name: &str, values: &[String]) {
    // Small DATA statements avoid F95's continuation-statement ceiling.
    // A constructor with tens of thousands of continuation lines is not F95.
    let empty = vec!["0".to_owned()];
    let values = if values.is_empty() {
        &empty[..]
    } else {
        values
    };
    for (block, chunk) in values.chunks(64).enumerate() {
        writeln!(
            s,
            "  data ({name}(j),j={},{}) / &",
            block * 64,
            block * 64 + chunk.len() - 1
        )
        .unwrap();
        let mut runs: Vec<String> = Vec::new();
        let mut at = 0;
        while at < chunk.len() {
            let mut end = at + 1;
            while end < chunk.len() && chunk[end] == chunk[at] {
                end += 1;
            }
            runs.push(if end - at > 1 {
                format!("{}*{}", end - at, chunk[at])
            } else {
                chunk[at].clone()
            });
            at = end;
        }
        let mut line = String::from("    ");
        for (i, v) in runs.iter().enumerate() {
            let token = format!("{v}{}", if i + 1 == runs.len() { " /" } else { "," });
            if line.len() + token.len() > 105 {
                writeln!(s, "{line} &").unwrap();
                line = String::from("    ");
            }
            line.push_str(&token);
        }
        writeln!(s, "{line}").unwrap();
    }
}
fn ints(s: &mut String, name: &str, v: impl IntoIterator<Item = i32>) {
    data(
        s,
        name,
        &v.into_iter().map(|n| n.to_string()).collect::<Vec<_>>(),
    );
}

pub fn source(
    code: &[Inst],
    entry: i32,
    literals: &[Vec<u8>],
    limits: &Limits,
    strict95: bool,
) -> Result<String, String> {
    let r = host::registry();
    let has_typed = r.symbols.iter().any(|x| x.signature.is_some());
    let has_foreign = r.symbols.iter().any(|x| x.module >= 2);
    if strict95 && r.symbols.iter().any(|x| x.module >= 2) {
        return Err(
            "--f95 supports std/math only; C/Rust plugin bindings require the F2003 adapter".into(),
        );
    }
    let mut s=String::from("! Urotif 0.4: Fortran frontend -> decoded IR -> standalone Fortran.\n! No Rust library or Urotif parser is needed to compile/run this file.\n! F95 core; F2003 CLI/C bindings unless emitted with --f95.\n");
    s.push_str(include_str!("../../fortran/urotif_types.f90"));
    s.push_str(include_str!("../../fortran/urotif_limits.f90"));
    s.push_str(include_str!("../../fortran/urotif_host_api.f90"));
    if has_typed {
        s.push_str(include_str!("../../fortran/urotif_typed_abi.f90"));
    }
    let core = include_str!("../../fortran/urotif_prototype.f90")
        .replace("  use urotif_lexer, only: read_source\n", "")
        .replace("  include 'prototype_driver.inc'", "")
        .replace(
            "  include 'byte_helpers.inc'",
            include_str!("../../fortran/byte_helpers.inc"),
        )
        .replace(
            "  include 'foundation_methods.inc'",
            include_str!("../../fortran/foundation_methods.inc"),
        )
        .replace(
            "  include 'typed_methods.inc'",
            include_str!("../../fortran/typed_methods.inc"),
        );
    s.push_str(&core);
    let ls = lines(code);
    writeln!(s,"\nmodule urotif_tables\n  use urotif_limits\n  implicit none\n  integer,private::j\n  integer,parameter::code_count={},entry_pc={entry},source_lines={}\n  logical,parameter::uses_input={}\n  type(runtime_limits),parameter::program_limits=runtime_limits( &\n    {})",
        code.len(),ls.len(),if code.iter().any(|i|i.op==18){".true."}else{".false."},limits.0.iter().map(|n|n.to_string()).collect::<Vec<_>>().join(",")).unwrap();
    for name in [
        "ir_op",
        "ir_arg",
        "ir_next",
        "ir_cost",
        "ir_line",
        "ir_column",
    ] {
        writeln!(s, "  integer,save::{name}(0:code_count-1)").unwrap();
    }
    s.push_str("  real(rk),save::ir_number(0:code_count-1)\n  integer,save::line_start(0:source_lines-1),line_length(0:source_lines-1)\n");
    writeln!(s,"  integer,parameter::module_count={},symbol_count={}\n  character(63),save::module_names(0:module_count-1),symbol_names(0:symbol_count-1)\n  integer,save::symbol_module(0:symbol_count-1),symbol_arity(0:symbol_count-1),symbol_kind(0:symbol_count-1)",r.modules.len(),r.symbols.len()).unwrap();
    s.push_str(
        "  integer,save::symbol_parameters(0:8*symbol_count-1),symbol_result(0:symbol_count-1)\n",
    );
    let n = literals.iter().map(Vec::len).sum::<usize>();
    writeln!(
        s,
        "  integer,save::literal_start(0:{}),literal_length(0:{}),literal_bytes(0:{})",
        literals.len().max(1) - 1,
        literals.len().max(1) - 1,
        n.max(1) - 1
    )
    .unwrap();
    for (name, v) in [
        ("ir_op", code.iter().map(|i| i.op).collect::<Vec<_>>()),
        ("ir_arg", code.iter().map(|i| i.arg).collect()),
        ("ir_next", code.iter().map(|i| i.next).collect()),
        ("ir_cost", code.iter().map(|i| i.cost).collect()),
        ("ir_line", code.iter().map(|i| i.line).collect()),
        ("ir_column", code.iter().map(|i| i.column).collect()),
    ] {
        ints(&mut s, name, v);
    }
    data(
        &mut s,
        "ir_number",
        &code
            .iter()
            .map(|i| format!("{:.17e}_rk", i.number))
            .collect::<Vec<_>>(),
    );
    ints(&mut s, "line_start", ls.iter().map(|(a, _)| *a as i32));
    ints(&mut s, "line_length", ls.iter().map(|(_, b)| *b as i32));
    data(
        &mut s,
        "module_names",
        &r.modules
            .iter()
            .map(|m| format!("'{m}'"))
            .collect::<Vec<_>>(),
    );
    data(
        &mut s,
        "symbol_names",
        &r.symbols
            .iter()
            .map(|x| format!("'{}'", x.name))
            .collect::<Vec<_>>(),
    );
    ints(
        &mut s,
        "symbol_module",
        r.symbols.iter().map(|x| x.module as i32),
    );
    ints(
        &mut s,
        "symbol_arity",
        r.symbols.iter().map(|x| x.arity as i32),
    );
    ints(&mut s, "symbol_kind", r.symbols.iter().map(|x| x.kind));
    let mut parameters = Vec::new();
    for x in &r.symbols {
        let mut a = [0; 8];
        if let Some(sig) = &x.signature {
            for (i, k) in sig.parameters.iter().enumerate() {
                a[i] = *k as i32;
            }
        }
        parameters.extend_from_slice(&a);
    }
    ints(&mut s, "symbol_parameters", parameters);
    ints(
        &mut s,
        "symbol_result",
        r.symbols
            .iter()
            .map(|x| x.signature.as_ref().map_or(0, |s| s.result as i32)),
    );
    let mut at = 0;
    let starts = literals
        .iter()
        .map(|b| {
            let n = at;
            at += b.len() as i32;
            n
        })
        .collect::<Vec<_>>();
    ints(&mut s, "literal_start", starts);
    ints(
        &mut s,
        "literal_length",
        literals.iter().map(|b| b.len() as i32),
    );
    ints(
        &mut s,
        "literal_bytes",
        literals.iter().flatten().map(|b| *b as i32),
    );
    s.push_str("end module urotif_tables\n");
    // Only these adapters, not the value runtime, require C interoperability.
    if has_foreign {
        s.push_str("module urotif_foreign\n  use,intrinsic::iso_c_binding\n");
        if has_typed {
            s.push_str("  use urotif_typed_abi,only:typed_arg,typed_result\n");
        }
        s.push_str("  implicit none\n  interface\n");
        for (id, x) in r.symbols.iter().enumerate().filter(|(_, x)| x.module >= 2) {
            writeln!(s, "    function ext_{id}(a,n,out) &").unwrap();
            let binding = format!(
                "        bind(C,name='urotif_ext_{}_{}') result(status)",
                r.modules[x.module], x.name
            );
            if binding.len() <= 132 {
                writeln!(s, "{binding}").unwrap();
            } else {
                writeln!(s,"        bind(C,name='urotif_ext_'// &\n          '{}_'// &\n          '{}') result(status)",r.modules[x.module],x.name).unwrap();
            }
            if x.signature.is_some() {
                s.push_str("      import typed_arg,typed_result,c_size_t,c_int32_t\n      type(typed_arg),intent(in)::a(*)\n      type(typed_result),intent(inout)::out\n");
            } else {
                s.push_str("      import c_double,c_size_t,c_int32_t\n      real(c_double),intent(in)::a(*)\n      real(c_double),intent(inout)::out\n");
            }
            s.push_str("      integer(c_size_t),value::n\n      integer(c_int32_t)::status\n    end function\n");
        }
        s.push_str("  end interface\nend module urotif_foreign\n");
    }
    s.push_str(include_str!("../../runtime/fortran_lookup.f90"));
    s.push_str("subroutine uf_host_apply(id,args,n,result,status,message)\n  use urotif_tables\n  use urotif_types,only:finite_number\n");
    if has_foreign {
        s.push_str("  use urotif_foreign\n  use,intrinsic::ieee_arithmetic,only:ieee_value,ieee_quiet_nan\n");
    }
    s.push_str("  implicit none\n  integer,intent(in)::id,n\n  real(rk),intent(in)::args(*)\n  real(rk),intent(out)::result\n  integer,intent(out)::status\n  character(*),intent(out)::message\n  result=0.0_rk;status=1;message='external application failed'\n  if(id<0.or.id>=symbol_count)return\n  if(n/=symbol_arity(id))return\n");
    if has_foreign {
        s.push_str("  result=ieee_value(0.0_rk,ieee_quiet_nan)\n");
    }
    s.push_str("  select case(id)\n");
    for (id, x) in r.symbols.iter().enumerate().filter(|(_, x)| x.kind == 0) {
        writeln!(s, "  case({id})").unwrap();
        if x.module == 1 {
            let expr = match x.name.as_str() {
                "sqrt" => "sqrt(args(1))",
                "square" => "args(1)*args(1)",
                "abs" => "abs(args(1))",
                "add" => "args(1)+args(2)",
                _ => unreachable!(),
            };
            if x.name == "sqrt" {
                s.push_str("    if(args(1)<0.0_rk)return\n");
            }
            writeln!(s, "    result={expr};status=0").unwrap();
        } else {
            writeln!(s, "    status=int(ext_{id}(args,int(n,c_size_t),result))").unwrap();
        }
    }
    s.push_str("  end select\n  if(.not.finite_number(result))status=1\n  if(status==0)message=''\nend subroutine uf_host_apply\n");
    s.push_str(include_str!("../../runtime/fortran_typed_signature.f90"));
    if has_typed {
        s.push_str("subroutine uf_typed_dispatch(id,args,n,result,status,message)\n  use urotif_foreign\n  implicit none\n  integer,intent(in)::id,n\n  type(typed_arg),intent(in)::args(*)\n  type(typed_result),intent(inout)::result\n  integer,intent(out)::status\n  character(*),intent(out)::message\n  status=1;message='typed service failure'\n  select case(id)\n");
        for (id, x) in r
            .symbols
            .iter()
            .enumerate()
            .filter(|(_, x)| x.signature.is_some())
        {
            writeln!(s,"  case({id})\n    if(n/={})return\n    status=int(ext_{id}(args,int(n,c_size_t),result))",x.arity).unwrap();
        }
        s.push_str("  end select\n  if(status==0)message=''\nend subroutine uf_typed_dispatch\n");
    } else {
        s.push_str(include_str!("../../runtime/fortran_typed_stub.f90"));
    }
    if strict95 {
        s.push_str("subroutine uf_flush_output()\nend subroutine\n");
    } else {
        s.push_str("subroutine uf_flush_output()\n  use,intrinsic::iso_fortran_env,only:output_unit\n  implicit none\n  flush(output_unit)\nend subroutine\n");
    }
    s.push_str(include_str!("../../runtime/foundation.f90"));
    if strict95 {
        s.push_str("! Strict F95 entry: stdin is program input, fuel is the default budget.\nprogram urotif_transpiled\n  use urotif_target\n  implicit none\n  type(prototype_state)::s\n  integer::pc\n  logical::failed\n  call target_run(s,1000000,pc)\n  if(s%output_length>0)call write_bytes(s%output(:s%output_length))\n  failed=s%error%failed\n  call proto_release(s)\n  if(failed)stop 1\nend program\n");
    } else {
        s.push_str(include_str!("../../runtime/fortran_cli.f90"));
    }
    Ok(s)
}
