#!/usr/bin/env python3
import argparse
import re
import zipfile
from pathlib import Path
from artifact_contract import tree_files, validate

p = argparse.ArgumentParser()
p.add_argument('--root', type=Path, default=Path('.'))
p.add_argument('--basename', required=True)
p.add_argument('--platform', choices=['linux','windows'], required=True)
p.add_argument('--validate-only', action='store_true')
a = p.parse_args()
if not re.fullmatch(r'[a-z0-9][a-z0-9.-]*', a.basename): raise ValueError('Unsafe release basename')
tree = a.root / 'dist' / a.platform / 'artifact'
files = tree_files(tree)
validate(files, a.platform)
archive = a.root / 'dist' / 'release' / (a.basename + '.zip')
if not a.validate_only:
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(files.items()): z.writestr(name, data)
with zipfile.ZipFile(archive) as z:
    if len(z.namelist()) != len(set(z.namelist())): raise ValueError('Duplicate ZIP entries')
    validate({n:z.read(n) for n in z.namelist()}, a.platform)
print('Validated tree and ZIP:', archive)
