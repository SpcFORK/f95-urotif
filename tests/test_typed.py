#!/usr/bin/env python3
"""ABI-2 native/C/Rust/Fortran/WASM differential checks, in short selectable suites.
No frontend is implemented here: the Fortran CLI assembles and decodes all source.
"""
from pathlib import Path
import hashlib, json, subprocess, tempfile, unittest
ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'bin/urotif'
HEADER = '=) urotif\n'
VARIANTS = [('c',True),('c',False),('rust',True),('fortran',True),('fortran',False),('wasm',True)]

def command(args, stdin='', cwd=ROOT, timeout=20):
    return subprocess.run(list(map(str,args)),input=stdin,cwd=cwd,text=True,capture_output=True,timeout=timeout)
def require(args, **kw):
    r=command(args,**kw)
    if r.returncode: raise AssertionError(f'{args}\n{r.stdout}\n{r.stderr}')
    return r

class Typed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='urotif-typed-')
        cls.work=Path(cls.temp.name);cls.cache={};cls.links=[];cls.objects=[]
        for name,src in [('buffers','plugins/buffers.c'),('audit','tests/fixtures/typed_contract.c'),('demo','plugins/demo.c')]:
            so=cls.work/(name+'.so');obj=cls.work/(name+'.o')
            require(['gcc','-std=c99','-O2','-shared','-fPIC',ROOT/src,'-lm','-o',so])
            require(['gcc','-std=c99','-O2','-DUROTIF_STATIC_LINK','-c',ROOT/src,'-o',obj])
            cls.links+=['--link',so];cls.objects.append(obj)
        so=cls.work/'unicode.so';obj=cls.work/'libunicode.a'
        require(['rustc','--edition=2021','-O','-A','dead_code','--crate-type=cdylib',ROOT/'plugins/unicode.rs','-o',so])
        require(['rustc','--edition=2021','-O','-A','dead_code','-A','unused_imports','--crate-type=staticlib','--cfg','urotif_static_link',ROOT/'plugins/unicode.rs','-o',obj])
        cls.links+=['--link',so];cls.objects.append(obj)
    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()
    def source(self,body):
        text=HEADER+body+'\n';p=self.work/(hashlib.sha256(text.encode()).hexdigest()[:20]+'.utf');p.write_text(text);return p
    def native(self,p,stdin='',flags=(),links=None,fuel=1000000):
        flags=[f for f in flags if f!='--embed-source']
        r=command([BIN,'probe',p,'--foundation','--fuel',fuel,*flags,*(self.links if links is None else links)],stdin)
        self.assertIn(r.returncode,(0,1),(r.stdout,r.stderr));self.assertTrue(r.stdout,(r.stderr,p))
        v=json.loads(r.stdout);v['status']=0 if v['ok'] else int(v['error'][1:4]);v.setdefault('stack_depth',len(v['stack']));return v
    def build(self,p,target,opt=True,flags=(),links=None):
        links=self.links if links is None else links
        key=(str(p),target,opt,tuple(map(str,flags)),tuple(map(str,links)))
        if key in self.cache:return self.cache[key]
        folder=self.work/hashlib.sha256(repr(key).encode()).hexdigest()[:20];folder.mkdir()
        src=folder/('program.'+{'c':'c','rust':'rs','fortran':'f90','wasm':'wasm'}[target]);exe=folder/'program'
        require([BIN,target,p,'--foundation',*flags,*links,*([] if opt else ['--no-opt']),'-o',src])
        if target=='c':require(['gcc','-std=c99','-O2',src,*self.objects,'-ldl','-lpthread','-lm','-lrt','-lutil','-o',exe],cwd=folder)
        elif target=='fortran':require(['gfortran','-std=f2003','-pedantic-errors','-O2','-fcheck=all',src,*self.objects,'-ldl','-lpthread','-lm','-lrt','-lutil','-o',exe],cwd=folder)
        elif target=='rust':
            args=['rustc','--edition=2021','--crate-name','typed_test','-O','-A','dead_code','-A','unused_imports',src]
            for obj in self.objects:args+=['-C',f'link-arg={obj}']
            require([*args,'-o',exe],cwd=folder)
        cmd=['node',ROOT/'tools/foundation-wasm.mjs',src,'--json','--host',ROOT/'tests/fixtures/typed-contract-host.mjs'] if target=='wasm' else [exe,'--json']
        self.cache[key]=(cmd,src);return cmd,src
    def compiled(self,cmd,stdin='',fuel=1000000,repeat=1):
        r=command([*cmd,'--fuel',fuel,'--repeat',repeat],stdin)
        self.assertIn(r.returncode,(0,1),(r.stdout,r.stderr));return json.loads(r.stdout)
    def parity(self,p,stdin='',flags=(),variants=VARIANTS,links=None):
        native=self.native(p,stdin,flags,links)
        for target,opt in variants:
            with self.subTest(target=target,opt=opt):
                cmd,_=self.build(p,target,opt,flags,links);v=self.compiled(cmd,stdin)
                for key in ['status','steps','output','output_hex','stack_depth']:
                    self.assertEqual(native[key],v[key],(key,native,v))
                if v['status']:self.assertEqual((native['line'],native['column']),(v['line'],v['column']))
        return native
    def test_value_flow_all_targets(self):
        body=r'''[\x00\xffC]S@[buffers.hex]r@@$\n$
[00ff43]S@[buffers.unhex]r@@$\n$
[[buffers.concat]r@[ab]S@[cd]S@]a@$\n$
[buffers.empty]r@@[std.len]r@@$\n$
[abcdef]S@{3}[buffers.prefix]r@@$\n$
[{2}{4}]{10}{1}[buffers.affine]r@@%$\n$[buffers.sum]r@@$\n$
[{1}{2}{3}][{4}{5}{6}][buffers.dot]r@@$\n$
[Stra\xc3\x9fe caf\xc3\xa9]S@[unicode.upper]r@@$\n$
[A\xf0\x9f\x98\x80\xc3\xa9]S@[unicode.codepoints]r@@$\n$
[{3}{2}~{3}{0}][unicode.sort]r@@$\n$
[][buffers.sum]r@@$\n$
[]{2}{1}[buffers.affine]r@@$\n$
[][unicode.sort]r@@$\n$
[audit.zero]r@@$\n$
{1}{2}{3}{4}{5}{6}{7}{8}[audit.sum8]r@@$\n$
{3}[demo.cube]r@@$\n$
h@'''
        v=self.parity(self.source(body),flags=['--embed-source'])
        expected=b'00ff43\n\x00\xffC\nabcd\n0\nabc\n[21, 41]\n62\n32\n'+ 'STRASSE CAFÉ\n3\n[-2, 0, 3, 3]\n0\n[]\n[]\n42\n36\n27\n'.encode()
        self.assertEqual((v['status'],v['output_hex']),(0,expected.hex()))
    def test_failure_matrix_all_targets(self):
        rows=[
          '{1}[buffers.hex]r@@','[x]S@[buffers.sum]r@@','[a{2}][buffers.sum]r@@',
          '[[{1}]][buffers.sum]r@@','[[buffers.hex]r@]a@','[[buffers.hex]r@[x]S@[y]S@]a@',
          '[xyz]S@[buffers.unhex]r@@','[gg]S@[buffers.unhex]r@@',r'[\xff]S@[unicode.upper]r@@',
          '[abc]S@{1.5}[buffers.prefix]r@@','[abc]S@{1}~[buffers.prefix]r@@',
          '[{1}][{2}{3}][buffers.dot]r@@','[{1e308}{1e308}][buffers.sum]r@@',
          '[{1e308}]{2}{0}[buffers.affine]r@@',
        ]+['[audit.'+name.replace('_',r'\_')+']r@@' for name in ['missing','nan','infinite','long_bytes','long_vector','capacity','vector_capacity','pointer','vector_pointer','status']]
        p=self.source('[[int]S@`]C@0^\n'+'\n'.join(row+'h@' for row in rows))
        for i,row in enumerate(rows):
            with self.subTest(case=row):self.assertEqual(self.parity(p,str(i+3)+'\n')['status'],12)
    def test_output_channel_boundaries(self):
        rows=[
          ('[ab]S@[buffers.hex]r@@$h@',0,b'6162'),
          ('['+'a'*32+']S@[buffers.hex]r@@$h@',0,b'61'*32),
          ('['+'a'*33+']S@[buffers.hex]r@@$h@',12,b''),
          ('['+'{1}'*8+']{2}{1}[buffers.affine]r@@$h@',0,b'[3, 3, 3, 3, 3, 3, 3, 3]'),
          ('['+'{1}'*9+']{2}{1}[buffers.affine]r@@$h@',12,b''),
          ('[x]S@$['+'a'*32+']S@[buffers.hex]r@@$h@',2,b'x'),
        ]
        p=self.source('[[int]S@`]C@0^\n'+'\n'.join(row for row,_,_ in rows))
        for i,(row,status,output) in enumerate(rows):
            with self.subTest(case=i):
                v=self.parity(p,str(i+3)+'\n',flags=['--limit','output=64'])
                self.assertEqual((v['status'],v['output_hex']),(status,output.hex()))
    def test_aggregate_input_limits_count_aliases(self):
        for body,limit in [('['+'{1}'*17+']%[buffers.dot]r@@h@','edges=32'),
            ('['+'a'*140+']S@%[buffers.concat]r@@h@','text=256')]:
            with self.subTest(limit=limit):
                self.assertEqual(self.parity(self.source(body),flags=['--limit',limit])['status'],2)
    def test_metadata_only_grants_and_recovery(self):
        p=self.source(r'[\x00\xffC]S@[buffers.hex]r@@$h@')
        links=['--extern-v2','buffers.hex/bytes->bytes']
        self.assertEqual(self.native(p,links=links)['status'],12)
        for target in ['c','rust','fortran','wasm']:
            cmd,src=self.build(p,target,flags=['--embed-source'],links=links)
            self.assertEqual(self.compiled(cmd)['output'],'00ff43')
            recovered=src.with_suffix(src.suffix+'.utf');require([BIN,'recover',src,'-o',recovered])
            self.assertEqual(recovered.read_bytes(),p.read_bytes())
            self.assertEqual(self.native(recovered,links=links)['status'],12) # Source is not a capability grant.
            catalog=json.loads(Path(str(src)+'.links.json').read_text())
            entry=catalog['symbols'][-1]
            self.assertEqual(entry['signature'],{'abi':2,'parameters':[2],'result':2})
            if target=='wasm':
                denied=command(cmd[:-2]);self.assertEqual(json.loads(denied.stdout)['status'],-1)
                self.assertIn('not granted',denied.stdout)
                js="import{readFileSync}from'node:fs';const m=await WebAssembly.compile(readFileSync(process.argv[1]));console.log(new TextDecoder().decode(WebAssembly.Module.customSections(m,'urotif.links.v2')[0]));"
                embedded=json.loads(require(['node','--input-type=module','-e',js,src]).stdout)
                self.assertEqual(embedded,catalog)
        # Reapply the explicit declaration and host grant when re-emitting recovered source.
        cmd,_=self.build(recovered,'wasm',links=links)
        self.assertEqual(self.compiled(cmd)['output'],'00ff43')
    def test_calls_subroutines_and_repeat(self):
        source=self.work/'routines.ufm';assembled=self.work/'routines.utf'
        source.write_text('''[{2}{4}]
.call transform
.dup
.println
.ref buffers.sum
@
.println
.halt
.label transform
.number 10
.number 1
.ref buffers.affine
@
.return
''')
        require([BIN,'assemble',source,'-o',assembled]);v=self.parity(assembled)
        self.assertEqual(v['output'],'[21, 41]\n62\n')
        for target in ['c','rust','fortran','wasm']:
            cmd,_=self.build(assembled,target);self.assertEqual(self.compiled(cmd),self.compiled(cmd,repeat=4))
    def test_gc_preserves_typed_results(self):
        p=self.source(r"[Stra\xc3\x9fe caf\xc3\xa9]S@[unicode.upper]r@@[{9}{1}{5}][unicode.sort]r@@{500}"+'\n'+
            r"%{0}{4}{0}=[aa]S@[buffers.hex]r@@_[{2}{4}]{2}{1}[buffers.affine]r@@_{1}-{3}{0}^"+'\n'+
            r"_[buffers.sum]r@@$\n$$\n$h@")
        flags=['--limit','nodes=256','--limit','edges=256','--limit','text=1024','--limit','output=128']
        v=self.parity(p,flags=flags);self.assertEqual((v['status'],v['output']),(0,'15\nSTRASSE CAFÉ\n'))
        self.assertGreater(v['collections'],0)
        for target,opt in VARIANTS:
            cmd,_=self.build(p,target,opt,flags);self.assertGreater(self.compiled(cmd)['collections'],0)
    def test_declared_signature_validation(self):
        for spec in ['demo.x/bytes','demo.x/object->number','demo.x/bytes->object',
          'demo.x/number,->bytes','std.x/->number','../x.f/->number','demo.x/'+','.join(['number']*9)+'->number']:
            with self.subTest(spec=spec):self.assertNotEqual(command([BIN,'links','--extern-v2',spec]).returncode,0)
        for flags in [['--extern-v2','x.f/->bytes','--extern-v2','x.f/->bytes'],
          ['--extern','x.f/1','--extern-v2','x.f/bytes->bytes'],['--link',self.links[1],'--link',self.links[1]]]:
            self.assertNotEqual(command([BIN,'links',*flags]).returncode,0)
        p=self.source('[buffers.empty]r@@h@');out=self.work/'forbidden95.f90'
        r=command([BIN,'fortran',p,'--foundation','--f95',*self.links,'-o',out])
        self.assertNotEqual(r.returncode,0);self.assertFalse(out.exists());self.assertIn('F2003',r.stderr)
        # Each metadata identifier may have 63 bytes; their C binding label
        # must not make generated Fortran exceed its standard 132-column limit.
        module='a'*63;name='b'*63;canonical='urotif_ext_'+module+'_'+name
        p=self.source('['+module+'.'+name+']r@@h@');out=self.work/'long-binding.f90'
        require([BIN,'fortran',p,'--foundation','--extern-v2',module+'.'+name+'/->number','-o',out])
        folder=self.work/'long-modules';folder.mkdir()
        require(['gfortran','-std=f2003','-pedantic-errors','-O2','-c',out,'-o',folder/'program.o'],cwd=folder)
        self.assertIn(canonical,require(['nm','-u',folder/'program.o']).stdout)
    def test_legacy_missing_result_is_not_zero(self):
        c=self.work/'old-contract.c';so=self.work/'old-contract.so';obj=self.work/'old-contract.o'
        c.write_text(f'''#include "{ROOT/'include/urotif_plugin.h'}"
int32_t urotif_ext_oldcontract_untouched(const double*a,size_t n,double*r){{return 0;}}
#ifndef UROTIF_STATIC_LINK
static const UrotifPluginSymbol s={{"untouched",0,urotif_ext_oldcontract_untouched}};
static const UrotifPlugin p={{1,"oldcontract",1,&s}};
const UrotifPlugin*urotif_plugin_v1(void){{return &p;}}
#endif
''')
        require(['gcc','-std=c99','-shared','-fPIC',c,'-o',so])
        require(['gcc','-std=c99','-DUROTIF_STATIC_LINK','-c',c,'-o',obj])
        self.objects=[*self.objects,obj]
        host=self.work/'old-host.mjs';host.write_text("export default {'oldcontract.untouched':()=>undefined};\n")
        p=self.source('[oldcontract.untouched]r@@$h@');links=['--link',so]
        expected=self.native(p,links=links);self.assertEqual(expected['status'],12)
        for target,opt in VARIANTS:
            cmd,_=self.build(p,target,opt,links=links)
            if target=='wasm':cmd=[*cmd[:-1],host]
            got=self.compiled(cmd)
            for key in ['status','steps','output_hex','stack_depth']:
                self.assertEqual(got[key],expected[key],(target,opt,got,expected))
    def test_bad_v2_descriptor_does_not_fall_back_to_v1(self):
        # Exports both entries: a valid v1 descriptor must not mask a broken v2 entry.
        for name,initializer,symbol in [
          ('version','{99,sizeof(UrotifPluginV2),"bad",1,&s}','{"x",0,{0},1,f}'),
          ('size','{2,0,"bad",1,&s}','{"x",0,{0},1,f}'),
          ('arity','{2,sizeof(UrotifPluginV2),"bad",1,&s}','{"x",9,{1},1,f}'),
          ('padding','{2,sizeof(UrotifPluginV2),"bad",1,&s}','{"x",0,{1},1,f}'),
          ('type','{2,sizeof(UrotifPluginV2),"bad",1,&s}','{"x",1,{9},1,f}'),
          ('function','{2,sizeof(UrotifPluginV2),"bad",1,&s}','{"x",0,{0},1,0}'),
        ]:
            with self.subTest(name=name):
                c=self.work/(name+'.c');so=self.work/(name+'.so')
                c.write_text(f'''#include "{ROOT/'include/urotif_plugin_v2.h'}"
#include "{ROOT/'include/urotif_plugin.h'}"
static int32_t f(const UrotifTypedArg*a,size_t n,UrotifTypedResult*r){{return 1;}}
static int32_t old(const double*a,size_t n,double*r){{*r=1;return 0;}}
static const UrotifPluginSymbolV2 s={symbol};static const UrotifPluginV2 p={initializer};
const UrotifPluginV2*urotif_plugin_v2(void){{return &p;}}
static const UrotifPluginSymbol t={{"ok",0,old}};static const UrotifPlugin q={{1,"fallback",1,&t}};
const UrotifPlugin*urotif_plugin_v1(void){{return &q;}}
''')
                require(['gcc','-std=c99','-shared','-fPIC',c,'-o',so]);r=command([BIN,'links','--link',so])
                self.assertNotEqual(r.returncode,0,(r.stdout,r.stderr))

if __name__=='__main__':unittest.main(verbosity=2)
