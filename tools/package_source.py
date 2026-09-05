#!/usr/bin/env python3
"""Create a filtered, deterministic-order source ZIP, never a workspace dump.
With Git: include eligible tracked files. Without Git: use the source allowlist.
Checksum and per-file manifest sidecars stay outside the repository payload.
"""
from pathlib import Path
import argparse
import hashlib
import json
import stat
import sys
import tomllib
import zipfile
sys.dont_write_bytecode = True
from repo_files import inspect_files, source_paths, tracked_paths

ROOT = Path(__file__).resolve().parents[1]
version = tomllib.loads((ROOT / 'rust-chain/Cargo.toml').read_text())['package']['version']
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('-o', '--output', type=Path, default=ROOT / 'release' / f'urotif-source-v{version}.zip')
args = parser.parse_args()
dest = args.output.resolve()
if dest.suffix.lower() != '.zip':
    parser.error('output must end in .zip')
paths = source_paths(ROOT)
# Fail rather than silently hide dangerous or accidentally tracked products.
tracked = tracked_paths(ROOT)
issues = inspect_files(ROOT, tracked if tracked is not None else paths)
if issues:
    print('\n'.join(issues), file=sys.stderr)
    raise SystemExit(1)
files = {rel.as_posix(): (ROOT / rel).read_bytes() for rel in paths}
manifest = {name: hashlib.sha256(data).hexdigest() for name, data in files.items()}
dest.parent.mkdir(parents=True, exist_ok=True)
temp = dest.with_suffix(dest.suffix + '.tmp')
try:
    with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo('urotif/' + name, date_time=(1980, 1, 1, 0, 0, 0))
            mode = 0o755 if (ROOT / name).stat().st_mode & 0o111 else 0o644
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | mode) << 16
            archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(temp) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('ZIP CRC check failed')
        for name, digest in manifest.items():
            if hashlib.sha256(archive.read('urotif/' + name)).hexdigest() != digest:
                raise RuntimeError(f'ZIP content mismatch: {name}')
    temp.replace(dest)
finally:
    temp.unlink(missing_ok=True)
digest = hashlib.sha256(dest.read_bytes()).hexdigest()
dest.with_suffix(dest.suffix + '.sha256').write_text(f'{digest}  {dest.name}\n')
dest.with_suffix(dest.suffix + '.manifest.json').write_text(json.dumps({
    'version': version, 'archive': dest.name, 'sha256': digest, 'files': manifest,
}, indent=2) + '\n')
print(json.dumps({'archive': str(dest), 'source_files': len(files), 'bytes': dest.stat().st_size,
                  'sha256': digest, 'validation': 'ZIP CRC + every source SHA256 verified'}, indent=2))
