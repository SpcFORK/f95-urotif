// Portable Foundation runtime template. Generated tables and imports are
// supplied by the native Rust backend from FORTRAN-predecoded IR.
use std::cell::RefCell;
type Id = usize;
type Res<T> = Result<T, i32>;
#[derive(Clone, Copy, Default)]
struct V {
    tag: u8,
    start: usize,
    len: usize,
    num: f64,
}
// 0 null, 1 float, 2 bytes, 3 array, 4 portable integer, 5 module, 6 external.
struct Engine {
    nodes: Vec<V>,
    edges: Vec<Id>,
    text: Vec<u8>,
    output: Vec<u8>,
    stack: Vec<Id>,
    frames: Vec<(usize, u8)>,
    returns: Vec<(usize, usize)>,
    free: Vec<Id>,
    chars: [Id; 256],
    refs: [Id; 256],
    modules: [Id; 32],
    arrays: Vec<Id>,
    strings: Vec<Id>,
    input: Vec<u8>,
    cursor: usize,
    stream_input:bool, stream_output:bool, printed:usize, input_total:usize,
    pc: usize,
    steps: u32,
    collections: u32,
    halted: bool,
    jump: Option<usize>,
}
impl Engine {
    fn new(input: Vec<u8>) -> Self {
        Self {
            nodes: vec![V::default()],
            edges: Vec::new(),
            text: Vec::new(),
            output: Vec::new(),
            stack: Vec::new(),
            frames: vec![(0, 0)],
            returns: Vec::new(),
            free: Vec::new(),
            chars: [0; 256],
            refs: [0; 256],
            modules: [0; 32],
            arrays: vec![0; LITERALS.len()],
            strings: vec![0; LITERALS.len()],
            input,
            cursor: 0,
            stream_input:false,stream_output:false,printed:0,input_total:0,
            pc: ENTRY,
            steps: 0,
            collections: 0,
            halted: false,
            jump: None,
        }
    }
    fn node(&mut self, v: V) -> Res<Id> {
        if let Some(id) = self.free.pop() {
            self.nodes[id] = v;
            Ok(id)
        } else {
            if self.nodes.len() >= NC {
                return Err(2);
            }
            self.nodes.push(v);
            Ok(self.nodes.len() - 1)
        }
    }
    fn number(&mut self, x: f64, int: bool) -> Res<Id> {
        if !x.is_finite() || (int && x.abs() > 9007199254740991.0) {
            return Err(10);
        }
        self.node(V {
            tag: if int { 4 } else { 1 },
            num: x,
            ..V::default()
        })
    }
    fn bytes(&mut self, b: &[u8]) -> Res<Id> {
        if self.text.len() + b.len() > TC {
            return Err(2);
        }
        let p = self.text.len();
        self.text.extend_from_slice(b);
        self.node(V {
            tag: 2,
            start: p,
            len: b.len(),
            num: 0.0,
        })
    }
    fn character(&mut self, c: u8) -> Res<Id> {
        let id = self.chars[c as usize];
        if id != 0 {
            return Ok(id);
        }
        let id = self.bytes(&[c])?;
        self.chars[c as usize] = id;
        Ok(id)
    }
    fn array(&mut self, ids: &[Id]) -> Res<Id> {
        if self.edges.len() + ids.len() > EC {
            return Err(2);
        }
        let p = self.edges.len();
        self.edges.extend_from_slice(ids);
        self.node(V {
            tag: 3,
            start: p,
            len: ids.len(),
            num: 0.0,
        })
    }
    fn push(&mut self, id: Id) -> Res<()> {
        if self.stack.len() >= SC {
            return Err(2);
        }
        self.stack.push(id);
        Ok(())
    }
    fn pop(&mut self) -> Res<Id> {
        if self.stack.len() == self.frames.last().unwrap().0 {
            return Err(1);
        }
        Ok(self.stack.pop().unwrap())
    }
    fn collect(&mut self) {
        let mut marked = vec![false; self.nodes.len()];
        marked[0] = true;
        let mut work = Vec::new();
        for &id in self
            .stack
            .iter()
            .chain(self.chars.iter())
            .chain(self.refs.iter())
            .chain(self.modules.iter())
            .chain(self.arrays.iter())
            .chain(self.strings.iter())
        {
            if !marked[id] {
                marked[id] = true;
                work.push(id)
            }
        }
        while let Some(id) = work.pop() {
            let v = self.nodes[id];
            if v.tag == 3 {
                for &x in &self.edges[v.start..v.start + v.len] {
                    if !marked[x] {
                        marked[x] = true;
                        work.push(x)
                    }
                }
            }
        }
        let mut edges = Vec::new();
        let mut text = Vec::new();
        self.free.clear();
        for id in 1..self.nodes.len() {
            if !marked[id] {
                self.free.push(id);
                self.nodes[id] = V::default();
                continue;
            }
            let v = self.nodes[id];
            if v.tag == 3 {
                self.nodes[id].start = edges.len();
                edges.extend_from_slice(&self.edges[v.start..v.start + v.len])
            }
            if v.tag == 2 {
                self.nodes[id].start = text.len();
                text.extend_from_slice(&self.text[v.start..v.start + v.len])
            }
        }
        self.edges = edges;
        self.text = text;
        self.collections += 1;
    }
    fn number_of(&self, id: Id, convert: bool) -> Res<f64> {
        let v = self.nodes[id];
        if v.tag == 1 || v.tag == 4 {
            return Ok(v.num);
        }
        if convert && v.tag == 2 {
            decimal(&self.text[v.start..v.start + v.len]).ok_or(4)
        } else {
            Err(4)
        }
    }
    fn repr(&self, id: Id, out: &mut Vec<u8>, quoted: bool, depth: usize) -> Res<()> {
        if depth > FC {
            return Err(2);
        }
        let v = self.nodes[id];
        match v.tag {
            0 => append(out, b"?"),
            1 | 4 => append(out, number_text(v.num).as_bytes()),
            2 => {
                if quoted {
                    append(out, b"'")?
                }
                for &c in &self.text[v.start..v.start + v.len] {
                    if quoted {
                        match c {
                            b'\n' => {
                                append(out, b"\\n")?;
                                continue;
                            }
                            b'\r' => {
                                append(out, b"\\r")?;
                                continue;
                            }
                            b'\t' => {
                                append(out, b"\\t")?;
                                continue;
                            }
                            b'\\' | b'\'' => append(out, b"\\")?,
                            _ => {}
                        }
                    }
                    append(out, &[c])?
                }
                if quoted {
                    append(out, b"'")?
                }
                Ok(())
            }
            3 => {
                append(out, b"[")?;
                for (i, &x) in self.edges[v.start..v.start + v.len].iter().enumerate() {
                    if i > 0 {
                        append(out, b", ")?
                    }
                    self.repr(x, out, true, depth + 1)?
                }
                append(out, b"]")
            }
            5 => append(out, format!("<module:{}>", v.start).as_bytes()),
            6 => append(out, format!("<external:{}>", v.start).as_bytes()),
            _ => Err(4),
        }
    }
    fn print(&mut self, id: Id) -> Res<()> {
        let mut out = Vec::new();
        self.repr(id, &mut out, false, 0)?;
        append(&mut self.output, &out)
    }
    fn join(&mut self, id: Id, stringify: bool) -> Res<Id> {
        let v = self.nodes[id];
        if v.tag != 3 {
            return Err(4);
        }
        let mut b = Vec::new();
        for &x in &self.edges[v.start..v.start + v.len] {
            if stringify {
                self.repr(x, &mut b, false, 0)?
            } else {
                let x = self.nodes[x];
                if x.tag != 2 {
                    return Err(4);
                }
                append(&mut b, &self.text[x.start..x.start + x.len])?
            }
        }
        self.bytes(&b)
    }
    fn equal(&self, a: Id, b: Id, work: &mut usize, depth:usize) -> Res<bool> {
        if *work == 0 {
            return Err(2);
        }
        *work -= 1;
        if a == b {return Ok(true);}
        if depth>FC{return Err(2)}
        let (a, b) = (self.nodes[a], self.nodes[b]);
        if matches!(a.tag, 1 | 4) && matches!(b.tag, 1 | 4) {
            return Ok(a.num == b.num);
        }
        if a.tag != b.tag {
            return Ok(false);
        }
        Ok(match a.tag {
            0 => true,
            2 => self.text[a.start..a.start + a.len] == self.text[b.start..b.start + b.len],
            3 => {
                if a.len != b.len {
                    return Ok(false);
                }
                for i in 0..a.len {
                    if !self.equal(self.edges[a.start + i], self.edges[b.start + i], work,depth+1)? {
                        return Ok(false);
                    }
                }
                true
            }
            5 | 6 => a.start == b.start,
            _ => false,
        })
    }
    fn close(&mut self, kind: u8) -> Res<Id> {
        if self.frames.len() == 1 {
            return Err(3);
        }
        let (base, k) = *self.frames.last().unwrap();
        if k != kind {
            return Err(3);
        }
        let ids = self.stack[base..].to_vec();
        let array = self.array(&ids)?;
        self.stack.truncate(base);
        self.frames.pop();
        Ok(array)
    }
    fn name(&self, id: Id) -> Res<String> {
        let v = self.nodes[id];
        let mut out = Vec::new();
        match v.tag {
            2 => out.extend_from_slice(&self.text[v.start..v.start + v.len]),
            3 => {
                for &x in &self.edges[v.start..v.start + v.len] {
                    let x = self.nodes[x];
                    if x.tag != 2 {
                        return Err(11);
                    }
                    out.extend_from_slice(&self.text[x.start..x.start + x.len]);
                    if out.len() > 127 {
                        return Err(11);
                    }
                }
            }
            _ => return Err(11),
        }
        if out.len() > 127 {
            return Err(11);
        }
        String::from_utf8(out).map_err(|_| 11)
    }
    fn reference(&mut self, module: usize, name: &str) -> Res<Id> {
        let id = SYMBOLS
            .iter()
            .position(|s| s.module == module && s.name == name)
            .ok_or(11)?;
        self.ref_id(id)
    }
    fn ref_id(&mut self, id: usize) -> Res<Id> {
        let s = SYMBOLS.get(id).ok_or(11)?;
        if self.refs[id] != 0 {
            return Ok(self.refs[id]);
        }
        let v = self.node(V {
            tag: 6,
            start: id,
            len: s.arity,
            num: s.kind as f64,
        })?;
        self.refs[id] = v;
        Ok(v)
    }
    fn resolve(&mut self, name: &str) -> Res<Id> {
        let (m, n) = name.split_once('.').unwrap_or(("std", name));
        let m = MODULES.iter().position(|x| *x == m).ok_or(11)?;
        self.reference(m, n)
    }
    fn apply(&mut self, r: Id, args: &[Id]) -> Res<()> {
        let r = self.nodes[r];
        if r.tag != 6 || r.len != args.len() || args.len() > 8 {
            return Err(12);
        }
        if r.num as u8==7{return self.apply_typed(r.start,args)}
        let id = match r.num as u8 {
            1 | 2 => {
                let x = self.number_of(args[0], true).map_err(|_| 12)?;
                if r.num == 1.0 {
                    if x.abs() > 9007199254740991.0 {
                        return Err(12);
                    }
                    self.number(x.trunc(), true)?
                } else {
                    self.number(x, false)?
                }
            }
            3 => {
                let mut b = Vec::new();
                self.repr(args[0], &mut b, false, 0)?;
                self.bytes(&b)?
            }
            4 => {
                let v = self.nodes[args[0]];
                if v.tag != 2 && v.tag != 3 {
                    return Err(12);
                }
                self.number(v.len as f64, true)?
            }
            0 => {
                let mut a = [0.0; 8];
                for (i, &v) in args.iter().enumerate() {
                    a[i] = self.number_of(v, false).map_err(|_| 12)?
                }
                let x = foreign_call(r.start, &a[..args.len()])?;
                if !x.is_finite() {
                    return Err(12);
                }
                self.number(x, false)?
            }
            _ => return Err(12),
        };
        self.push(id)
    }
    fn at(&mut self, next: usize) -> Res<()> {
        let sym = self.pop()?;
        let v = self.nodes[sym];
        if v.tag == 6 {
            if v.len > 8 {
                return Err(12);
            }
            let mut args = vec![0; v.len];
            for i in (0..v.len).rev() {
                args[i] = self.pop()?
            }
            return self.apply(sym, &args);
        }
        if v.tag != 2 || v.len != 1 {
            return Err(6);
        }
        let command = self.text[v.start];
        if command == b'h' {
            self.halted = true;
            return Ok(());
        }
        if command == b'R' {
            let (pc, depth) = self.returns.pop().ok_or(13)?;
            if depth != self.frames.len() {
                return Err(13);
            }
            self.jump = Some(pc);
            return Ok(());
        }
        if matches!(command,b'x'|b'o'|b't') {
            let n=if command==b't'{3}else{2};let sp=self.stack.len();
            if sp-self.frames.last().unwrap().0<n{return Err(1)}
            let a=self.stack[sp-n];
            if command==b'o'{self.push(a)?;}else if command==b'x'{self.stack.swap(sp-2,sp-1);}else{self.stack[sp-3..].rotate_left(1);}
            return Ok(())
        }
        if command==b'd'{let id=self.number((self.stack.len()-self.frames.last().unwrap().0)as f64,true)?;return self.push(id)}
        let arg = self.pop()?;
        if command==b'b'{
            let n=self.number_of(arg,false)?;
            if n<0.0||n!=n.trunc(){return Err(4)}
            if n>(self.stack.len()-self.frames.last().unwrap().0)as f64{return Err(1)}
            let base=self.stack.len()-n as usize;let ids=self.stack[base..].to_vec();
            let id=self.array(&ids)?;self.stack.truncate(base);return self.push(id)
        }
        let v = self.nodes[arg];
        match command {
            b'p' | b'P' => {
                if v.tag == 3 {
                    let ids = self.edges[v.start..v.start + v.len].to_vec();
                    for x in ids {
                        if self.nodes[x].tag != 2 {
                            return Err(4);
                        }
                        self.print(x)?
                    }
                } else if v.tag == 2 {
                    self.print(arg)?
                } else {
                    return Err(4);
                }
                if command == b'P' {
                    append(&mut self.output, b"\n")?
                }
            }
            b'S' => {
                let x = self.join(arg, false)?;
                self.push(x)?
            }
            b's' => {
                let mut b = Vec::new();
                self.repr(arg, &mut b, false, 0)?;
                let x = self.bytes(&b)?;
                self.push(x)?
            }
            b'i' => {
                let name = self.name(arg)?;
                let id = MODULES.iter().position(|x| *x == name).ok_or(11)?;
                let mut x = self.modules[id];
                if x == 0 {
                    x = self.node(V {
                        tag: 5,
                        start: id,
                        ..V::default()
                    })?;
                    self.modules[id] = x
                }
                self.push(x)?
            }
            b'G' | b'r' => {
                let name = self.name(arg)?;
                let x = if command == b'G' {
                    self.reference(0, &name)?
                } else {
                    self.resolve(&name)?
                };
                self.push(x)?
            }
            b'g' => {
                if v.tag != 3 || v.len != 2 {
                    return Err(11);
                }
                let m = self.nodes[self.edges[v.start]];
                if m.tag != 5 {
                    return Err(11);
                }
                let name = self.name(self.edges[v.start + 1])?;
                let x = self.reference(m.start, &name)?;
                self.push(x)?
            }
            b'a' | b'C' => {
                if v.tag != 3 || v.len < 1 || v.len > 9 {
                    return Err(12);
                }
                let mut r = self.edges[v.start];
                if command == b'C' {
                    let name = self.name(r)?;
                    r = self.reference(0, &name)?
                }
                let args = self.edges[v.start + 1..v.start + v.len].to_vec();
                self.apply(r, &args)?
            }
            b'k' => {
                if v.tag != 3 || v.len != 2 {
                    return Err(13);
                }
                let y = self.number_of(self.edges[v.start], true).map_err(|_| 13)?;
                let x = self
                    .number_of(self.edges[v.start + 1], true)
                    .map_err(|_| 13)?;
                let pc = coordinate(y, x).map_err(|_| 13)?;
                if self.returns.len() == RC {
                    return Err(13);
                }
                self.returns.push((next, self.frames.len()));
                self.jump = Some(pc)
            }
            _ => return Err(6),
        }
        Ok(())
    }
    fn literal(&mut self, pool: usize, text: bool) -> Res<Id> {
        let id = if text {
            self.strings[pool]
        } else {
            self.arrays[pool]
        };
        if id != 0 {
            return Ok(id);
        }
        let id = if text {
            self.bytes(LITERALS[pool])?
        } else {
            let mut ids = Vec::new();
            for &c in LITERALS[pool] {
                ids.push(self.character(c)?)
            }
            self.array(&ids)?
        };
        if text {
            self.strings[pool] = id
        } else {
            self.arrays[pool] = id
        }
        Ok(id)
    }
    fn read(&mut self) -> Res<Id> {
        #[cfg(not(target_arch="wasm32"))]
        if self.stream_input {
            use std::io::{Read,BufRead};
            let mut bytes=Vec::new();
            std::io::stdin().lock().take((LC+2)as u64).read_until(b'\n',&mut bytes).map_err(|_|9)?;
            if bytes.is_empty()||bytes.len()>INPUT_CAP-self.input_total{return Err(9)}
            self.input_total+=bytes.len();
            if bytes.last()==Some(&b'\n'){bytes.pop();}
            if bytes.last()==Some(&b'\r'){bytes.pop();}
            if bytes.len()>LC{return Err(9)}
            return self.bytes(&bytes)
        }
        if self.cursor >= self.input.len() {
            return Err(9);
        }
        let begin = self.cursor;
        while self.cursor < self.input.len() && self.input[self.cursor] != b'\n' {
            self.cursor += 1
        }
        let mut end = self.cursor;
        if self.cursor < self.input.len() {
            self.cursor += 1
        }
        if end > begin && self.input[end - 1] == b'\r' {
            end -= 1
        }
        if end - begin > LC {
            return Err(9);
        }
        let bytes = self.input[begin..end].to_vec();
        self.bytes(&bytes)
    }
    fn flush_pending(&mut self)->Res<()> {
        #[cfg(not(target_arch="wasm32"))]
        if self.stream_output && self.printed<self.output.len(){
            use std::io::Write;
            let mut out=std::io::stdout().lock();
            out.write_all(&self.output[self.printed..]).map_err(|_|9)?;out.flush().map_err(|_|9)?;
            self.printed=self.output.len();
        }
        Ok(())
    }
    fn run(&mut self, fuel: u32) -> i32 {
        let status=self.execute(fuel).err().unwrap_or(0);
        let io=self.flush_pending().err().unwrap_or(0);
        if status!=0{status}else{io}
    }
    fn execute(&mut self, fuel: u32) -> Res<()> {
        loop {
            let mut i = *CODE.get(self.pc).ok_or(7)?;
            if i.op == 0 {
                break;
            }
            if i.op == 3 {
                self.pc = i.next;
                continue;
            }
            let edge_need=self.stack.len().max(if i.op==24{LITERALS[i.arg].len()}else{0});
            if self.nodes.len() - self.free.len() > NC - 16
                || self.edges.len() > EC - (EC/2).min(edge_need) - 16
                || self.text.len() > TC - (TC/2).min(OC) - 16
            {
                self.collect()
            }
            // Fast paths have original entry/fallback instructions. A partial budget
            // executes the original '[' instead, preserving observable fuel boundaries.
            if (23..=26).contains(&i.op)
                && (fuel.saturating_sub(self.steps) < i.cost
                    || self.frames.len() == FC + 1
                    || self.stack.len()
                        + if i.op == 23 || i.op == 25 {
                            (i.cost as usize - 4).max(2)
                        } else {
                            (i.cost as usize - 2).max(1)
                        }
                        > SC)
            {
                i.arg = if i.op == 26 { 1 } else { 0 };
                i.op = 5;
                i.next = self.pc + 1;
                i.cost = 1
            }
            if self.steps.checked_add(i.cost).ok_or(8)? > fuel {
                return Err(8);
            }
            self.steps += i.cost;
            let mut next = i.next;
            match i.op {
                1 | 27 => {
                    let x = self.character(i.arg as u8)?;
                    self.push(x)?
                }
                2 | 21 => {}
                4 => {
                    if i.arg > 255 {
                        return Err(3);
                    }
                    let c = if i.arg == b'n' as usize {
                        b'\n'
                    } else {
                        i.arg as u8
                    };
                    let x = self.character(c)?;
                    self.push(x)?
                }
                5 => {
                    if self.frames.len() == FC + 1 {
                        return Err(2);
                    }
                    self.frames.push((self.stack.len(), i.arg as u8))
                }
                6 => {
                    let mut x = self.close(i.arg as u8)?;
                    if i.arg == 1 {
                        x = self.join(x, true)?;
                        let n = self.number_of(x, true)?;
                        x = self.number(n, false)?
                    }
                    self.push(x)?
                }
                7 => {
                    let x = self.pop()?;
                    self.push(x)?;
                    self.push(x)?
                }
                8 => {
                    self.pop()?;
                }
                9 | 10 | 11 | 12 => {
                    let a = self.pop()?;
                    let b = self.pop()?;
                    let (av, bv) = (self.nodes[a], self.nodes[b]);
                    let x = if i.op == 9 && av.tag == 2 && bv.tag == 2 {
                        let mut bytes = self.text[av.start..av.start + av.len].to_vec();
                        bytes.extend_from_slice(&self.text[bv.start..bv.start + bv.len]);
                        if bytes.len() > OC {
                            return Err(2);
                        }
                        self.bytes(&bytes)?
                    } else {
                        let y = self.number_of(a, false)?;
                        let x = self.number_of(b, false)?;
                        if i.op == 12 && y == 0.0 {
                            return Err(10);
                        }
                        let z = match i.op {
                            9 => x + y,
                            10 => x - y,
                            11 => x * y,
                            _ => x / y,
                        };
                        self.number(z, av.tag == 4 && bv.tag == 4 && i.op != 12)?
                    };
                    self.push(x)?
                }
                13 => {
                    let a = self.pop()?;
                    let x = self.number_of(a, false)?;
                    let b = self.number(-x, self.nodes[a].tag == 4)?;
                    self.push(b)?
                }
                14 => {
                    let x = self.pop()?;
                    self.print(x)?
                }
                15 => {
                    let x = self.pop()?;
                    let v = self.nodes[x];
                    if v.tag != 3 {
                        return Err(4);
                    }
                    let ids = self.edges[v.start..v.start + v.len].to_vec();
                    for x in ids {
                        self.push(x)?
                    }
                }
                16 => {
                    let key = self.pop()?;
                    let obj = self.pop()?;
                    let k = self.number_of(key, true).map_err(|_| 5)?;
                    if k.abs() > 2147483647.0 {
                        return Err(5);
                    }
                    let k = k.trunc() as i64;
                    let v = self.nodes[obj];
                    if v.tag != 2 && v.tag != 3 {
                        return Err(5);
                    }
                    let x = if k < 0 || k as usize >= v.len {
                        0
                    } else if v.tag == 3 {
                        self.edges[v.start + k as usize]
                    } else if v.tag == 2 {
                        let c = self.text[v.start + k as usize];
                        self.character(c)?
                    } else {
                        return Err(5);
                    };
                    self.push(x)?
                }
                17 => self.at(next)?,
                18 => {
                    let x = self.read()?;
                    self.push(x)?
                }
                19 | 20 => {
                    let a = self.pop()?;
                    let b = self.pop()?;
                    let x = self.number_of(a, true).map_err(|_| 7)?;
                    let y = self.number_of(b, true).map_err(|_| 7)?;
                    let mut take = true;
                    if i.op == 20 {
                        let a = self.pop()?;
                        let b = self.pop()?;
                        let mut work=WORK;
                        take = self.equal(a, b, &mut work,0)?
                    }
                    if take {
                        next = coordinate(y, x)?
                    }
                }
                22 => return Err(6),
                26 => {
                    let x = self.number(i.value, false)?;
                    self.push(x)?
                }
                23 => {
                    let x = self.ref_id(i.arg)?;
                    self.push(x)?
                }
                24 | 25 => {
                    let x = self.literal(i.arg, i.op == 25)?;
                    self.push(x)?
                }
                _ => return Err(7),
            }
            self.flush_pending()?;
            if self.halted {
                break;
            }
            if let Some(pc) = self.jump.take() {
                next = pc
            }
            self.pc = next;
        }
        if self.frames.len() != 1 {
            return Err(3);
        }
        Ok(())
    }
}
fn append(out: &mut Vec<u8>, bytes: &[u8]) -> Res<()> {
    if out.len() + bytes.len() > OC {
        return Err(2);
    }
    out.extend_from_slice(bytes);
    Ok(())
}
fn coordinate(y: f64, x: f64) -> Res<usize> {
    if y < 1.0
        || y > LINES.len() as f64
        || x < 0.0
        || x > SOURCE_CAP as f64
        || x != x.trunc()
        || y != y.trunc()
    {
        return Err(7);
    }
    let (start, len) = LINES[y as usize - 1];
    Ok(start + (x as usize).min(len))
}
fn decimal(b: &[u8]) -> Option<f64> {
    let s = std::str::from_utf8(b).ok()?.trim_matches(' ');
    let c = s.as_bytes();
    let mut i = 0;
    if c.get(i) == Some(&b'+') || c.get(i) == Some(&b'-') {
        i += 1
    }
    let mut n = 0;
    while c.get(i).is_some_and(u8::is_ascii_digit) {
        i += 1;
        n += 1
    }
    if c.get(i) == Some(&b'.') {
        i += 1;
        while c.get(i).is_some_and(u8::is_ascii_digit) {
            i += 1;
            n += 1
        }
    }
    if n == 0 {
        return None;
    }
    if c.get(i) == Some(&b'e') || c.get(i) == Some(&b'E') {
        i += 1;
        if c.get(i) == Some(&b'+') || c.get(i) == Some(&b'-') {
            i += 1
        }
        let start = i;
        while c.get(i).is_some_and(u8::is_ascii_digit) {
            i += 1
        }
        if i == start {
            return None;
        }
    }
    if i != c.len() {
        return None;
    }
    let x = s.parse::<f64>().ok()?;
    x.is_finite().then_some(x)
}
fn number_text(x: f64) -> String {
    if x == 0.0 {
        return "0".into();
    }
    if x.abs() >= 1e-12 && x.abs() < 1e15 {
        return format!("{x:.15}")
            .trim_end_matches('0')
            .trim_end_matches('.')
            .to_owned();
    }
    let s = format!("{x:.15e}");
    let (m, e) = s.split_once('e').unwrap();
    let e = e.parse::<i32>().unwrap();
    format!("{m}E{}{:03}", if e < 0 { '-' } else { '+' }, e.abs())
}
fn json_string(b: &[u8]) -> String {
    let mut s = String::from("\"");
    for c in String::from_utf8_lossy(b).chars() {
        match c {
            '"' => s.push_str("\\\""),
            '\\' => s.push_str("\\\\"),
            c if c < ' ' => s.push_str(&format!("\\u{:04x}", c as u32)),
            c => s.push(c),
        }
    }
    s.push('"');
    s
}
fn hex_bytes(b:&[u8])->String{b.iter().map(|x|format!("{x:02x}")).collect()}
fn report(e: &Engine, status: i32) -> String {
    let i = &CODE[e.pc.min(CODE.len() - 1)];
    format!("{{\"status\":{status},\"output\":{},\"output_hex\":\"{}\",\"steps\":{},\"line\":{},\"column\":{},\"collections\":{},\"stack_depth\":{}}}",json_string(&e.output),hex_bytes(&e.output),e.steps,i.line,i.col,e.collections,e.stack.len())
}
#[cfg(not(target_arch = "wasm32"))]
fn main() {
    use std::io::{Read, Write};
    let args: Vec<_> = std::env::args().skip(1).collect();
    let mut fuel = 1_000_000;
    let mut repeat = 1;
    let mut json = false;
    let mut stream=false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--json" => json = true,
            "--stream" => stream = true,
            "--fuel" => {
                i += 1;
                fuel = args
                    .get(i)
                    .and_then(|s| s.parse::<u32>().ok())
                    .filter(|n| *n > 0 && *n <= 2147483647)
                    .unwrap_or_else(|| {
                        eprintln!("bad fuel");
                        std::process::exit(2)
                    })
            }
            "--repeat" => {
                i += 1;
                repeat = args
                    .get(i)
                    .and_then(|s| s.parse::<usize>().ok())
                    .filter(|n| *n > 0 && *n <= 10000)
                    .unwrap_or(0);
                if repeat == 0 {
                    std::process::exit(2)
                }
            }
            _ => {
                eprintln!("unknown option");
                std::process::exit(2)
            }
        }
        i += 1
    }
    if stream&&(json||repeat>1){std::process::exit(2)}
    let mut input = Vec::new();
    if USES_INPUT && repeat>1 {
        if std::io::stdin()
            .take(INPUT_CAP as u64 + 1)
            .read_to_end(&mut input)
            .is_err()
        {
            eprintln!("input read failure");
            std::process::exit(2)
        }
    }
    if input.len() > INPUT_CAP {
        eprintln!("input limit");
        std::process::exit(2)
    }
    let mut last = Engine::new(input.clone());
    let mut status = 0;
    for _ in 0..repeat {
        last = Engine::new(input.clone());
        last.stream_input=repeat==1;last.stream_output=stream;
        status = last.run(fuel)
    }
    if json {
        println!("{}", report(&last, status))
    } else {
        if !stream{std::io::stdout().write_all(&last.output).unwrap();}
        if status != 0 {
            let i = &CODE[last.pc.min(CODE.len() - 1)];
            eprintln!("Foundation P{status:03} at {}:{}", i.line, i.col)
        }
    }
    if status != 0 {
        std::process::exit(1)
    }
}
#[cfg(target_arch = "wasm32")]
struct WasmState {
    input: Vec<u8>,
    output: Vec<u8>,
    status: i32,
    steps: u32,
    line: u32,
    column: u32,
    collections: u32,
    stack_depth: u32,
}
#[cfg(target_arch = "wasm32")]
thread_local! {static STATE:RefCell<WasmState>=RefCell::new(WasmState{input:vec![0;INPUT_CAP],output:Vec::new(),status:0,steps:0,line:1,column:1,collections:0,stack_depth:0});}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_input_ptr() -> *mut u8 {
    STATE.with(|s| s.borrow_mut().input.as_mut_ptr())
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_input_capacity() -> u32 {
    INPUT_CAP as u32
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_run(len: u32, fuel: u32) -> i32 {
    STATE.with(|s| {
        let mut s = s.borrow_mut();
        s.output.clear();
        s.steps = 0;
        s.line = CODE[ENTRY].line as u32;
        s.column = CODE[ENTRY].col as u32;
        s.stack_depth = 0;
        s.collections = 0;
        if len as usize > INPUT_CAP {
            s.status = 9;
            return 9;
        }
        if fuel > 2147483647 {
            s.status = 8;
            return 8;
        }
        let mut e = Engine::new(s.input[..len as usize].to_vec());
        let status = e.run(fuel);
        let i = &CODE[e.pc.min(CODE.len() - 1)];
        s.output = e.output;
        s.status = status;
        s.steps = e.steps;
        s.line = i.line as u32;
        s.column = i.col as u32;
        s.collections = e.collections;
        s.stack_depth = e.stack.len() as u32;
        status
    })
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_output_ptr() -> *const u8 {
    STATE.with(|s| s.borrow().output.as_ptr())
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_output_len() -> u32 {
    STATE.with(|s| s.borrow().output.len() as u32)
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_steps() -> u32 {
    STATE.with(|s| s.borrow().steps)
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_error_line() -> u32 {
    STATE.with(|s| s.borrow().line)
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_error_column() -> u32 {
    STATE.with(|s| s.borrow().column)
}
#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_collections() -> u32 {
    STATE.with(|s| s.borrow().collections)
}

#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_stack_depth() -> u32 {
    STATE.with(|s| s.borrow().stack_depth)
}

#[cfg(target_arch = "wasm32")]
#[no_mangle]
pub extern "C" fn urotif_uses_input() -> u32 {
    USES_INPUT as u32
}
