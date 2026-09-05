#!/usr/bin/env python3
"""Check selected/tracked source files and preserved reference checksums.
This is repository hygiene, not a complete secret scanner or legal review.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys
sys.dont_write_bytecode = True
from repo_files import inspect_files, source_paths, tracked_paths

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--clean-tree', action='store_true', help='also reject unselected files in an unbuilt source tree')
args = parser.parse_args()
tracked = tracked_paths(ROOT)
selected = source_paths(ROOT)
issues = inspect_files(ROOT, tracked if tracked is not None else selected)
if args.clean_tree:
    selected_set = set(selected)
    for p in ROOT.rglob('*'):
        rel = p.relative_to(ROOT)
        if '.git' in rel.parts:
            continue
        if p.is_symlink() or (p.is_file() and rel not in selected_set):
            issues.append(f'{rel}: not part of the clean source set')
refs = json.loads((ROOT / 'reference/SHA256.json').read_text())
for name, expected in refs.items():
    p = ROOT / 'reference' / name
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != expected:
        issues.append(f'reference/{name}: preserved checksum mismatch')
if issues:
    print('\n'.join(issues), file=sys.stderr)
    raise SystemExit(1)
print(f'OK: {len(selected)} selected source files; {len(refs)} preserved reference hashes; no flagged common secret patterns.')
if not any((ROOT / name).is_file() for name in ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING']):
    print('NOTICE: no project license is present; resolve licensing before public/open-source distribution.')
