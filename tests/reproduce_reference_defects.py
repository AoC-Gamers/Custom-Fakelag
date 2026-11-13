#!/usr/bin/env python3
"""Reproduce the three reference defects in isolated executables, never in SRCDS."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--reference', default='430872d40dcafa3dc41c21a707a7523b8db64524')
parser.add_argument('--arch', choices=['native', '32'], default='32')
args = parser.parse_args()
output = ROOT / '.build/reference-defects'
output.mkdir(parents=True, exist_ok=True)
deps = Path(os.environ.get('DEPS_DIR', ROOT / '.deps/exts-linux')).resolve()
files = [
    'extension/network/net_structures.h', 'extension/network/LagSystem.h',
    'extension/network/LagSystem.cpp', 'extension/latency/PlayerLagManager.h',
    'extension/latency/PlayerLagManager.cpp', 'extension/network/LagPacketPolicy.cpp',
]
for name in files:
    dest = output / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(subprocess.check_output(['git', 'show', f'{args.reference}:{name}'], cwd=ROOT))
(output / 'copy.cpp').write_text('''#include "extension/network/net_structures.h"
int main() { _netpacket_t a, b; a.size=b.size=4; a.data=new unsigned char[4]; b.data=new unsigned char[4]; a=b; }
''')
# Extract the actual reference arithmetic; this is not the full policy callback.
policy = (output / files[-1]).read_text()
expression = '(packetLossPercent * kExitBadProbability) / (100 - packetLossPercent)'
if expression not in policy:
    raise SystemExit('Reference loss formula differs; inspect before reproducing.')
(output / 'loss.cpp').write_text('int main() { volatile int packetLossPercent=100; const int kExitBadProbability=5000; return ' + expression + '; }\n')
(output / 'reset.cpp').write_text('''#include "extension/network/LagSystem.h"
#include "extension/latency/PlayerLagManager.h"
#include <cstdio>
struct Resolver : IClientNetAdrResolver {
 bool TryResolveClientNetAdr(int, dumb_netadr_t* addr) const override { *addr={}; return true; }
};
int main() {
 double time=1; LagSystem queue(&time); Resolver resolver; PlayerLagManager profiles(&resolver);
 profiles.SetPlayerLag(1,100);
 _netpacket_t p; p.size=4; p.data=new unsigned char[4]; p.received=1;
 queue.LagPacket(&p,100); profiles.ClearAll();
 std::printf("profiles=%zu queue=%zu\\n", profiles.GetLagCount(), queue.GetQueueDepth(0));
 return profiles.GetLagCount()==0 && queue.GetQueueDepth(0)==1 ? 0 : 1;
}
''')
flags = ['-std=c++17', '-g', '-fsanitize=address,undefined', '-fno-sanitize-recover=all']
if args.arch == '32':
    flags += ['-m32']
flags += ['-D' + macro for macro in ['UNIT_TEST', '_LINUX', 'POSIX', 'LINUX', 'GNUC', 'COMPILER_GCC', 'stricmp=strcasecmp', '_stricmp=stricmp']]
flags += ['-I' + str(deps / path) for path in ['hl2sdk-l4d2/public', 'hl2sdk-l4d2/public/tier1', 'hl2sdk-l4d2/public/tier0', 'hl2sdk-l4d2/public/mathlib', 'sourcemod-1.12/public/amtl']]
results = {}
for case in ['copy', 'loss', 'reset']:
    sources = [output / f'{case}.cpp']
    if case == 'reset':
        sources += [output / files[2], output / files[4]]
    executable = output / case
    command = [os.environ.get('CXX', 'g++'), *flags, *map(str, sources), '-o', str(executable)]
    with (output / f'{case}.log').open('w') as log:
        log.write(shlex.join(command) + '\n')
        log.flush()
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=log, check=True)
        result = subprocess.run([str(executable)], stdout=log, stderr=log)
    evidence = (output / f'{case}.log').read_text()
    expected = {'copy': 'double-free', 'loss': 'division by zero', 'reset': 'profiles=0 queue=1'}[case]
    ok = expected in evidence and ((result.returncode != 0) if case != 'reset' else result.returncode == 0)
    results[case] = {'exit': result.returncode, 'expected_evidence': expected, 'reproduced': ok}
    print(f'{case}: {results[case]}')
(output / 'results.json').write_text(json.dumps({'reference': args.reference, 'architecture': args.arch, 'cases': results}, indent=2) + '\n')
if not all(result['reproduced'] for result in results.values()):
    raise SystemExit('A reference defect did not reproduce; inspect logs.')
