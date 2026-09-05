"""Shared source-bundle selection and limited repository hygiene checks."""
from pathlib import Path
import os
import re
import subprocess

SOURCE_DIRS = {
    '.github', 'ablations', 'benchmarks', 'docs', 'examples', 'fortran',
    'include', 'lib', 'plugins', 'reference', 'runtime', 'rust-chain', 'tests', 'tools',
}
ROOT_FILES = {
    '.editorconfig', '.gitattributes', '.gitignore', 'Makefile', 'README.md',
    'FOUNDATION.md', 'ROUNDTRIP.md', 'TYPED_LINKS.md', 'REVISED_TRUTH.md',
    'CONTRIBUTING.md', 'SECURITY.md', 'CHANGELOG.md', 'THIRD_PARTY_NOTICES.md',
    'LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING', 'rust-toolchain.toml',
}
GENERATED_DIRS = {
    '.git', 'build', 'bin', 'target', 'release', 'dist', 'node_modules',
    '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.cache',
    '.venv', 'venv', '.work', '.idea', '.vscode',
}
GENERATED_FILES = {
    'TRANSPILE.html', 'TYPED_LINKS.html', 'benchmarks/RESULTS.md',
    '.DS_Store', 'Thumbs.db', 'SOURCE_MANIFEST.json',
}
BINARY_SUFFIXES = {
    '.o', '.obj', '.mod', '.smod', '.a', '.lib', '.so', '.dll', '.dylib',
    '.exe', '.wasm', '.wat', '.zip', '.tar', '.gz', '.tgz', '.7z', '.pyc', '.pyo', '.log',
}
SENSITIVE_NAMES = {'.netrc', '.git-credentials', 'credentials.json', 'id_rsa', 'id_ed25519', 'id_ecdsa'}
SENSITIVE_SUFFIXES = {'.pem', '.key', '.p12', '.pfx'}
# High-confidence shapes only; this cannot prove the absence of every secret.
SECRET_PATTERNS = [
    ('private-key block', re.compile(r'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----')),
    ('GitHub token shape', re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})\b')),
    ('AWS access-key shape', re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b')),
    ('Slack token shape', re.compile(r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b')),
]


def path_issue(rel):
    """Return an exclusion reason; .urb/.uru are reference data, not executables."""
    rel = Path(rel)
    name = rel.name
    if rel.is_absolute() or '..' in rel.parts:
        return 'unsafe relative path'
    if any(part in GENERATED_DIRS for part in rel.parts):
        return 'generated/local directory'
    if rel.parts[0] == 'artifacts' and rel.as_posix() != 'artifacts/.gitkeep':
        return 'generated report/artifact'
    if rel.as_posix() in GENERATED_FILES or rel.suffix.lower() in BINARY_SUFFIXES:
        return 'generated/binary file'
    if name.endswith(('.wasm.rs', '.links.json')) or '.so.' in name:
        return 'generated target/library'
    if name in SENSITIVE_NAMES or rel.suffix.lower() in SENSITIVE_SUFFIXES:
        return 'sensitive filename'
    if name == '.env' or (name.startswith('.env.') and name != '.env.example'):
        return 'local environment file'
    if any(part in {'secrets', '.local'} for part in rel.parts):
        return 'local/sensitive directory'
    return None


def tracked_paths(root):
    """Use this repository's tracked set when available, not an ancestor repo."""
    if not (root / '.git').exists():
        return None
    result = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'],
                            capture_output=True, check=True)
    return [Path(os.fsdecode(p)) for p in result.stdout.split(b'\0') if p]


def source_paths(root):
    tracked = tracked_paths(root)
    if tracked is not None:
        paths = tracked
    else:
        paths = []
        for directory, dirs, names in os.walk(root, followlinks=False):
            here = Path(directory)
            dirs[:] = [d for d in dirs if d not in GENERATED_DIRS and not (here / d).is_symlink()]
            for name in names:
                rel = (here / name).relative_to(root)
                if rel.parts[0] in SOURCE_DIRS or rel.as_posix() in ROOT_FILES or rel.as_posix() == 'artifacts/.gitkeep':
                    paths.append(rel)
    return sorted((p for p in paths if path_issue(p) is None), key=lambda p: p.as_posix())


def inspect_files(root, paths):
    issues = []
    for rel in paths:
        p = root / rel
        reason = path_issue(rel)
        if reason:
            issues.append(f'{rel}: {reason}')
            continue
        if p.is_symlink() or not p.is_file():
            issues.append(f'{rel}: missing, symlink, or non-regular source file')
            continue
        # A symlinked parent can escape a package even if the leaf is regular.
        if any(parent.is_symlink() for parent in p.parents if parent != root and root in parent.parents):
            issues.append(f'{rel}: symlinked parent directory')
            continue
        raw = p.read_bytes()
        pe_offset = int.from_bytes(raw[60:64], 'little') if len(raw) >= 64 else 0
        is_pe = raw.startswith(b'MZ') and pe_offset >= 64 and raw[pe_offset:pe_offset+4] == b'PE\0\0'
        if raw.startswith((b'\x7fELF', b'\x00asm')) or is_pe:
            issues.append(f'{rel}: executable/module magic in a source file')
        text = raw.decode('utf-8', errors='replace')
        for label, pattern in SECRET_PATTERNS:
            if pattern.search(text):
                issues.append(f'{rel}: possible {label}; inspect before publishing')
    return issues
