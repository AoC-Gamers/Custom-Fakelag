#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path
from artifact_contract import inventory, tree_files, validate

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
    files[name] = (a.root / name).read_bytes()
validate(files, a.platform)
out = a.root / 'dist' / a.platform / 'artifact'
if out.exists(): shutil.rmtree(out)
for name, data in files.items():
    target = out / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
print(out)
