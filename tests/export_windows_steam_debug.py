"""Allowlist export of private Steam diagnostic trials. Never exports consoles."""
import argparse, hashlib, json, re, shutil
from pathlib import Path

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def modules(observation):
    return [{k:m[k] for k in ('name','base','bytes','sha256') if k in m}
            for m in observation.get('modules',[])]

def export(source, destination):
    data=json.loads((source/'state.json').read_text(encoding='utf-8'))
    allowed=('id','row','sv_lan','base','started','finished','source_revision',
        'collector_source_sha256','diagnostic_sha256','runtime_sha256','forced_termination',
        'debugger','preflight','cfg_sha256','original_cfg_sha256','cfg_only_sv_lan_changed',
        'activity_definition','fixed_hashes','server_pid','collector_pid','effective_components',
        'observer_mode','quit_requested','supervisor_quit_requested','server_exit_code',
        'server_exit_hex','win32_exit_code','process_handle_signaled','exit_codes_agree',
        'collector_error','state','registry_window_seconds')
    clean={k:data[k] for k in allowed if k in data}
    clean['registry_restored_exactly']=data.get('registry_original')==data.get('registry_restored')
    clean['loaded_modules']=modules(data.get('ready_observation',{}))
    clean['runtime_loaded']={k:data.get('runtime_loaded',{}).get(k) for k in ('name','base','bytes')}
    clean['events']=[]
    for event in data['events']:
        selected={k:v for k,v in event.items() if k not in ('console','observation','userid')}
        if selected.get('command','') and selected['command'].startswith('kickid '):
            selected['command']='kickid <current-userid> private_steam_lifecycle_trial'
        if 'observation' in event: selected['modules']=modules(event['observation'])
        clean['events'].append(selected)
    clean['raw_private_evidence']={p.name:{'sha256':sha(p),'bytes':p.stat().st_size}
        for p in source.iterdir() if p.is_file() and p.suffix not in ('.tmp',)}
    clean['limits']=['No console or player identity exported.',
        'A process exit code alone does not identify exception operation/address.',
        'Diagnostic snapshots are non-atomic and do not prove allocation lifetime.']
    destination.mkdir(parents=True,exist_ok=False)
    clean['diagnostic_logs']=[]
    for name in ('trace.log','trace.log.1'):
        path=source/name
        if not path.exists(): continue
        text=path.read_text(encoding='utf-8')
        assert not re.search(r'STEAM_|\[U:|(?:\d{1,3}\.){3}\d{1,3}|(?i:password|token|userid|playername)',text)
        assert all(re.fullmatch(r'unix=\d+ elapsed_ms=\d+ seq=\d+ [a-zA-Z0-9_= .]+',line) for line in text.splitlines())
        shutil.copy2(path,destination/name)
        clean['diagnostic_logs'].append({'name':name,'sha256':sha(path),'bytes':path.stat().st_size})
    encoded=json.dumps(clean,indent=2)
    assert not re.search(r'STEAM_[01]:|\[U:|(?:\d{1,3}\.){3}\d{1,3}',encoded)
    (destination/'trial.json').write_text(encoded+'\n',encoding='utf-8')
    return clean

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path)
    a=p.parse_args();result=export(a.source,a.destination);print(json.dumps({'id':result['id'],'exported':True}))
