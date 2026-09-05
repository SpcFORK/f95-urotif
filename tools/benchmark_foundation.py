#!/usr/bin/env python3
"""Reproducible local ablation, not a claim of universally fastest execution.
Primary metric: complete CLI latency, including startup, reading/preparation,
runtime initialization, execution, GC, and reporting. Identical Urotif input.
WASM warm execution is reported separately and not mixed into speedup ratios.
"""
from pathlib import Path
import argparse, datetime, json, platform, statistics, subprocess, time
ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT/'bin/urotif';WORK=ROOT/'build/benchmarks';ART=ROOT/'artifacts'

def run(cmd,stdin=''):
    start=time.perf_counter_ns()
    p=subprocess.run(list(map(str,cmd)),cwd=ROOT,input=stdin,text=True,capture_output=True,timeout=180)
    ms=(time.perf_counter_ns()-start)/1e6
    if p.returncode:raise RuntimeError(f'{cmd}\n{p.stdout}\n{p.stderr}')
    return p,ms

def version(cmd):return run(cmd)[0].stdout.splitlines()[0]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--iterations',type=int,default=20000);ap.add_argument('--samples',type=int,default=5)
    a=ap.parse_args();WORK.mkdir(parents=True,exist_ok=True);ART.mkdir(exist_ok=True)
    suffix='{1}-{3}{0}^'
    cases={'countdown':'%{0}{4}{0}='+suffix,
           'external-call':'%{0}{4}{0}=%[math.square]r@@_'+suffix,
           'literal-text':'%{0}{4}{0}=[Urotif primitives]S@_'+suffix}
    report={'date':'2026-09-04','clock_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'platform':platform.platform(),
        'cpu':next((x.split(':',1)[1].strip() for x in Path('/proc/cpuinfo').read_text().splitlines() if x.startswith('model name')),'unknown'),
        'iterations':a.iterations,'samples':a.samples,'metric':'median complete CLI wall time; includes startup and VM initialization',
        'flags':{'Fortran':'-O2 -fcheck=all','C':'-std=c99 -O3 (no fast-math)','Rust':'-O -C strip=symbols (no fast-math)','WASM':'rustc -O -C strip=symbols; Node default engine'},
        'versions':{'gfortran':version(['gfortran','--version']),'gcc':version(['gcc','--version']),'rustc':version(['rustc','--version']),'node':version(['node','--version'])},'cases':{}}
    for name,body in cases.items():
        p=WORK/(name+'.utf');p.write_text('=) urotif\n{'+str(a.iterations)+'}\n'+body+'\n_h@\n')
        entries={};commands={};expect=None
        commands['Fortran native']=[BIN,'probe',p,'--foundation','--fuel',20000000]
        for target in ['c','rust','wasm']:
            for opt in [False,True]:
                label=f'{target} {"opt" if opt else "no-opt"}'
                ext={'c':'c','rust':'rs','wasm':'wasm'}[target]
                out=WORK/(name+('-opt.' if opt else '-raw.')+ext)
                _,lower_ms=run([BIN,target,p,'--foundation','-o',out,*([] if opt else ['--no-opt'])])
                build_ms=0
                if target=='c':
                    exe=out.with_suffix('.c-bin');_,build_ms=run(['gcc','-std=c99','-O3',out,'-lm','-o',exe]);cmd=[exe,'--json']
                elif target=='rust':
                    exe=out.with_suffix('.rs-bin');_,build_ms=run(['rustc','--edition=2021','--crate-name','urotif_benchmark','-O','-C','strip=symbols','-A','dead_code','-A','unused_imports',out,'-o',exe]);cmd=[exe,'--json']
                else:exe=out;cmd=['node','tools/foundation-wasm.mjs',out,'--json']
                commands[label]=cmd+['--fuel',20000000]
                entries[label]={'lower_ms':lower_ms,'target_compile_ms':build_ms,'artifact_bytes':exe.stat().st_size,'source_bytes':(Path(str(out)+'.rs') if target=='wasm' else out).stat().st_size}
        for label,cmd in commands.items():
            run(cmd) # warm file/system caches, not a persistent process
            durations=[]
            for _ in range(a.samples):
                result,ms=run(cmd);v=json.loads(result.stdout);status=0 if v.get('ok') else v.get('status')
                current=(status,v['output'],v['steps'])
                if expect is None:expect=current
                if current!=expect:raise AssertionError((name,label,expect,current))
                durations.append(ms)
            entries.setdefault(label,{}).update(median_ms=statistics.median(durations),samples_ms=durations,steps=v['steps'],collections=v['collections'])
            print(name,label,round(statistics.median(durations),3),'ms',flush=True)
        for opt in [False,True]:
            out=WORK/(name+('-opt.wasm' if opt else '-raw.wasm'))
            js=f"""import{{readFileSync}}from'node:fs';const{{instance}}=await WebAssembly.instantiate(readFileSync({json.dumps(str(out))}),{{}});const e=instance.exports;e.urotif_input_ptr();for(let i=0;i<5;i++)e.urotif_run(0,20000000);const samples=[];for(let i=0;i<{a.samples};i++){{const start=performance.now();for(let j=0;j<10;j++)if(e.urotif_run(0,20000000))throw Error('run failed');samples.push((performance.now()-start)/10)}}console.log(JSON.stringify(samples));"""
            values=json.loads(run(['node','--input-type=module','-e',js])[0].stdout)
            entries[f'wasm {"opt" if opt else "no-opt"}']['warm_vm_ms']=statistics.median(values)
        report['cases'][name]=entries
    (ART/'foundation-benchmarks.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['# Foundation optimization measurements','',f'Local measurement, {report["date"]}. {a.iterations:,} loop iterations; median of {a.samples} complete CLI runs.','',
      '**These are microbenchmarks, not a universal “fastest language” claim.** Both variants execute identical Urotif semantics and report identical output and logical instruction counts. `no-opt` disables the Fortran constant/reference fast paths; byte predecoding, bounds checks, caches and GC remain enabled in both compiled variants.','',
      '| Workload | Fortran native | C no-opt | C opt | C fast-path gain | Rust no-opt | Rust opt | WASM no-opt | WASM opt |',
      '|---|---:|---:|---:|---:|---:|---:|---:|---:|']
    for name,e in report['cases'].items():
        values=[e[x]['median_ms'] for x in ['Fortran native','c no-opt','c opt','rust no-opt','rust opt','wasm no-opt','wasm opt']]
        lines.append(f'| {name} | {values[0]:.2f} ms | {values[1]:.2f} ms | {values[2]:.2f} ms | {values[1]/values[2]:.2f}× | {values[3]:.2f} ms | {values[4]:.2f} ms | {values[5]:.2f} ms | {values[6]:.2f} ms |')
    lines+=['','## Separately: warm WASM VM execution','', 'Module instantiation/JIT startup is excluded here. Each fresh run still resets the VM and includes allocations and GC. These numbers are **not** mixed with the CLI figures above.','', '| Workload | no-opt | optimized |','|---|---:|---:|']
    for name,e in report['cases'].items():lines.append(f'| {name} | {e["wasm no-opt"]["warm_vm_ms"]:.3f} ms | {e["wasm opt"]["warm_vm_ms"]:.3f} ms |')
    lines+=['','## Reproduce','','```sh','make all','python3 tools/benchmark_foundation.py --iterations 20000 --samples 5','```','',f'CPU: {report["cpu"]}. Platform: {report["platform"]}.','', 'Compiler versions, flags, each timing sample, build time, binary size, GC counts, and matching semantic-step counts are in `artifacts/foundation-benchmarks.json`. Native Fortran has bounds checking enabled. C and Rust retain the explicit language limits, but these are different implementations: their ratio is not an isolated dispatch experiment.','', 'The WASM `lower_ms` includes its rustc build; the C/Rust rows record source lowering and native compilation separately. Shared-sandbox scheduling, CPU scaling, and microbenchmark choice can affect these results. No speed comparisons to Oak, arbitrary C/Rust programs, or other languages are claimed.','']
    (ROOT/'benchmarks/RESULTS.md').write_text('\n'.join(lines))
if __name__=='__main__':main()
