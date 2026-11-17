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


ALLOWED_NODES = {'', 'addons/', 'addons/sourcemod/', 'addons/sourcemod/plugins/',
                 'addons/sourcemod/extensions/', 'addons/sourcemod/scripting/',
                 'addons/sourcemod/scripting/include/', 'addons/sourcemod/translations/',
                 'addons/sourcemod/gamedata/'}


def validate_manifest(manifest):
    if set(manifest) != {'build', 'artifact', 'documentation'}:
        raise ValueError('Unknown or missing manifest keys')
    if manifest['build'] != {'plugins': {'root': ['player_fakelag']}, 'extensions': {'root': ['custom_fakelag']}}:
        raise ValueError('Unsupported build inventory')
    artifact = manifest['artifact']
    if set(artifact) != {'addons'} or set(artifact['addons']) != {'sourcemod'}:
        raise ValueError('Unknown artifact section')
    expected = {'plugins', 'extensions', 'scripting', 'translations', 'gamedata'}
    if set(artifact['addons']['sourcemod']) != expected:
        raise ValueError('Unknown artifact section')


def selected_files(prefix, names, platform):
    suffix = '.dll' if platform == 'windows' else '.so'
    for name in names:
        path = str(relative(prefix + name))
        if path.endswith(('.dll', '.so')) and not path.endswith(suffix):
            continue
        yield path


def all_children(prefix, enabled):
    if enabled is not True or prefix not in ('addons/sourcemod/gamedata/', 'addons/sourcemod/translations/'):
        raise ValueError('Unsupported all selector')
    return {f.relative_to(ROOT).as_posix() for f in (ROOT / prefix).rglob('*') if f.is_file()}


def manifest_paths(node, platform, prefix=''):
    if prefix not in ALLOWED_NODES:
        raise ValueError(f'Unknown artifact node {prefix}')
    paths = set()
    for key, value in node.items():
        if key == 'files':
            paths.update(selected_files(prefix, value, platform))
        elif key == 'all':
            paths.update(all_children(prefix, value))
        elif isinstance(value, dict):
            relative(key)
            paths.update(manifest_paths(value, platform, prefix + key + '/'))
        else:
            raise ValueError(f'Unknown manifest selector {key}')
    return paths


def inventory(platform):
    manifest = json.loads((ROOT / 'scripts/package/package-map.json').read_text())
    validate_manifest(manifest)
    paths = manifest_paths(manifest['artifact'], platform)
    paths.update(str(relative(x)) for x in manifest['documentation'])
    if len({x.casefold() for x in paths}) != len(paths):
        raise ValueError('Case collision')
    return paths


def validate_elf(data):
    if len(data) < 20 or data[:6] != b'\x7fELF\x01\x01':
        raise ValueError('Expected ELF32 i386')
    if struct.unpack_from('<H', data, 18)[0] != 3:
        raise ValueError('Expected ELF32 i386')


def validate_pe(data):
    if len(data) < 64 or data[:2] != b'MZ':
        raise ValueError('Expected PE32')
    offset = struct.unpack_from('<I', data, 60)[0]
    if offset + 26 > len(data) or data[offset:offset+4] != b'PE\0\0':
        raise ValueError('Expected PE32 i386')
    if struct.unpack_from('<H', data, offset+4)[0] != 0x14c or struct.unpack_from('<H', data, offset+24)[0] != 0x10b:
        raise ValueError('Expected PE32 i386')


def validate(files, platform):
    expected = inventory(platform)
    if set(files) != expected:
        raise ValueError(f'Artifact mismatch: missing={sorted(expected-set(files))}, extra={sorted(set(files)-expected)}')
    for name, data in files.items():
        relative(name)
        if name.endswith('.so'):
            validate_elf(data)
        elif name.endswith('.dll'):
            validate_pe(data)


def tree_files(tree):
    files = {}
    for f in tree.rglob('*'):
        if f.is_symlink(): raise ValueError(f'Symlink: {f}')
        if f.is_file(): files[f.relative_to(tree).as_posix()] = f.read_bytes()
        elif not f.is_dir(): raise ValueError(f'Special file: {f}')
    return files
