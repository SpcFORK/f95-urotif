//! Optional, reversible source metadata. NOT a Fortran/C/Rust decompiler.
//! CRC32 detects accidental corruption; it is not authentication or sandboxing.
use std::{
    fmt::Write,
    fs,
    panic::{catch_unwind, AssertUnwindSafe},
};
const MAX: usize = 8 * 1024 * 1024;
fn crc32(b: &[u8]) -> u32 {
    let mut c = !0u32;
    for &x in b {
        c ^= x as u32;
        for _ in 0..8 {
            c = (c >> 1) ^ (0xedb88320u32.wrapping_mul(c & 1));
        }
    }
    !c
}
pub fn text(source: &[u8], prefix: &str) -> String {
    let mut s = format!(
        "\n{prefix} UROTIF-SOURCE-V1 {} {:08x}\n",
        source.len(),
        crc32(source)
    );
    for line in source.chunks(48) {
        write!(s, "{prefix} UROTIF-HEX ").unwrap();
        for b in line {
            write!(s, "{b:02x}").unwrap();
        }
        s.push('\n');
    }
    writeln!(s, "{prefix} UROTIF-END").unwrap();
    s
}
fn leb(mut n: usize, b: &mut Vec<u8>) {
    loop {
        let x = (n & 127) as u8;
        n >>= 7;
        b.push(x | if n > 0 { 128 } else { 0 });
        if n == 0 {
            return;
        }
    }
}
fn read_leb(b: &[u8], at: &mut usize) -> Result<usize, String> {
    let mut n = 0u32;
    for k in 0..5 {
        let x = *b.get(*at).ok_or("truncated WASM length")?;
        *at += 1;
        if k == 4 && x > 15 {
            return Err("invalid WASM length".into());
        }
        n |= ((x & 127) as u32) << (k * 7);
        if x & 128 == 0 {
            return Ok(n as usize);
        }
    }
    Err("invalid WASM length".into())
}
pub fn wasm(source: &[u8]) -> Vec<u8> {
    let name = b"urotif.source.v1";
    let mut body = Vec::new();
    leb(name.len(), &mut body);
    body.extend_from_slice(name);
    body.extend_from_slice(b"URT1");
    body.extend_from_slice(&(source.len() as u32).to_le_bytes());
    body.extend_from_slice(&crc32(source).to_le_bytes());
    body.extend_from_slice(source);
    let mut section = vec![0];
    leb(body.len(), &mut section);
    section.extend(body);
    section
}
fn verified(b: Vec<u8>, n: usize, crc: u32) -> Result<Vec<u8>, String> {
    if n > MAX || b.len() != n || crc32(&b) != crc {
        Err("source capsule length/checksum mismatch".into())
    } else {
        Ok(b)
    }
}
pub fn recover(b: &[u8]) -> Result<Vec<u8>, String> {
    if b.starts_with(b"\0asm") {
        if b.get(4..8) != Some(&[1, 0, 0, 0]) {
            return Err("unsupported WASM version".into());
        }
        let mut at = 8;
        let mut found = None;
        while at < b.len() {
            let kind = b[at];
            at += 1;
            let n = read_leb(b, &mut at)?;
            let end = at
                .checked_add(n)
                .filter(|e| *e <= b.len())
                .ok_or("truncated WASM section")?;
            if kind == 0 {
                let mut p = at;
                let l = read_leb(&b[..end], &mut p)?;
                let q = p
                    .checked_add(l)
                    .filter(|e| *e <= end)
                    .ok_or("invalid custom name")?;
                if &b[p..q] == b"urotif.source.v1" {
                    if found.is_some() {
                        return Err("duplicate source capsule".into());
                    }
                    let x = &b[q..end];
                    if x.len() < 12 || &x[..4] != b"URT1" {
                        return Err("invalid source capsule".into());
                    }
                    let n = u32::from_le_bytes(x[4..8].try_into().unwrap()) as usize;
                    let c = u32::from_le_bytes(x[8..12].try_into().unwrap());
                    found = Some(verified(x[12..].to_vec(), n, c)?);
                }
            }
            at = end;
        }
        return found.ok_or("no source capsule; emit with --embed-source".into());
    }
    let text =
        std::str::from_utf8(b).map_err(|_| "not a generated text artifact or WASM module")?;
    let mut expected = None;
    let mut bytes = Vec::new();
    let mut ended = false;
    for line in text.lines() {
        let raw = line.trim_start();
        let Some(raw) = raw.strip_prefix('!').or_else(|| raw.strip_prefix("//")) else {
            continue;
        };
        let raw = raw.trim_start();
        if let Some(h) = raw.strip_prefix("UROTIF-SOURCE-V1 ") {
            if expected.is_some() {
                return Err("duplicate source capsule".into());
            }
            let p = h.split_whitespace().collect::<Vec<_>>();
            if p.len() != 2 {
                return Err("bad source capsule header".into());
            }
            let n = p[0].parse::<usize>().map_err(|_| "bad source length")?;
            if n > MAX {
                return Err("source capsule too large".into());
            }
            let c = u32::from_str_radix(p[1], 16).map_err(|_| "bad source checksum")?;
            expected = Some((n, c));
        } else if let Some(hex) = raw.strip_prefix("UROTIF-HEX ") {
            if expected.is_none() || ended || hex.len() % 2 != 0 {
                return Err("bad source capsule order/encoding".into());
            }
            if bytes.len() + hex.len() / 2 > MAX {
                return Err("source capsule too large".into());
            }
            for p in hex.as_bytes().chunks(2) {
                let x = std::str::from_utf8(p).map_err(|_| "invalid hex")?;
                bytes.push(u8::from_str_radix(x, 16).map_err(|_| "invalid source hex")?);
            }
        } else if raw == "UROTIF-END" {
            if expected.is_none() || ended {
                return Err("bad source capsule ending".into());
            }
            ended = true;
        }
    }
    let (n, c) = expected.ok_or("no source capsule; emit with --embed-source")?;
    if !ended {
        return Err("incomplete source capsule".into());
    }
    verified(bytes, n, c)
}
#[no_mangle]
pub unsafe extern "C" fn urotif_source_recover(
    input: *const u8,
    input_len: usize,
    output: *const u8,
    output_len: usize,
    error: *mut u8,
    cap: usize,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let a = std::str::from_utf8(unsafe { crate::checked_slice(input, input_len, 4096)? })
            .map_err(|_| "input path must be UTF-8")?;
        let b = std::str::from_utf8(unsafe { crate::checked_slice(output, output_len, 4096)? })
            .map_err(|_| "output path must be UTF-8")?;
        if a == b || a.is_empty() || b.is_empty() {
            return Err("recovery needs distinct nonempty paths".into());
        }
        if fs::metadata(a).map_err(|e| e.to_string())?.len() > 512 * 1024 * 1024 {
            return Err("artifact exceeds recovery size guard".into());
        }
        let source = recover(&fs::read(a).map_err(|e| e.to_string())?)?;
        let temp = format!("{b}.recover-{}", std::process::id());
        fs::write(&temp, &source).map_err(|e| e.to_string())?;
        fs::rename(&temp, b).map_err(|e| {
            let _ = fs::remove_file(&temp);
            e.to_string()
        })?;
        Ok(())
    }))
    .unwrap_or_else(|_| Err("source recovery panic contained".into()));
    let (status, message) = match result {
        Ok(()) => (0, String::new()),
        Err(e) => (1, e),
    };
    if cap > 0 && !error.is_null() {
        let n = message.len().min(cap - 1);
        unsafe {
            std::ptr::copy_nonoverlapping(message.as_ptr(), error, n);
            *error.add(n) = 0;
        }
    }
    status
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn capsule_roundtrips() {
        let b = b"=) urotif\n[bytes\\!]P@h@\n";
        for p in ["!", "//"] {
            assert_eq!(recover(text(b, p).as_bytes()).unwrap(), b)
        }
        let mut w = b"\0asm\x01\0\0\0".to_vec();
        w.extend(wasm(b));
        assert_eq!(recover(&w).unwrap(), b);
    }
    #[test]
    fn corrupt_capsule_rejected() {
        let mut s = text(b"abcd", "!");
        s = s.replace("61626364", "62626364");
        assert!(recover(s.as_bytes()).is_err());
        assert!(recover(b"! UROTIF-SOURCE-V1 0 00000000").is_err());
    }
}
