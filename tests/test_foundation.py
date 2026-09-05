#!/usr/bin/env python3
"""Five-way Foundation differential tests, including real emitted WASM.
Needs make all, gcc, rustc + wasm32-unknown-unknown, and Node. No network.
The original reference suite remains separate and must also pass.
"""
from pathlib import Path
import hashlib, json, random, subprocess, tempfile, unittest
ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT/'bin/urotif'
HEADER='=) urotif\n'

def call(args,stdin='',timeout=30):
    return subprocess.run(list(map(str,args)),cwd=ROOT,input=stdin,text=True,capture_output=True,timeout=timeout)

def require(args,timeout=90):
    r=call(args,timeout=timeout)
    if r.returncode: raise AssertionError(f'{args}\n{r.stdout}\n{r.stderr}')
    return r

class Foundation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='urotif-foundation-')
        cls.work=Path(cls.temp.name);cls.cache={}
        cls.plugin=cls.work/'demo.so';cls.obj=cls.work/'demo.o';cls.rust_plugin=cls.work/'rust-demo.so'
        require(['gcc','-std=c99','-O3','-shared','-fPIC','plugins/demo.c','-o',cls.plugin])
        require(['gcc','-std=c99','-O3','-DUROTIF_STATIC_LINK','-c','plugins/demo.c','-o',cls.obj])
        require(['rustc','--edition=2021','-O','--crate-type=cdylib','plugins/rust_demo.rs','-o',cls.rust_plugin])
    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()
    def source(self,text):
        digest=hashlib.sha256(text.encode()).hexdigest()[:20]
        p=self.work/(digest+'.utf');p.write_text(text);return p
    def native(self,p,stdin='',fuel=1000000,links=()):
        r=call([BIN,'probe',p,'--foundation','--fuel',fuel,*links],stdin)
        self.assertIn(r.returncode,(0,1),(r.stdout,r.stderr))
        # Reject duplicate JSON keys as well as malformed output.
        def obj(pairs):
            d={}
            for k,v in pairs:
                self.assertNotIn(k,d);d[k]=v
            return d
        v=json.loads(r.stdout,object_pairs_hook=obj)
        self.assertEqual(v['ok'],r.returncode==0)
        v['status']=0 if v['ok'] else int(v['error'][1:4]);v.setdefault('stack_depth',len(v['stack']))
        return v
    def build(self,p,target='c',opt=True,links=()):
        key=(str(p),target,opt,tuple(map(str,links)))
        if key in self.cache:return self.cache[key]
        tag=hashlib.sha256(repr(key).encode()).hexdigest()[:20]
        ext={'c':'c','rust':'rs','wasm':'wasm','fortran':'f90'}[target]
        src=self.work/(tag+'.'+ext)
        require([BIN,target,p,'--foundation','-o',src,*([] if opt else ['--no-opt']),*links])
        if target=='c':
            exe=src.with_suffix('.c-bin')
            require(['gcc','-std=c99','-O3',src,*([self.obj] if links else []),'-lm','-o',exe])
            cmd=[exe,'--json']
        elif target=='fortran':
            exe=src.with_suffix('.f-bin')
            require(['gfortran','-std=f2003','-pedantic-errors','-O2','-fcheck=all','-J'+str(self.work),src,*([self.obj] if links else []),'-o',exe])
            cmd=[exe,'--json']
        elif target=='rust':
            exe=src.with_suffix('.rs-bin')
            require(['rustc','--edition=2021','--crate-name','foundation_test','-O','-A','dead_code','-A','unused_imports',src,*(['-C',f'link-arg={self.obj}'] if links else []),'-o',exe])
            cmd=[exe,'--json']
        else:cmd=['node','tools/foundation-wasm.mjs',src,'--json',*(['--host','plugins/demo-host.mjs'] if links else [])]
        self.cache[key]=cmd;return cmd
    def compiled(self,cmd,stdin='',fuel=1000000,repeat=1):
        r=call([*cmd,'--fuel',fuel,'--repeat',repeat],stdin)
        self.assertIn(r.returncode,(0,1),(r.stdout,r.stderr));v=json.loads(r.stdout)
        self.assertEqual(v['status']==0,r.returncode==0);return v
    def parity(self,p,stdin='',fuel=1000000,variants=(('c',True),('c',False),('rust',True),('wasm',True),('fortran',True),('fortran',False)),links=()):
        native=self.native(p,stdin,fuel,links)
        for target,opt in variants:
            with self.subTest(target=target,opt=opt):
                v=self.compiled(self.build(p,target,opt,links),stdin,fuel)
                for k in ['status','output','output_hex','steps','stack_depth']:
                    self.assertEqual(v[k],native[k],(k,native,v,p.read_text()))
                if native['status']:
                    self.assertEqual((v['line'],v['column']),(native['line'],native['column']),(native,v,p.read_text()))
        return native

    def test_reference_hello_and_text_addition(self):
        for name,stdin,output in [('hello.utf','','Hello, World!\n'),('anb.utf','2\n3\n','32')]:
            r=self.parity(ROOT/'reference/smp'/name,stdin);self.assertEqual(r['output'],output);self.assertEqual(r['status'],0)
    def test_conversion_import_external_subroutine(self):
        for name,stdin,output in [('convert','42\n','42'),('import-apply','17\n','17'),('external','','81'),('subroutine','','81')]:
            with self.subTest(name=name):
                r=self.parity(ROOT/f'examples/foundation/{name}.utf',stdin);self.assertEqual((r['status'],r['output']),(0,output))
    def test_truth_intent_zero_and_nonzero(self):
        p=ROOT/'examples/foundation/truth.utf'
        for stdin,prefix in [('7\n2\n0\nBAD\n','72'),('0\nBAD\n','')]:
            with self.subTest(stdin=stdin):
                r=self.parity(p,stdin,200);self.assertEqual(r['status'],8)
                self.assertTrue(r['output'].startswith(prefix));self.assertEqual(set(r['output'][len(prefix):]),{'0'})
                self.assertEqual(r['stack'],[0])
        r=self.parity(p,'7\n2\n',200);self.assertEqual((r['status'],r['output']),(9,'72'))
    def test_standard_conversions_and_collections(self):
        cases=[
            ('[[float]S@`]C@[std.string]r@@$h@','3.125\n','3.125'),
            ('[[len]S@[abcd]]C@$h@','','4'),
            ('[abc]S@[de]S@+$h@','','deabc'),
            ('{9}{4}-$\\n${3}~$\\n${9}{4}|$h@','','5\n-3\n2.25'),
            ('[a{2}[bc]]$h@',"","['a', 2, ['b', 'c']]"),
            ('[math.square]r@s@$[[math]i@[square]S@]g@s@$h@','','<external:5><external:5>'),
            ('[abcd]{1};$[x]{9};$h@','','b?'),
            ('{1}{65536}|$h@','','0.000015258789062'),
            ('{1e20}$h@','','1.000000000000000E+020'),
        ]
        for source,stdin,output in cases:
            with self.subTest(source=source):
                r=self.parity(self.source(HEADER+source+'\n'),stdin);self.assertEqual((r['status'],r['output']),(0,output))
    def test_equality_is_consuming_and_typed(self):
        for first,want in [('0{0}','F'),('{0}[[int]S@0]C@','T'),('[math.square]r@[math.square]r@','T')]:
            p=self.source(HEADER+first+'30=F$h@\nT$h@\n')
            r=self.parity(p);self.assertEqual((r['status'],r['output'],r['stack']),(0,want,[]))
    def test_arbitrary_entries_survive_fusion(self):
        cases=[('[31^\n[ab]P@h@\n',0,'ab\n'),('31^\n\\n$h@\n',0,'n'),('33^\n[ab]P@h@\n',3,''),('[ab\ncd]P@h@\n',0,'abcd\n')]
        for body,status,out in cases:
            with self.subTest(body=body):
                r=self.parity(self.source(HEADER+body));self.assertEqual((r['status'],r['output']),(status,out))
    def test_fuel_each_interior_boundary(self):
        p=self.source(HEADER+'[Hello, World\\!]P@{9}[math.square]r@@$h@\n')
        for fuel in range(1,47):
            with self.subTest(fuel=fuel):self.parity(p,fuel=fuel)
    def test_comments_reset_column_only_in_foundation(self):
        p=self.source(HEADER+'abc#ignore\nXYZs@$h@\n');r=self.parity(p)
        self.assertEqual((r['status'],r['output'],r['stack']),(0,'Z',list('abcXY')))
    def test_checked_failure_matrix(self):
        cases=[
            ('$',1,''),(']',3,''),('[}',3,''),('\\',3,''),('a{1}+',4,''),
            ('{1}{0}|',10,''),('{2}0;',5,''),('{1}@',6,''),
            ('[fs.read]r@',11,''),('[std.len]r@@',1,''),
            ('[[int]S@]C@',12,''),('[[int]S@`]C@',12,'nan\n'),
            ('{2}[std.len]r@@',12,''),('{1}~[math.sqrt]r@@',12,''),
            ('R@',13,''),('[30]k@h@\n[R@',13,''),('[20]k@',13,''),
            ('`',9,''),('{0}{0}^',7,''),('[[int]S@{9007199254740992}]C@',12,''),
            ('[[int]S@{9007199254740991}]C@[[int]S@1]C@+',10,''),
        ]
        for body,status,stdin in cases:
            with self.subTest(body=body):
                r=self.parity(self.source(HEADER+body+'\n'),stdin,fuel=10000)
                self.assertEqual(r['status'],status)
    def test_input_line_boundary(self):
        p=self.source(HEADER+'[[len]S@`]C@$h@\n')
        for n,status in [(0,0),(2048,0),(2049,9)]:
            r=self.parity(p,'x'*n+'\n');self.assertEqual(r['status'],status)
            if status==0:self.assertEqual(r['output'],str(n))
        self.parity(p,'abc\r\n')
    def test_gc_preserves_nested_roots(self):
        p=self.source(HEADER+'[[payload]S@]{10000}\n%{0}{4}{0}={1}-{3}{0}^\n_s@$h@\n')
        r=self.parity(p);self.assertGreater(r['collections'],0)
        self.assertEqual((r['status'],r['output'],r['stack']),(0,"['payload']",[]))
        for target in ['c','rust','wasm','fortran']:
            v=self.compiled(self.build(p,target));self.assertGreater(v['collections'],0)
    def test_fast_paths_preserve_frame_and_stack_limits(self):
        for body in ['['*64+'{1}'+']'*64,'0'*2047+'[ab]','0'*2047+'[]S@']:
            r=self.parity(self.source(HEADER+body+'\n'));self.assertEqual(r['status'],2)
    def test_repeat_resets_all_state(self):
        p=ROOT/'examples/foundation/subroutine.utf'
        for target in ['c','rust','wasm','fortran']:
            cmd=self.build(p,target);a=self.compiled(cmd);b=self.compiled(cmd,repeat=4)
            self.assertEqual(a,b)
    def test_native_c_and_rust_plugins(self):
        p=self.source(HEADER+'{3}[demo.cube]r@@${21}[rustdemo.twice]r@@$h@\n')
        r=self.native(p,links=['--link',self.plugin,'--link',self.rust_plugin])
        self.assertEqual((r['status'],r['output']),(0,'2742'))
    def test_plugin_argument_order_all_targets(self):
        for body in ['{2}{3}{5}[demo.affine]r@@$h@','[[demo.affine]r@{2}{3}{5}]a@$h@']:
            p=self.source(HEADER+body+'\n');links=['--link',self.plugin]
            r=self.parity(p,links=links);self.assertEqual((r['status'],r['output']),(0,'11'))
    def test_signature_only_wasm_link_and_deny_missing_host(self):
        p=ROOT/'examples/foundation/plugin.utf'
        cmd=self.build(p,'wasm',links=['--extern','demo.cube/1'])
        r=self.compiled(cmd);self.assertEqual((r['status'],r['output']),(0,'27'))
        denied=call(cmd[:-2]);v=json.loads(denied.stdout)
        self.assertEqual(v['status'],-1);self.assertIn('not granted',v['error'])
        r=self.native(p,links=['--extern','demo.cube/1']);self.assertEqual(r['status'],12)
    def test_rejected_declarations_and_duplicate_modules(self):
        for args in [ ['--extern','evil/path.run/1'],['--extern','demo.bad/9'],['--extern','std.overwrite/1'],['--link',self.plugin,'--link',self.plugin],['--extern','demo.x/1','--extern','demo.x/1'],['--link','missing.so'] ]:
            r=call([BIN,'links',*args]);self.assertNotEqual(r.returncode,0)
    def test_bad_plugin_abi_is_rejected(self):
        p=self.work/'bad.c';p.write_text('#include "'+str(ROOT/'include/urotif_plugin.h')+'"\nstatic UrotifPlugin p={99,0,0,0}; const UrotifPlugin*urotif_plugin_v1(void){return &p;}\n')
        so=self.work/'bad.so';require(['gcc','-shared','-fPIC',p,'-o',so]);r=call([BIN,'links','--link',so])
        self.assertNotEqual(r.returncode,0);self.assertIn('invalid plugin ABI',r.stderr)
    def test_symbolic_assembler_roundtrip(self):
        for name,stdin in [('square',''),('truth','7\n2\n0\n')]:
            out=self.work/(name+'-assembled.utf')
            require([BIN,'assemble',ROOT/f'examples/foundation/{name}.ufm','-o',out])
            self.assertEqual(out.read_bytes(),(ROOT/f'examples/foundation/{name}-assembled.utf').read_bytes())
            r=self.parity(out,stdin,fuel=200)
            if name=='square':self.assertEqual((r['status'],r['output']),(0,'81'))
            else:
                self.assertEqual(r['status'],8);self.assertTrue(r['output'].startswith('72'))
                self.assertEqual(set(r['output'][2:]),{'0'})
    def test_assembler_diagnostics_and_no_partial_output(self):
        for text in ['.label x\n.label x\n','.goto nowhere\n','.call bad name\n','.return extra\n','.typo x\n']:
            p=self.source(text);out=self.work/'should-not-be-written.utf'
            r=call([BIN,'assemble',p,'-o',out]);self.assertNotEqual(r.returncode,0)
            self.assertFalse(out.exists())
    def test_wasm_invalid_call_resets_public_output(self):
        cmd=self.build(ROOT/'examples/foundation/external.utf','wasm')
        path=cmd[2]
        js="""import{readFileSync}from'node:fs';const{instance}=await WebAssembly.instantiate(readFileSync(PATH),{});const e=instance.exports;e.urotif_input_ptr();if(e.urotif_run(0,100)!==0||e.urotif_output_len()!==2)throw Error('initial run');if(e.urotif_run(e.urotif_input_capacity()+1,100)!==9||e.urotif_output_len()!==0||e.urotif_steps()!==0)throw Error('stale output after bad input');if(e.urotif_run(0,0xffffffff)!==8||e.urotif_output_len()!==0)throw Error('bad fuel');if(e.urotif_run(0,100)!==0||e.urotif_output_len()!==2)throw Error('reset');""".replace('PATH',json.dumps(str(path)))
        require(['node','--input-type=module','-e',js])

    def test_differential_100_arithmetic_expressions(self):
        rng=random.Random(4815);body=[]
        for _ in range(100):
            a,b=rng.randint(0,100),rng.randint(1,100)
            body.append('{'+str(a)+'}{'+str(b)+'}'+rng.choice(['+','-','*','|'])+'$\\n$')
        p=self.source(HEADER+''.join(body)+'h@\n');r=self.parity(p)
        self.assertEqual(r['status'],0);self.assertEqual(len(r['output'].splitlines()),100)
    def test_differential_100_malformed_entries(self):
        rng=random.Random(20260904)
        rows=[''.join(rng.choice('01ab[]{}%_$+*-~|@\\;:!#`') for _ in range(rng.randint(1,40)))+'h@' for _ in range(100)]
        p=self.source(HEADER+'[[int]S@`]C@0^\n'+'\n'.join(rows)+'\n')
        for i in range(len(rows)):
            with self.subTest(row=i):self.parity(p,str(i+3)+'\n',fuel=200)

if __name__=='__main__':unittest.main(verbosity=2)
