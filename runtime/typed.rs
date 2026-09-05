// Generic typed extension channel; signatures and bindings are emitted tables.
impl Engine {
    fn apply_typed(&mut self, slot: usize, ids: &[Id]) -> Res<()> {
        let sig = SYMBOLS.get(slot).ok_or(12)?;
        if ids.len() != sig.parameters.len() {
            return Err(12);
        }
        let mut args = Vec::with_capacity(ids.len());
        let mut packed: Vec<Vec<f64>> = Vec::with_capacity(ids.len());
        let (mut nb, mut nv) = (0usize, 0usize);
        for (&id, &tag) in ids.iter().zip(sig.parameters) {
            let v = self.nodes[id];
            let mut a = TypedArg {
                tag,
                ..TypedArg::default()
            };
            match tag {
                1 => {
                    if v.tag != 1 && v.tag != 4 {
                        return Err(12);
                    }
                    a.number = v.num;
                }
                2 => {
                    if v.tag != 2 {
                        return Err(12);
                    }
                    if v.len > TC - nb {
                        return Err(2);
                    }
                    nb += v.len;
                    a.length = v.len;
                    if v.len > 0 {
                        a.bytes = self.text[v.start..].as_ptr();
                    }
                }
                3 => {
                    if v.tag != 3 {
                        return Err(12);
                    }
                    if v.len > EC - nv {
                        return Err(2);
                    }
                    nv += v.len;
                    let mut vector = Vec::with_capacity(v.len);
                    for &child in &self.edges[v.start..v.start + v.len] {
                        let x = self.nodes[child];
                        if x.tag != 1 && x.tag != 4 {
                            return Err(12);
                        }
                        vector.push(x.num);
                    }
                    packed.push(vector);
                    a.count = v.len;
                    if v.len > 0 {
                        a.vector = packed.last().unwrap().as_ptr();
                    }
                }
                _ => return Err(12),
            }
            args.push(a);
        }
        let bc = if sig.result == 2 {
            OC.min(TC - self.text.len())
        } else {
            0
        };
        let vc = if sig.result == 3 {
            (OC / 8)
                .min(EC - self.edges.len())
                .min((NC - self.nodes.len() + self.free.len()).saturating_sub(1))
        } else {
            0
        };
        let mut rb = vec![0u8; bc];
        let mut rv = vec![0.0f64; vc];
        let mut out = TypedResult {
            number: f64::NAN,
            bytes: rb.as_mut_ptr(),
            capacity: bc,
            length: 0,
            vector: rv.as_mut_ptr(),
            vector_capacity: vc,
            count: 0,
        };
        let status = unsafe { foreign_typed(slot, args.as_ptr(), args.len(), &mut out) };
        if status != 0
            || out.bytes != rb.as_mut_ptr()
            || out.vector != rv.as_mut_ptr()
            || out.capacity != bc
            || out.vector_capacity != vc
            || out.length > bc
            || out.count > vc
        {
            return Err(12);
        }
        let id = match sig.result {
            1 => {
                if !out.number.is_finite() {
                    return Err(12);
                }
                self.number(out.number, false)?
            }
            2 => self.bytes(&rb[..out.length])?,
            3 => {
                if rv[..out.count].iter().any(|x| !x.is_finite()) {
                    return Err(12);
                }
                let mut children = Vec::with_capacity(out.count);
                for &x in &rv[..out.count] {
                    children.push(self.number(x, false)?);
                }
                self.array(&children)?
            }
            _ => return Err(12),
        };
        self.push(id)
    }
}
// Core-WASM has 32-bit pointers/size_t, unlike the tested 64-bit native ABI.
#[cfg(target_arch = "wasm32")]
const _: () = {
    assert!(std::mem::size_of::<TypedArg>() == 32);
    assert!(std::mem::size_of::<TypedResult>() == 32);
    assert!(std::mem::offset_of!(TypedArg, vector) == 24);
    assert!(std::mem::offset_of!(TypedResult, vector) == 20);
};
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_typed_arg_size() -> u32 {
    std::mem::size_of::<TypedArg>() as u32
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_typed_result_size() -> u32 {
    std::mem::size_of::<TypedResult>() as u32
}
