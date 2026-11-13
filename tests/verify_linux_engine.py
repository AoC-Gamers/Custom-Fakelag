#!/usr/bin/env python3
"""Verify the exact offline ELF module backing the Linux adapter. No execution."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('module', type=Path)
args = parser.parse_args()
manifest = json.loads((ROOT / 'docs/runtime/linux-engine-2.2.4.3.json').read_text())
data = args.module.read_bytes()
if hashlib.sha256(data).hexdigest() != manifest['sha256']:
    raise SystemExit('Unsupported engine SHA-256')
if data[:6] != b'\x7fELF\x01\x01':
    raise SystemExit('Expected ELF32 little endian')
header = struct.unpack_from('<16sHHIIIIIHHHHHH', data)
if header[2] != 3:
    raise SystemExit('Expected EM_386')
sections = [struct.unpack_from('<IIIIIIIIII', data, header[6] + i * header[11]) for i in range(header[12])]
symbols = {}
for section in sections:
    if section[1] != 2:
        continue
    names = sections[section[6]]
    strings = data[names[4]:names[4] + names[5]]
    for offset in range(section[4], section[4] + section[5], section[9]):
        name, value, _, _, _, _ = struct.unpack_from('<IIIBBH', data, offset)
        end = strings.find(b'\0', name)
        symbols[strings[name:end].decode('ascii', errors='replace')] = value
for name, address in manifest['symbols'].items():
    if symbols.get(name) != int(address, 16):
        raise SystemExit(f'Symbol mismatch: {name}')
print(json.dumps({'sha256': manifest['sha256'], 'architecture': 'ELF32 i386', 'symbols_verified': manifest['symbols']}, indent=2))
