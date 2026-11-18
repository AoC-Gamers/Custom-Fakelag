#!/usr/bin/env python3
import argparse
import shutil
import os
import re
import subprocess
from pathlib import Path
from artifact_contract import inventory, tree_files, validate

def installation_readme(root):
    source = (root / 'README.md').read_text(encoding='utf-8')
    installation = source.split('## Instalación\n', 1)[1].split('\n## ', 1)[0].strip()
    revision = os.getenv('SOURCE_REVISION') or os.getenv('GITHUB_SHA')
    if not revision and (root / '.git').exists():
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    repository = 'https://github.com/AoC-Gamers/Custom-Fakelag'
    if revision and not re.fullmatch(r'[a-f0-9]{40}', revision):
        raise ValueError('Invalid source revision')
    def rewrite_link(match):
        path = match[1]
        destination = f'{repository}/blob/{revision}/{path}' if revision else repository
        return f']({destination})'
    installation = re.sub(r'\]\((docs/[^)]+)\)', rewrite_link, installation)
    identity = f'Commit de referencia: `{revision}`.' if revision else 'Build local sin commit identificado.'
    return (f'# Custom-Fakelag para Left 4 Dead 2\n\n{identity}\n\n'
            f'## Instalación\n\n{installation}\n\n'
            'Consulta [la licencia](LICENSE) y el [historial de cambios](CHANGELOG.md).\n').encode('utf-8')


p = argparse.ArgumentParser()
p.add_argument('root', type=Path)
p.add_argument('smx', type=Path)
p.add_argument('exts', type=Path)
p.add_argument('--platform', required=True, choices=['linux','windows'])
a = p.parse_args()
files = {}
for source in (a.smx, a.exts):
    if not source.is_dir(): raise ValueError(f'Missing stage {source}')
    for name, data in tree_files(source).items():
        if name in files: raise ValueError(f'Stage collision: {name}')
        files[name] = data
for name in inventory(a.platform):
    if name.startswith('addons/'): continue
    files[name] = installation_readme(a.root) if name == 'README.md' else (a.root / name).read_bytes()
validate(files, a.platform)
out = a.root / 'dist' / a.platform / 'artifact'
if out.exists(): shutil.rmtree(out)
for name, data in files.items():
    target = out / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
print(out)
