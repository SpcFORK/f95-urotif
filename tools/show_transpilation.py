#!/usr/bin/env python3
"""Emit the 14-example gallery; execute WASM/native plus three full target builds.
Requires make all, rustc + wasm32-unknown-unknown, gcc, gfortran, and Node.
No source-language interpretation is done here: all translation uses bin/urotif.
"""
from pathlib import Path
import subprocess, json, hashlib, html, shutil
ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT/'bin/urotif'
DEST=ROOT/'artifacts/roundtrip'

def run(args,stdin='',cwd=ROOT):
    r=subprocess.run(list(map(str,args)),cwd=cwd,input=stdin,text=True,capture_output=True,timeout=90)
    if r.returncode:raise RuntimeError(f'{args}\n{r.stdout}\n{r.stderr}')
    return r.stdout

cases=json.loads((ROOT/'examples/next/cases.json').read_text())
results=[]
for case in cases:
    name=case['name'];directory=DEST/name;directory.mkdir(parents=True,exist_ok=True)
    src=ROOT/case['program'];checkdir=ROOT/'build/showcase'/name;checkdir.mkdir(parents=True,exist_ok=True)
    native=json.loads(run([BIN,'probe',src,'--foundation'],case['input']))
    checks={'native':{'status':0,'output_hex':native['output_hex'],'steps':native['steps']}}
    files={};recoveries={}
    for target,ext in [('c','c'),('rust','rs'),('fortran','f90'),('wasm','wasm')]:
        path=directory/(name+'.'+ext)
        run([BIN,target,src,'--foundation','--embed-source','-o',path])
        recovered=checkdir/(target+'-recovered.utf')
        run([BIN,'recover',path,'-o',recovered])
        assert recovered.read_bytes()==src.read_bytes(),(name,target,'recovery')
        files[target]=str(path.relative_to(ROOT));recoveries[target]=hashlib.sha256(recovered.read_bytes()).hexdigest()
    wasm=json.loads(run(['node',ROOT/'tools/foundation-wasm.mjs',ROOT/files['wasm'],'--json'],case['input']))
    checks['wasm']={k:wasm[k]for k in ['status','output_hex','steps']}
    if name in {'cube-library','factorial','hello-utf8'}:
        commands={
            'c':['gcc','-std=c99','-O2',ROOT/files['c'],'-lm','-o',checkdir/'c-program'],
            'rust':['rustc','--edition=2021','--crate-name','urotif_showcase','-O','-A','dead_code','-A','unused_imports',ROOT/files['rust'],'-o',checkdir/'rust-program'],
            'fortran':['gfortran','-std=f2003','-pedantic-errors','-O2','-fcheck=all','-J'+str(checkdir),ROOT/files['fortran'],'-o',checkdir/'fortran-program']}
        for target,command in commands.items():
            run(command,cwd=checkdir)
            value=json.loads(run([checkdir/(target+'-program'),'--json'],case['input']))
            checks[target]={k:value[k]for k in ['status','output_hex','steps']}
    for target,value in checks.items():
        assert value==checks['native'],(name,target,value,checks['native'])
        assert value['output_hex']==case['output_hex'],(name,target,'expected bytes')
    results.append({'name':name,'files':files,'executed':checks,'recovery_sha256':recoveries})
    print(name+': emitted/recovered four targets; verified '+', '.join(checks),flush=True)
(DEST/'verification.json').write_text(json.dumps({'version':'0.3.0','samples':results},indent=2)+'\n')

