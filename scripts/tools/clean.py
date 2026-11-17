import sys, shutil
from pathlib import Path
root = Path(__file__).resolve().parents[2]
paths = [Path(x).resolve() for x in sys.argv[1:]]
for p in paths:
    if not any(base in p.parents for base in (root/'.build', root/'dist')):
        raise ValueError(f'Refusing unmanaged cleanup: {p}')
for p in paths:
    if p.exists(): shutil.rmtree(p)
