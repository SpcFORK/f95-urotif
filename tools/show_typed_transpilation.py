#!/usr/bin/env python3
"""Emit/recover/execute typed examples through Fortran Main -> Rust chain.
Use --only NAME ... for short batches. No Urotif interpreter is implemented here.
Requires make all plugins; generated native files link canonical C-ABI symbols.
"""
from pathlib import Path
import argparse, hashlib, html, json, subprocess
ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT/'bin/urotif';DEST=ROOT/'artifacts/typed'
NATIVE_LIBS=['-ldl','-lpthread','-lm','-lrt','-lutil']
def run(args,stdin='',cwd=ROOT):
    r=subprocess.run(list(map(str,args)),cwd=cwd,input=stdin,text=True,capture_output=True,timeout=20)
    if r.returncode:raise RuntimeError(f'{args}\n{r.stdout}\n{r.stderr}')
    return r.stdout

def gallery(cases,records):
    row=records.get('showcase')
    if not row:return
    case=next(c for c in cases if c['name']=='showcase')
    panels={'Urotif (.ufm)':(ROOT/case['source']).read_text(),'Expanded (.utf)':(ROOT/case['program']).read_text(),
            'Library macros':(ROOT/'lib/typed.ufm').read_text()}
    for title,key in [('Fortran','fortran'),('C','c'),('Rust','rust')]:panels[title]=(ROOT/row['files'][key]).read_text()
    wasm=ROOT/row['files']['wasm']
    panels['WASM + imports']=json.dumps({'file':row['files']['wasm'],'bytes':wasm.stat().st_size,
        'sha256':hashlib.sha256(wasm.read_bytes()).hexdigest(),'magic':wasm.read_bytes()[:8].hex(),
        'execution':row['executed']['wasm'],'catalog':json.loads(Path(str(wasm)+'.links.json').read_text())},indent=2)
    panels['C plugin']=(ROOT/'plugins/buffers.c').read_text()
    panels['Rust plugin']=(ROOT/'plugins/unicode.rs').read_text()
    panels['WASM host']=(ROOT/'plugins/typed-host.mjs').read_text()
    panels['Build commands']=row['reproduce']
    buttons=''.join(f'<button data-key="{html.escape(k)}">{html.escape(k)}</button>' for k in panels)
    rows=''.join('<tr><td>'+html.escape(c['name'])+'</td><td><code>'+html.escape(c['output'].strip().replace('\n',' · '))+'</code></td><td>'+('5/5 + recovery' if c['name'] in records else 'not yet recorded')+'</td></tr>' for c in cases)
    payload=json.dumps(panels,ensure_ascii=True).replace('<','\\u003c')
    page='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Urotif 0.4 — typed libraries</title>
