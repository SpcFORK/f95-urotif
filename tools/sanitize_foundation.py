#!/usr/bin/env python3
"""Linux/GCC AddressSanitizer + UndefinedBehaviorSanitizer target smoke test.
Checks emitted C with and without fast paths; not a proof of memory safety.
"""
from pathlib import Path
import json, os, random, subprocess
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/sanitizer';WORK.mkdir(parents=True,exist_ok=True)
rng=random.Random(20260904)
rows=[''.join(rng.choice('01ab[]{}%_$+*-~|@\\;:!#`') for _ in range(rng.randint(1,40)))+'h@' for _ in range(100)]
source=WORK/'malformed.utf';source.write_text('=) urotif\n[[int]S@`]C@0^\n'+'\n'.join(rows)+'\n')
gc=WORK/'gc.utf';gc.write_text('=) urotif\n[[payload]S@]{10000}\n%{0}{4}{0}={1}-{3}{0}^\n_s@$h@\n')
env=dict(os.environ,ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
checked=0
for p in [source,gc]:
    for opt in [False,True]:
        c=WORK/(p.stem+str(opt)+'.c');exe=c.with_suffix('.bin')
        subprocess.run([str(ROOT/'bin/urotif'),'c',str(p),'--foundation','-o',str(c),*([] if opt else ['--no-opt'])],cwd=ROOT,check=True)
        subprocess.run(['gcc','-std=c99','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-fno-pie','-no-pie',str(c),'-lm','-o',str(exe)],cwd=ROOT,check=True)
        inputs=[str(i+3)+'\n' for i in range(100)] if p==source else ['']
        for stdin in inputs:
            r=subprocess.run([str(exe),'--json','--fuel','1000000' if p==gc else '200'],input=stdin,text=True,capture_output=True,env=env,timeout=10)
            if r.returncode not in [0,1] or r.stderr:raise RuntimeError(f'{p} opt={opt} input={stdin!r}\n{r.stdout}\n{r.stderr}')
            v=json.loads(r.stdout)
            if p==gc and (v['status']!=0 or v['output']!="['payload']" or v['collections']==0):raise AssertionError(v)
            checked+=1
result={'instrumentation':['AddressSanitizer','UndefinedBehaviorSanitizer'],'runs':checked,'malformed_entries_per_variant':100,'variants':['constant fast paths off','constant fast paths on'],'gc_workload_iterations':10000,'result':'no sanitizer diagnostics in this smoke test'}
(ROOT/'artifacts').mkdir(parents=True,exist_ok=True)
(ROOT/'artifacts/foundation-sanitizers.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
