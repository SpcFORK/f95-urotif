#!/usr/bin/env python3
"""Reproduce the source-archive ablation against a separately installed Oak.
The supplied archives are never edited. Patches live only in a temporary dir.
Usage: python3 tools/probe_oak.py --oak /path/to/oak
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MARKER = '\n__UROTIF_ABLATION_STATE__'


def oak_quote(s):
    return "'" + str(s).replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n') + "'"


def invoke(oak, script, stdin='2\n3\n'):
    try:
        result = subprocess.run([oak, str(script)], cwd=ROOT, input=stdin,
                                text=True, capture_output=True, timeout=3)
        record = dict(exit=result.returncode, stdout=result.stdout, stderr=result.stderr)
        if MARKER in result.stdout:
            output, state = result.stdout.rsplit(MARKER, 1)
            record['program_output'] = output
            record['state'] = json.loads(state)
        return record
    except subprocess.TimeoutExpired:
        return dict(timeout=True, note='external 3-second watchdog; no success claimed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--oak', required=True, help='Oak executable (tested with official v0.3)')
    parser.add_argument('--out', default=str(ROOT / 'artifacts/oak-evidence.json'))
    parser.add_argument('--sample', action='append', help='Specific source file; repeat for multiple files')
    args = parser.parse_args()
    samples = [Path(p).resolve() for p in args.sample] if args.sample else sorted((ROOT / 'reference/smp').iterdir())
    version = subprocess.run([args.oak, 'version'], text=True, capture_output=True, timeout=3)
    source = (ROOT / 'reference/urotif/main.oak').read_text()
    index_fixed = source.replace('Env.add(k.(h))', 'Env.add(h.(int(k)))')
    receiver_fixed = source.replace('Ctx.(lx.0)(std.slice(lx, 1)...)', 'sc.(lx.0)(std.slice(lx, 1)...)')
    all_fixed = index_fixed.replace('Ctx.(lx.0)(std.slice(lx, 1)...)', 'sc.(lx.0)(std.slice(lx, 1)...)')
    all_fixed = all_fixed.replace('[Env.pop() - 1, Env.pop() - 1]', '[int(Env.pop()) - 1, int(Env.pop()) - 1]')
    # Watchdog is explicit, separate from semantic repairs. No hanging sample
    # gets mislabeled as normal termination merely because the watchdog stops.
    all_fixed = all_fixed.replace('\tline: 0\n', '\tline: 0\n\tablationTicks: 0\n')
    all_fixed = all_fixed.replace('\t\teval(char, code)\n\t\tinc()\n',
        '\t\teval(char, code)\n\t\tinc()\n\t\tUctx.ablationTicks <- Uctx.ablationTicks + 1\n'
        '\t\tif Uctx.ablationTicks >= 80 -> Uctx.line <- len(code)\n')
    patches = [
        {'stage': 'A1_direct_API', 'source': source, 'description': 'Bypass broken run.oak wrapper; no interpreter edits.'},
        {'stage': 'A2_index_only', 'source': index_fixed, 'description': 'Replace k.(h) with h.(int(k)) in ;.'},
        {'stage': 'A3_receiver_only', 'source': receiver_fixed, 'description': 'Replace Ctx.(lx.0) with sc.(lx.0) in callFx.'},
        {'stage': 'A4_combined_with_watchdog', 'source': all_fixed,
         'description': 'Index + receiver + integer coordinates; explicit 80-instruction watchdog.'},
    ]
    result = {'oak_version': version.stdout.strip(), 'input': '2\n3\n',
              'main_oak_sha256': hashlib.sha256(source.encode()).hexdigest(), 'records': []}
    with tempfile.TemporaryDirectory(prefix='urotif-oak-') as td:
        td = Path(td)
        for sample in samples:
            # The archive's unmodified runner takes the filename as its argument.
            cli = subprocess.run([args.oak, str(ROOT / 'reference/urotif/run.oak'), str(sample)],
                                 cwd=ROOT, input='2\n3\n', text=True, capture_output=True, timeout=3)
            result['records'].append({'stage': 'A0_original_runner', 'sample': sample.name,
                                      'exit': cli.returncode, 'stdout': cli.stdout, 'stderr': cli.stderr})
        for stage in patches:
            module = td / (stage['stage'] + '.oak')
            module.write_text(stage['source'])
            for sample in samples:
                script = td / 'driver.oak'
                watchdog = stage['stage'] == 'A4_combined_with_watchdog'
                state = '{ memory: ctx.Env.Memory, watchdogHit: ctx.ablationTicks >= 80 }' if watchdog else '{ memory: ctx.Env.Memory }'
                script.write_text("main := import(" + oak_quote(module.with_suffix('')) + ")\n"
                                  "std := import('std')\njson := import('json')\n"
                                  'ctx := main.file(' + oak_quote(sample) + ')\n'
                                  'std.println(' + oak_quote(MARKER) + ' + json.serialize(' + state + '))\n')
                record = invoke(args.oak, script)
                record.update(stage=stage['stage'], sample=sample.name, change=stage['description'])
                result['records'].append(record)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    for record in result['records']:
        status = 'timeout' if record.get('timeout') else ('observed' if 'state' in record else 'error')
        if record.get('state', {}).get('watchdogHit'):
            status = 'watchdog stopped (not normal termination)'
        print(f"{record['stage']:30} {record['sample']:10} {status}")
    print('Evidence:', args.out)


if __name__ == '__main__':
    main()
