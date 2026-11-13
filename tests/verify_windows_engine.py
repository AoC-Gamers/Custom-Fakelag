#!/usr/bin/env python3
"""Offline PE identity, gamedata uniqueness, operands and contract disassembly.

Requires pefile 2024.8.26 and capstone 5.0.9. Never executes the supplied DLL.
Matching a client DLL does not establish what a dedicated server loads.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import pefile
import capstone

ROOT = Path(__file__).resolve().parents[1]


def scan(data, pattern):
    # SourceMod uses byte 0x2a as a wildcard, not as a literal star.
    expression = b''.join(b'.' if byte == 0x2a else re.escape(bytes([byte])) for byte in pattern)
    return [match.start() for match in re.finditer(b'(?=(' + expression + b'))', data, re.S)]


def verify(path):
    manifest = json.loads((ROOT / 'docs/runtime/windows-engine-2.2.4.3.json').read_text())
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != manifest['sha256']:
        raise ValueError('Unsupported SHA-256; no compatibility inferred')
    pe = pefile.PE(data=data)
    if pe.FILE_HEADER.Machine != 0x14c or pe.OPTIONAL_HEADER.Magic != 0x10b:
        raise ValueError('Expected PE32 I386')
    if pe.OPTIONAL_HEADER.SizeOfImage != int(manifest['size_of_image'], 16):
        raise ValueError('Unexpected image size')
    gamedata = (ROOT / 'gamedata/custom_fakelag.games.txt').read_text()
    patterns = re.findall(r'"windows"\s+"((?:\\x[0-9A-Fa-f]{2})+)"', gamedata)
    if len(patterns) != 2:
        raise ValueError('Unexpected gamedata signatures')
    matches = {}
    for name, encoded in zip(('NET_LagPacket', 'net_time'), patterns):
        pattern = bytes.fromhex(encoded.replace('\\x', ''))
        hits = scan(data, pattern)
        expected = int(manifest['signatures'][name]['rva'], 16)
        if len(hits) != 1 or pe.get_rva_from_offset(hits[0]) != expected:
            raise ValueError(f'Ambiguous or moved signature: {name}')
        section = pe.get_section_by_rva(expected)
        if not section or not section.Characteristics & 0x20000000:
            raise ValueError('Signature is outside executable section')
        matches[name] = {'count': 1, 'rva': hex(expected), 'section': section.Name.decode().strip('\0')}
    operand = struct.unpack('<I', pe.get_data(0x1c9d6c, 4))[0]
    if operand - pe.OPTIONAL_HEADER.ImageBase != int(manifest['symbols']['net_time'], 16):
        raise ValueError('Unexpected net_time effective operand')
    disassembler = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    excerpts = {}
    for name, span in manifest['evidence_ranges'].items():
        rva, size = (int(value, 16) for value in span)
        excerpts[name] = [{'rva': hex(ins.address - pe.OPTIONAL_HEADER.ImageBase),
                           'bytes': ins.bytes.hex(), 'instruction': f'{ins.mnemonic} {ins.op_str}'.strip()}
                          for ins in disassembler.disasm(pe.get_data(rva, size), pe.OPTIONAL_HEADER.ImageBase + rva)]
    return {'status': 'passed', 'kind': 'offline static analysis; not SRCDS', 'path': str(path.resolve()),
            'sha256': digest, 'pe_machine': 'I386', 'format': 'PE32',
            'timestamp': hex(pe.FILE_HEADER.TimeDateStamp), 'size_of_image': hex(pe.OPTIONAL_HEADER.SizeOfImage),
            'preferred_base': hex(pe.OPTIONAL_HEADER.ImageBase), 'signatures': matches,
            'net_time_preferred_va': hex(operand), 'excerpts': excerpts,
            'tools': {'pefile': pefile.__version__, 'capstone': capstone.__version__}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('module', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        result = verify(args.module)
    except (ValueError, pefile.PEFormatError) as error:
        parser.exit(1, f'{error}\n')
    encoded = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.write_text(encoded)
    else:
        print(encoded, end='')
