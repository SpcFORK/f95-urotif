#!/usr/bin/env python3
"""0.3 resource, source-extension and recoverable-transpilation acceptance tests."""
from pathlib import Path
import json, subprocess, unittest, hashlib, os, selectors, time
import test_foundation as support
from test_foundation import ROOT, BIN, HEADER, call, require

class Roundtrip(unittest.TestCase):
    setUpClass=classmethod(support.Foundation.setUpClass.__func__)
    tearDownClass=classmethod(support.Foundation.tearDownClass.__func__)
    source=support.Foundation.source
    native=support.Foundation.native
    build=support.Foundation.build
    compiled=support.Foundation.compiled
    parity=support.Foundation.parity

    def assemble(self,text):
        p=self.source(text);out=p.with_suffix('.assembled.utf')
        require([BIN,'assemble',p,'-o',out]);return out

    def test_14_new_samples_all_targets(self):
        for case in json.loads((ROOT/'examples/next/cases.json').read_text()):
            with self.subTest(sample=case['name']):
                p=ROOT/case['program'];out=self.work/(case['name']+'.utf')
                require([BIN,'assemble',ROOT/case['source'],'-o',out])
                self.assertEqual(out.read_bytes(),p.read_bytes())
                v=self.parity(p,case['input'])
                self.assertEqual((v['status'],v['output'],v['output_hex']),(0,case['output'],case['output_hex']))

    def test_recover_and_retranspile_every_target(self):
        p=ROOT/'examples/next/cube-library.utf';original=p.read_bytes()
        for target,ext in [('fortran','f90'),('c','c'),('rust','rs'),('wasm','wasm')]:
            with self.subTest(target=target):
                artifact=self.work/f'capsule.{ext}';recovered=self.work/f'{target}-recovered.utf'
                require([BIN,target,p,'--foundation','--embed-source','-o',artifact])
                require([BIN,'recover',artifact,'-o',recovered])
                self.assertEqual(recovered.read_bytes(),original)
                # This closes the behavioral loop, not just a text comparison.
                v=self.parity(recovered,variants=(('fortran',True),('c',True),('rust',True),('wasm',True)))
                self.assertEqual((v['status'],v['output']),(0,'27\n'))
                metadata=json.loads(Path(str(artifact)+'.links.json').read_text())
                self.assertEqual(metadata['limits']['stack'],2048)

    def test_capsule_corruption_and_missing_metadata_do_not_overwrite(self):
        p=ROOT/'examples/next/cube-library.utf';artifact=self.work/'capsule-bad.f90';out=self.work/'protected.utf'
        require([BIN,'fortran',p,'--foundation','--embed-source','-o',artifact])
        data=artifact.read_text();a=data.index('UROTIF-HEX ')+len('UROTIF-HEX ')
        artifact.write_text(data[:a]+('0' if data[a]!='0' else '1')+data[a+1:])
        out.write_bytes(b'KEEP\n')
        r=call([BIN,'recover',artifact,'-o',out]);self.assertNotEqual(r.returncode,0);self.assertIn('checksum',r.stderr)
        self.assertEqual(out.read_bytes(),b'KEEP\n')
        require([BIN,'fortran',p,'--foundation','-o',artifact])
        r=call([BIN,'recover',artifact,'-o',out]);self.assertNotEqual(r.returncode,0);self.assertIn('no source capsule',r.stderr)
        self.assertEqual(out.read_bytes(),b'KEEP\n')

    def test_strict_f95_is_standalone_without_rust(self):
        p=ROOT/'examples/next/nested-calls.utf';src=self.work/'strict.f90';exe=self.work/'strict-fortran'
        require([BIN,'fortran',p,'--foundation','--f95','-o',src])
        text=src.read_text()
        self.assertNotIn('run_prototype_source',text);self.assertNotIn('module urotif_lexer',text)
        self.assertNotIn("include '",text)
        require(['gfortran','-std=f95','-pedantic-errors','-O2','-fcheck=all','-J'+str(self.work),src,'-o',exe])
        self.assertEqual(require([exe]).stdout,'729\n')
        r=call([BIN,'fortran',p,'--foundation','--f95','--extern','demo.cube/1','-o',self.work/'no-foreign.f90'])
        self.assertNotEqual(r.returncode,0);self.assertIn('F2003',r.stderr)
        self.assertFalse((self.work/'no-foreign.f90').exists())

    def test_stack_shuffles_and_packing_failures(self):
        cases=[('x@',1),('1x@',1),('12t@',1),('1[2x@',1),('{1}{2}b@',1),('a{0.5}b@',4),('a1b@',4),('a{1}~b@',4)]
        for body,status in cases:
            with self.subTest(body=body):self.assertEqual(self.parity(self.source(HEADER+body+'\n'))['status'],status)
        p=self.source(HEADER+'{0}b@$12o@{3}b@$d@$h@\n')
        self.assertEqual(self.parity(p)['output'],"[]['1', '2', '1']0")

    def test_hex_all_bytes_and_utf8_diagnostics(self):
        p=self.source(HEADER+'['+''.join('\\x%02x'%n for n in range(256))+']S@$h@\n')
        v=self.parity(p);self.assertEqual(v['output_hex'],bytes(range(256)).hex())
        self.assertEqual(v['output'],bytes(range(256)).decode('utf8','replace'))
        for body in ['\\x','\\x0','\\xGG','[\\x0G]S@']:
            with self.subTest(body=body):self.assertEqual(self.parity(self.source(HEADER+body+'\n'))['status'],3)
        for raw in [b'\xe2\x82',b'\xe0\x80\x80',b'\xed\xa0\x80',b'\xf0\x90\x80',b'\xf4\x90\x80\x80',b'\xf0\x9f\x98\x80']:
            p=self.source(HEADER+'['+''.join('\\x%02x'%n for n in raw)+']S@$h@\n')
            self.assertEqual(self.parity(p)['output'],raw.decode('utf8','replace'))

    def test_hex_fuel_and_arbitrary_interior_entry(self):
        p=self.source(HEADER+'[A\\x6e\\x00]S@$h@\n')
        for fuel in range(1,12):self.parity(p,fuel=fuel)
        p=self.source(HEADER+'{3}{1}^\n\\x41$h@\n')
        self.assertEqual(self.parity(p)['output'],'1')

    def test_stack_budget_above_old_2048(self):
        p=self.source(HEADER+'0'*5000+'d@$h@\n')
        self.assertEqual(self.native(p)['status'],2)
        v=self.parity(p,links=['--limit','stack=8192'])
        self.assertEqual((v['status'],v['output'],v['stack_depth']),(0,'5000',5000))

    def test_input_line_above_old_2048(self):
        p=ROOT/'examples/next/record-length.utf'
        self.assertEqual(self.native(p,'a'*5000+'\n')['status'],9)
        v=self.parity(p,'a'*5000+'\n',links=['--limit','input-line=8192'])
        self.assertEqual((v['status'],v['output']),(0,'5000\n'))

    def test_output_above_old_262144(self):
        p=self.source(HEADER+'{3000}\n%{0}{4}{0}=['+'x'*100+']S@${1}-{3}{0}^\n_h@\n')
        self.assertEqual(self.native(p)['status'],2)
        v=self.parity(p,links=['--limit','output=400000'])
        self.assertEqual((v['status'],len(v['output'])),(0,300000))
        self.assertEqual(v['output'],'x'*300000)

    def test_return_stack_above_old_1024(self):
        p=self.assemble('.number 1500\n.call down\n.println\n.halt\n.label down\n.dup\n.number 0\n.eq base\n.number 1\n-\n.call down\n.return\n.label base\n.return\n')
        self.assertEqual(self.native(p)['status'],13)
        v=self.parity(p,links=['--limit','returns=4096'])
        self.assertEqual((v['status'],v['output']),(0,'0\n'))

    def test_construction_and_traversal_budgets(self):
        p=self.source(HEADER+'['*100+'{1}'+']'*100+'$h@\n')
        self.assertEqual(self.native(p)['status'],2)
        v=self.parity(p,links=['--limit','frames=128'])
        self.assertEqual(v['output'],'['*100+'1'+']'*100)
        array='['+'{1}'*100+']'
        p=self.source(HEADER+array+array+'{3}{0}=F$h@\nT$h@\n')
        self.assertEqual(self.parity(p,links=['--limit','work=10'])['status'],2)
        self.assertEqual(self.parity(p,links=['--limit','work=1024'])['output'],'T')

    def test_growing_live_arenas(self):
        p=self.source(HEADER+'[]{33000}\n%{0}{4}{0}=x@{1}b@x@{1}-{3}{0}^\n_h@\n')
        self.assertEqual(self.native(p,fuel=3000000)['status'],2)
        # Diagnostic JSON is bounded for this 33,000-deep final array. Execution
        # succeeds without recursively printing it or claiming an unlimited VM.
        links=['--limit','nodes=100000','--limit','edges=100000']
        v=self.parity(p,fuel=3000000,links=links,variants=(('c',True),('rust',True),('fortran',True),('wasm',True)))
        self.assertEqual((v['status'],v['stack_depth']),(0,1));self.assertTrue(v['stack_truncated'])

    def test_input_buffer_above_old_one_megabyte(self):
        p=self.source(HEADER+'{1100}\n%{0}{4}{0}=`_{1}-{3}{0}^\n_[done]S@$h@\n')
        data=('x'*1000+'\n')*1100
        self.assertEqual(self.native(p,data)['status'],9)
        v=self.parity(p,data,links=['--limit','input=2097152'],variants=(('c',True),('rust',True),('fortran',True),('wasm',True)))
        self.assertEqual((v['status'],v['output']),(0,'done'))

    def test_ir_above_old_65535_and_labels_above_1024(self):
        p=self.source(HEADER+'!'*70000+'[large]P@h@\n')
        v=self.parity(p,variants=(('c',True),('rust',True),('fortran',True),('wasm',True)))
        self.assertEqual((v['status'],v['output']),(0,'large\n'))
        p=self.assemble('.goto last\n'+''.join('.label label%d\n'%i for i in range(1500))+'.label last\n.text resolved\n.println\n.halt\n')
        self.assertEqual(self.parity(p)['output'],'resolved\n')

    def test_source_allocation_not_process_stack_sized(self):
        p=ROOT/'examples/next/cube-library.utf'
        require([BIN,'check',p,'--foundation','--limit','source=8388608'])
        v=self.native(p,links=['--limit','source=8388608']);self.assertEqual(v['output'],'27\n')

    def test_invalid_limit_values_and_no_partial_emission(self):
        p=ROOT/'examples/next/cube-library.utf'
        for bad in ['stack=0','unknown=5','source=9999999999','frames=1.5','stack=NaN','stack','work=-1']:
            out=self.work/'bad-limit.f90';out.unlink(missing_ok=True)
            r=call([BIN,'fortran',p,'--foundation','--limit',bad,'-o',out])
            self.assertNotEqual(r.returncode,0,bad);self.assertFalse(out.exists())
        small=self.work/'small-source.f90'
        r=call([BIN,'fortran',self.source(HEADER+'!'*100+'\n'),'--foundation','--limit','source=64','-o',small])
        self.assertNotEqual(r.returncode,0);self.assertFalse(small.exists())

    def test_macro_include_errors_and_primitive_extension(self):
        p=self.assemble('.define fourth %*%*\n.number 3\n.use fourth\n.println\n.halt\n')
        self.assertEqual(self.parity(p)['output'],'81\n')
        for text in ['.use missing\n','.define x %\n.define x *\n','.include missing-library.ufm\n','.define bad .goto foo\n','.bytes 0\n','.bytes gg\n','.number NaN\n','.pack -1\n']:
            src=self.source(text);out=src.with_suffix('.no-output.utf')
            r=call([BIN,'assemble',src,'-o',out]);self.assertNotEqual(r.returncode,0,text);self.assertFalse(out.exists())
        src=self.work/'recursive.ufm';src.write_text('.include recursive.ufm\n')
        r=call([BIN,'assemble',src,'-o',self.work/'cycle.utf']);self.assertNotEqual(r.returncode,0);self.assertIn('recursive include',r.stderr)

    def test_native_streaming_prompt_and_no_eof_requirement(self):
        source=ROOT/'examples/next/prompt-square.utf'
        commands=[[str(BIN),'run',str(source),'--foundation','--stream']]
        for target in ['c','rust','fortran']:
            commands.append([str(x) for x in self.build(source,target) if x!='--json']+['--stream'])
        for command in commands:
            with self.subTest(command=command):
                p=subprocess.Popen(command,cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                try:
                    selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
                    prompt=b'';deadline=time.monotonic()+5
                    while len(prompt)<8:
                        self.assertTrue(selector.select(max(0,deadline-time.monotonic())),'prompt blocked waiting for input/EOF')
                        part=os.read(p.stdout.fileno(),8-len(prompt));self.assertTrue(part);prompt+=part
                    selector.close();self.assertEqual(prompt,b'Number: ')
                    p.stdin.write(b'9\n');p.stdin.flush()
                    p.wait(timeout=5)  # stdin intentionally remains OPEN.
                    self.assertEqual(p.returncode,0,p.stderr.read().decode())
                    self.assertEqual(p.stdout.read(),b'81\n')
                finally:
                    if p.poll() is None:p.kill();p.wait()
                    p.stdin.close();p.stdout.close();p.stderr.close()

    def test_repeat_replays_input_but_is_not_live_streaming(self):
        p=ROOT/'examples/next/prompt-square.utf'
        for target in ['c','rust','fortran','wasm']:
            cmd=self.build(p,target)
            self.assertEqual(self.compiled(cmd,'9\n'),self.compiled(cmd,'9\n',repeat=3))
        for target in ['c','rust','fortran']:
            r=call([*self.build(p,target),'--stream'],'9\n');self.assertNotEqual(r.returncode,0)

if __name__=='__main__':unittest.main(verbosity=2)