# Offline, self-contained viewer: embed the real emitted text, not mock code.
case=next(c for c in cases if c['name']=='cube-library');row=next(r for r in results if r['name']==case['name'])
panels={'Urotif (.ufm)':(ROOT/case['source']).read_text(),'Expanded (.utf)':(ROOT/case['program']).read_text()}
for label,target in [('Fortran','fortran'),('C','c'),('Rust','rust')]:panels[label]=(ROOT/row['files'][target]).read_text()
wasm_path=ROOT/row['files']['wasm']
panels['WASM']=json.dumps({'file':row['files']['wasm'],'bytes':wasm_path.stat().st_size,'sha256':hashlib.sha256(wasm_path.read_bytes()).hexdigest(),'header_hex':wasm_path.read_bytes()[:8].hex(),'execution':row['executed']['wasm'],'recovery_sha256':row['recovery_sha256']['wasm']},indent=2)
buttons=''.join(f'<button data-key="{html.escape(k)}">{html.escape(k)}</button>'for k in panels)
payload=json.dumps(panels,ensure_ascii=True).replace('<','\\u003c')
page='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Urotif 0.3 — real transpilation</title>
<style>
:root{color-scheme:dark;font-family:system-ui,sans-serif;background:#111820;color:#edf3f8}*{box-sizing:border-box}body{max-width:1180px;margin:auto;padding:34px 26px}small{color:#80dbc5;text-transform:uppercase;letter-spacing:.16em}h1{font-size:clamp(28px,5vw,46px);margin:12px 0}p{color:#acbdcc;line-height:1.6;max-width:850px}.flow{border:1px solid #334658;background:#192630;padding:20px;border-radius:12px;font-family:monospace;font-size:16px;line-height:1.9}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin:24px 0}.card{border:1px solid #334658;border-radius:10px;padding:17px;background:#17212b}.card strong{font-size:25px;color:#9de9d0}.card span{display:block;color:#aabcce;margin-top:8px;font-size:13px}nav{display:flex;gap:8px;flex-wrap:wrap;margin:22px 0 12px}button{background:#1b2d3a;border:1px solid #3c5365;color:#d1e0eb;border-radius:7px;padding:10px 16px;cursor:pointer}button.active{background:#a1e8d3;color:#10271f;border-color:#a1e8d3}pre{background:#0c1219;border:1px solid #324556;border-radius:10px;padding:22px;white-space:pre;overflow:auto;max-height:570px;line-height:1.5;font-size:13px;tab-size:2}.note{border-left:3px solid #e5bc73;padding:5px 17px;margin-top:24px}.meta{font-family:monospace;color:#819aad;font-size:12px}footer{margin-top:28px;color:#7e98ab;font-size:13px}@media(max-width:650px){.grid{grid-template-columns:1fr}body{padding:22px 14px}}
</style>
<small>Urotif / milestone 0.3</small><h1>One source. Four targets.</h1><p>These tabs contain actual generated files. The example imports a source-defined cube macro, applies it to three, and prints twenty-seven.</p>
<div class="flow">Fortran main → Fortran-decoded IR → Rust backend<br>↳ C &nbsp; · &nbsp; Rust &nbsp; · &nbsp; <b>Fortran</b> &nbsp; · &nbsp; WebAssembly</div>
<div class="grid"><div class="card"><strong>27 ↵</strong><span>Matching native / C / Rust / Fortran / WASM output</span></div><div class="card"><strong>14 examples</strong><span>Libraries, loops, calls, arrays, UTF-8 and exact bytes</span></div><div class="card"><strong>Recoverable</strong><span>Normalized source recovered and compared byte-for-byte</span></div></div>
<nav>BUTTONS</nav><div class="meta" id="meta"></div><pre><code id="code"></code></pre>
<div class="note"><b>Recovery is metadata, not decompilation.</b><p>The optional source capsule restores the original normalized Urotif byte program. It does not translate arbitrary or edited Fortran back into Urotif. The emitted programs execute predecoded instruction tables; they do not reparse Urotif.</p></div>
<footer>Full commands, resource budgets, remaining limits and verification history: ROUNDTRIP.md.<br>Generated files and execution records: artifacts/roundtrip/. No network or server is required for this viewer.</footer>
<script>const panels=PAYLOAD;const buttons=[...document.querySelectorAll('button')];function show(k){document.getElementById('code').textContent=panels[k];document.getElementById('meta').textContent=k+' · '+panels[k].split('\\n').length+' lines · actual source/output';buttons.forEach(b=>b.classList.toggle('active',b.dataset.key===k));}buttons.forEach(b=>b.onclick=()=>show(b.dataset.key));show('Urotif (.ufm)');</script></html>'''
(ROOT/'TRANSPILE.html').write_text(page.replace('BUTTONS',buttons).replace('PAYLOAD',payload))
