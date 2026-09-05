#!/usr/bin/env python3
"""Instrument the generated C runtime AND C plugins, using the typed test oracle.
Rust's sample static library is linked but is not ASan-instrumented here.
Only C is exercised by this harness; it makes no Rust/Fortran sanitizer claim.
"""
from pathlib import Path
import hashlib, json, os, sys, unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
import test_typed as typed
os.environ['ASAN_OPTIONS']='detect_leaks=1:halt_on_error=1'
os.environ['UBSAN_OPTIONS']='halt_on_error=1:print_stacktrace=1'
FLAGS=['-fsanitize=address,undefined','-fno-omit-frame-pointer','-fno-pie','-g','-O1']
class SanitizedC(typed.Typed):
    executions=0
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        originals=cls.objects;cls.objects=[]
        for name,source in [('buffers','plugins/buffers.c'),('audit','tests/fixtures/typed_contract.c'),('demo','plugins/demo.c')]:
            obj=cls.work/(name+'-san.o')
            typed.require(['gcc','-std=c99',*FLAGS,'-DUROTIF_STATIC_LINK','-c',ROOT/source,'-o',obj])
            cls.objects.append(obj)
        cls.objects.append(originals[-1]) # Rust unicode staticlib, not instrumented.
    def build(self,p,target,opt=True,flags=(),links=None):
        # The parent's GC check iterates this module's variants, set below.
        if target!='c':raise AssertionError('sanitizer harness is C-only')
        key=(str(p),opt,tuple(flags));links=self.links if links is None else links
        if key in self.cache:return self.cache[key]
        name=hashlib.sha256(repr(key).encode()).hexdigest()[:20];src=self.work/(name+'.c');exe=self.work/(name+'-san')
        typed.require([typed.BIN,'c',p,'--foundation',*flags,*links,*([] if opt else ['--no-opt']),'-o',src])
        typed.require(['gcc','-std=c99',*FLAGS,'-no-pie',src,*self.objects,'-ldl','-lpthread','-lm','-lrt','-lutil','-o',exe])
        self.cache[key]=([exe,'--json'],src);return self.cache[key]
    def parity(self,p,stdin='',flags=(),variants=None,links=None):
        return super().parity(p,stdin,flags,typed.VARIANTS,links)
    def compiled(self,cmd,stdin='',fuel=1000000,repeat=1):
        r=typed.command([*cmd,'--fuel',fuel,'--repeat',repeat],stdin)
        self.assertNotIn('Sanitizer',r.stderr,r.stderr);self.assertNotIn('runtime error:',r.stderr,r.stderr)
        self.assertIn(r.returncode,(0,1),(r.stdout,r.stderr));self.assertTrue(r.stdout,r.stderr)
        type(self).executions+=1;return json.loads(r.stdout)

typed.VARIANTS=[('c',True),('c',False)]
names=['test_value_flow_all_targets','test_failure_matrix_all_targets','test_output_channel_boundaries',
       'test_aggregate_input_limits_count_aliases','test_gc_preserves_typed_results']
result=unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(SanitizedC(name) for name in names))
print(json.dumps({'instrumentation':'C runtime + C plugins: ASan/UBSan; Rust sample library uninstrumented',
    'executions':SanitizedC.executions,'suites':len(names),'passed':result.wasSuccessful()}),flush=True)
sys.exit(0 if result.wasSuccessful() else 1)
