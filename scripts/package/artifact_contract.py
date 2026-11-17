"""Shared installer contract. No SDK, report, or undeclared file is installable."""
import json
import struct
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]


def relative(name):
    p = PurePosixPath(name)
    if p.is_absolute() or '\\' in name or any(x in ('', '.', '..') for x in name.split('/')):
        raise ValueError(f'Unsafe path: {name}')
    return p


def inventory(platform):
    manifest = json.loads((ROOT / 'scripts/package/package-map.json').read_text())
    if set(manifest) != {'build', 'artifact', 'documentation'}:
        raise ValueError('Unknown or missing manifest keys')
    if manifest['build'] != {'plugins': {'root': ['player_fakelag']}, 'extensions': {'root': ['custom_fakelag']}}:
        raise ValueError('Unsupported build inventory')
    expected_sections = {'plugins', 'extensions', 'scripting', 'translations', 'gamedata'}
    if set(manifest['artifact']) != {'addons'} or set(manifest['artifact']['addons']) != {'sourcemod'} or set(manifest['artifact']['addons']['sourcemod']) != expected_sections:
        raise ValueError('Unknown artifact section')
    paths = set()
    allowed_nodes = {'', 'addons/', 'addons/sourcemod/', 'addons/sourcemod/plugins/', 'addons/sourcemod/extensions/', 'addons/sourcemod/scripting/', 'addons/sourcemod/scripting/include/', 'addons/sourcemod/translations/', 'addons/sourcemod/gamedata/'}
    def visit(node, prefix=''):
        if prefix not in allowed_nodes:
            raise ValueError(f'Unknown artifact node {prefix}')
        for key, value in node.items():
            if key == 'files':
                for name in value:
                    path = str(relative(prefix + name))
                    if path.endswith(('.dll', '.so')) and not path.endswith('.dll' if platform == 'windows' else '.so'):
                        continue
                    paths.add(path)
            elif key == 'all':
                if value is not True or prefix not in ('addons/sourcemod/gamedata/', 'addons/sourcemod/translations/'):
                    raise ValueError('Unsupported all selector')
                for f in (ROOT / prefix).rglob('*'):
                    if f.is_file(): paths.add(f.relative_to(ROOT).as_posix())
            elif isinstance(value, dict):
                relative(key)
                visit(value, prefix + key + '/')
            else:
                raise ValueError(f'Unknown manifest selector {key}')
    visit(manifest['artifact'])
    paths.update(str(relative(x)) for x in manifest['documentation'])
    if len({x.casefold() for x in paths}) != len(paths):
        raise ValueError('Case collision')
    return paths


def validate(files, platform):
    expected = inventory(platform)
    if set(files) != expected:
        raise ValueError(f'Artifact mismatch: missing={sorted(expected-set(files))}, extra={sorted(set(files)-expected)}')
    for name, data in files.items():
        relative(name)
        if name.endswith('.so'):
            if data[:5] != b'\x7fELF\x01' or data[5:6] != b'\x01' or struct.unpack_from('<H', data, 18)[0] != 3:
                raise ValueError('Expected ELF32 i386')
        if name.endswith('.dll'):
            if data[:2] != b'MZ' or len(data) < 64: raise ValueError('Expected PE32')
            offset = struct.unpack_from('<I', data, 60)[0]
            if data[offset:offset+4] != b'PE\0\0' or struct.unpack_from('<H', data, offset+4)[0] != 0x14c or struct.unpack_from('<H', data, offset+24)[0] != 0x10b:
                raise ValueError('Expected PE32 i386')


def tree_files(tree):
    files = {}
    for f in tree.rglob('*'):
        if f.is_symlink(): raise ValueError(f'Symlink: {f}')
        if f.is_file(): files[f.relative_to(tree).as_posix()] = f.read_bytes()
        elif not f.is_dir(): raise ValueError(f'Special file: {f}')
    return files
