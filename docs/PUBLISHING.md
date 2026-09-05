# Put this source bundle on GitHub

The ZIP is a clean source tree, not a Git repository with hidden history. It contains no `.git` directory, remote URL, credentials, native executables, compiler caches, old release archives, generated target galleries, or local verification logs.

## Before a public release

- Resolve [licensing](LICENSING.md), including the preserved reference fixtures. No license was invented during cleanup.
- Review the files and run the repository check.
- Decide on the GitHub owner/repository name. No repository has been created and nothing has been pushed by preparing this bundle.

## Using Git

Unzip the bundle, open the resulting `urotif/` directory, and create an empty GitHub repository. Avoid initializing the remote with a separate README/license if you want a direct first push.

```sh
cd urotif
python3 tools/check_repository.py --clean-tree

git init -b main
git add .
git status --short
git commit -m "Import Urotif 0.4 source"

git remote add origin https://github.com/YOUR-OWNER/urotif.git
git push -u origin main
```

Replace `YOUR-OWNER` with the actual account/organization. Authenticate through your Git credential manager, GitHub CLI, or SSH configuration—never embed a token in a committed URL or file.

The supplied `.gitattributes` prevents newline normalization of byte-language/reference fixtures. Do not change those rules casually: whitespace and exact bytes can be semantic.

## Using GitHub's upload UI

Git is recommended for this multi-directory bundle. If using the web interface, upload the contents of `urotif/`, not the outer folder or the ZIP itself; use batches if the interface imposes a file-count limit. Include the dotfiles and `.github/` directory. Leave external ZIP checksum/manifest sidecars outside the repository. Review the staged file list before committing. GitHub's upload UI is not a replacement for checking licenses and secrets.

## After the first push

The Actions workflow runs on pushes, pull requests, or manual dispatch. Its five independent jobs cover reference/core, Foundation, roundtrip, typed, and sanitizer suites. It does not publish packages or deploy software. A workflow file is not evidence of a successful hosted run: inspect the Actions results on your repository.

Consider enabling branch protection and private vulnerability reporting after the initial CI run. No repository-specific settings or permissions are assumed by this bundle.

## Keep the repository clean

Generated files stay local under `build/`, `bin/`, `artifacts/`, `release/`, and `rust-chain/target/`. Offline inspectors (`TRANSPILE.html`, `TYPED_LINKS.html`) can be regenerated but are ignored. Source `.utf`/`.ufm` examples and reference fixtures are intentionally retained.

```sh
make all core95 plugins -j2
python3 tools/check_repository.py
python3 tools/package_source.py
```

The package command writes a source ZIP plus external `.sha256` and `.manifest.json` files under `release/`. File order/timestamps are normalized, and ZIP CRC plus per-file hashes are checked. In a Git checkout it packages eligible tracked files; add intended new files before creating a release. Without Git it uses the documented source-directory allowlist in `tools/repo_files.py`.

The hygiene checker screens common credential filenames and high-confidence key/token patterns. It is a limited safety check, not a guarantee that every secret or licensing problem has been found.