<style>
:root{font-family:system-ui,sans-serif;color-scheme:dark;color:#eaf0f5;background:#101820}*{box-sizing:border-box}body{max-width:1220px;margin:auto;padding:36px 28px}header{display:flex;gap:12px;align-items:center;justify-content:space-between;color:#8fafa9;font-size:12px;letter-spacing:.15em;text-transform:uppercase}header span{border:1px solid #315449;padding:8px 12px;border-radius:30px;color:#b0ebcd}h1{font-size:clamp(32px,5vw,54px);line-height:1.08;max-width:760px;margin:27px 0 18px}h1 em{color:#91e2bc;font-style:normal}.lede{color:#b0bfca;font-size:17px;line-height:1.65;max-width:850px}.flow{border:1px solid #354653;background:#19252f;border-radius:12px;padding:18px 22px;font-family:monospace;line-height:1.9}.flow b{color:#abe7d1}.cards{display:grid;grid-template-columns:1.1fr 1fr;gap:18px;margin:25px 0}.card{border:1px solid #344957;padding:22px;border-radius:12px;background:#14212b}.card small{color:#90adbf;text-transform:uppercase;letter-spacing:.12em;font-size:11px}.card pre{background:none;border:0;padding:0;margin:13px 0 0;line-height:1.75;max-height:none;font-size:15px}.tag{display:inline-block;color:#ade8cf;background:#233e38;padding:5px 9px;border-radius:5px;margin:10px 4px 0 0;font-size:12px}h2{font-size:24px;margin-top:34px}nav{display:flex;gap:7px;flex-wrap:wrap;margin:16px 0 12px}button{border:1px solid #3a5264;background:#1b2c39;color:#c8d8e5;border-radius:6px;padding:10px 14px;cursor:pointer}button.active{background:#a9e7cb;border-color:#a9e7cb;color:#14291f}button:focus-visible{outline:2px solid #fff;outline-offset:2px}.meta{font:12px monospace;color:#91acbf;display:flex;justify-content:space-between;gap:15px}pre{font:13px/1.6 ui-monospace,monospace;border:1px solid #314757;border-radius:10px;background:#0c131b;padding:22px;overflow:auto;white-space:pre;max-height:570px;tab-size:2}table{border-collapse:collapse;width:100%;font-size:13px;line-height:1.6}td,th{text-align:left;border-bottom:1px solid #2c404f;padding:12px 10px}th{color:#8dadbf;font-weight:500;font-size:11px;text-transform:uppercase;letter-spacing:.1em}td:last-child{color:#96dcb6;white-space:nowrap}td code{color:#c4d3df;font-size:12px}.scroll{overflow:auto}.note{border-left:3px solid #dcbd78;margin:26px 0;padding:2px 18px;color:#beccd6;font-size:14px;line-height:1.7}.note b{color:#eddeb9}footer{border-top:1px solid #2d414d;margin-top:28px;padding-top:22px;color:#869fac;font-size:12px;line-height:1.8}@media(max-width:700px){body{padding:24px 14px}.cards{grid-template-columns:1fr}header{font-size:10px}pre{padding:16px}}
</style>
<header>Urotif / typed-link milestone <span>0.4 · actual generated files</span></header>
<h1>Extend the libraries.<br><em>Keep the language small.</em></h1>
<p class="lede">Numbers, binary bytes, and flat numeric vectors now cross the same reference/application boundary. New functions are described by signatures—not new Urotif opcodes or per-library interpreter branches.</p>
<div class="flow"><b>Fortran Main → Fortran-decoded IR → Rust chain</b><br>↳ Standalone C · Rust · Fortran · WebAssembly</div>
<div class="cards"><div class="card"><small>One source / five matching executions</small><pre>00ff43
[21, 41]
62
STRASSE CAFÉ</pre><span class="tag">Native Fortran</span><span class="tag">C</span><span class="tag">Rust</span><span class="tag">Fortran</span><span class="tag">WASM</span></div>
<div class="card"><small>The foreign signature is metadata</small><pre>hex     bytes → bytes
affine  vector, number, number → vector
sum     vector → number
upper   bytes → bytes</pre><span class="tag">ABI 1 retained</span><span class="tag">0–8 arguments</span><span class="tag">Caller-owned results</span></div></div>
<h2>Inspect the real pipeline</h2><p class="lede" style="font-size:14px">The Urotif example uses small source macros. Target tabs contain the actual standalone tables and runtime, not hand-written lookalikes. The plugin implementations are separate library code.</p>
<nav>BUTTONS</nav><div class="meta"><span id="meta"></span><span>Offline · no external assets</span></div><pre id="source"><code id="code"></code></pre>
<h2>Ten examples, compiled and run</h2><div class="scroll"><table><thead><tr><th>Example</th><th>Output</th><th>Verification</th></tr></thead><tbody>ROWS</tbody></table></div>
<div class="note"><b>Bounded does not mean sandboxed.</b><br>Type, capacity, ownership-descriptor, and finite-number checks reject contract failures. Native libraries are trusted code: these checks cannot stop native memory corruption, constructors, blocking, or crashes. WASM imports require explicit matching providers.</div>
<div class="note"><b>Recovery is still metadata—not decompilation.</b><br>All four targets carry optional normalized Urotif source capsules. Recovery is byte-compared; regenerated execution is checked. Reapply declarations, host grants, and resource policy when re-emitting. Arbitrary target edits are not translated back into Urotif.</div>
<footer>Guide and exact commands: TYPED_LINKS.md · Source: examples/typed/ · Generated files and execution records: artifacts/typed/.<br>Strict F95 remains available for built-in-only output. C-compatible foreign bindings use the separate F2003 adapter; the value/marshalling core remains F95.<br>Testing was staged; this viewer is an inspection/report page, not a browser execution sandbox.</footer>
<script>const panels=PAYLOAD;const buttons=[...document.querySelectorAll('button')];function show(k){document.getElementById('code').textContent=panels[k];document.getElementById('meta').textContent=k+' · '+panels[k].split('\\n').length+' lines';document.getElementById('source').scrollTop=0;buttons.forEach(b=>{const selected=b.dataset.key===k;b.classList.toggle('active',selected);b.setAttribute('aria-pressed',String(selected))});}buttons.forEach(b=>b.onclick=()=>show(b.dataset.key));show('Urotif (.ufm)');</script></html>'''
    (ROOT/'TYPED_LINKS.html').write_text(page.replace('BUTTONS',buttons).replace('ROWS',rows).replace('PAYLOAD',payload))

parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--only',nargs='+',help='emit and verify just these sample names')
args=parser.parse_args();cases=json.loads((ROOT/'examples/typed/cases.json').read_text())
if args.only and set(args.only)-{c['name'] for c in cases}:parser.error('unknown sample name')
DEST.mkdir(exist_ok=True,parents=True);record_path=DEST/'verification.json'
records={r['name']:r for r in json.loads(record_path.read_text())['samples']} if record_path.exists() else {}
for case in cases:
    name=case['name']
    if args.only and name not in args.only:continue
    directory=DEST/name;directory.mkdir(exist_ok=True)
    work=ROOT/'build/typed-showcase'/name;work.mkdir(parents=True,exist_ok=True)
    src=ROOT/case['program'];run([BIN,'assemble',ROOT/case['source'],'-o',src])
    flags=[];modules=[]
    for spec in case['imports']:
        flags+=['--extern-v2' if '->' in spec else '--extern',spec]
        m=spec.split('.')[0]
        if m not in modules:modules.append(m)
    links=[];objects=[]
    for module in modules:
        links+=['--link',ROOT/'build'/(module+'.so')]
        objects.append(ROOT/'build'/('libunicode.a' if module=='unicode' else module+'.o'))
    native=json.loads(run([BIN,'probe',src,'--foundation',*links],case['input']))
    assert native['ok'],native
    checks={'native':{'status':0,**{k:native[k] for k in ['output_hex','steps','stack_depth']}}}
    files={};recoveries={}
    for target,ext in [('c','c'),('rust','rs'),('fortran','f90'),('wasm','wasm')]:
        path=directory/(name+'.'+ext)
        run([BIN,target,src,'--foundation','--embed-source',*flags,'-o',path])
        recovered=work/(target+'-recovered.utf');run([BIN,'recover',path,'-o',recovered])
        assert recovered.read_bytes()==src.read_bytes(),(name,target,'source recovery')
        recoveries[target]=hashlib.sha256(recovered.read_bytes()).hexdigest()
        files[target]=str(path.relative_to(ROOT));exe=work/target
        if target=='c':command=['gcc','-std=c99','-O2',path,*objects,*NATIVE_LIBS,'-o',exe]
        elif target=='fortran':command=['gfortran','-std=f2003','-pedantic-errors','-O2','-fcheck=all',path,*objects,*NATIVE_LIBS,'-o',exe]
        elif target=='rust':
            command=['rustc','--edition=2021','--crate-name','typed_showcase','-O','-A','dead_code','-A','unused_imports',path]
            for obj in objects:command+=['-C',f'link-arg={obj}']
            command+=['-o',exe]
        else:command=None
        if command:run(command,cwd=work)
        argv=[exe,'--json'] if command else ['node',ROOT/'tools/foundation-wasm.mjs',path,'--json','--host',ROOT/'plugins/all-host.mjs']
        result=json.loads(run(argv,case['input']))
        checks[target]={k:result[k] for k in ['status','output_hex','steps','stack_depth']}
        assert checks[target]==checks['native'],(name,target,checks)
        assert result['output_hex']==case['output_hex'],(name,target,'expected bytes',result)
        if target=='wasm':
            # Actually re-emit recovered Urotif and execute it with explicit grants again.
            again=work/'recovered.wasm';run([BIN,'wasm',recovered,'--foundation',*flags,'-o',again])
            rerun=json.loads(run(['node',ROOT/'tools/foundation-wasm.mjs',again,'--json','--host',ROOT/'plugins/all-host.mjs'],case['input']))
            assert {k:rerun[k] for k in checks['native']}==checks['native']
    import shlex
    quoted=' '.join(shlex.quote(x) for x in flags)
    reproduce=f'''# Linux/GCC/Rust/Node; run from the project root.
make all plugins
bin/urotif assemble {case['source']} -o {case['program']}
bin/urotif run {case['program']} --foundation {' '.join('--link build/'+m+'.so' for m in modules)}
# Emit with metadata only: the emitter does NOT load a native plugin here.
bin/urotif wasm {case['program']} --foundation --embed-source {quoted} -o build/{name}.wasm
node tools/foundation-wasm.mjs build/{name}.wasm --json --host plugins/all-host.mjs
bin/urotif recover build/{name}.wasm -o build/{name}-recovered.utf
# Full native target compilation commands: TYPED_LINKS.md
'''
    records[name]={'name':name,'files':files,'imports':case['imports'],'native_modules':modules,'executed':checks,
       'recovery_sha256':recoveries,'recovered_wasm_execution':True,'reproduce':reproduce}
    record_path.write_text(json.dumps({'version':'0.4.0','samples':[records[c['name']] for c in cases if c['name'] in records]},indent=2)+'\n')
    print(name+': five matching executions, four exact source recoveries, recovered WASM re-emitted/run',flush=True)
gallery(cases,records)
