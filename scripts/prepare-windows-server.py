"""Mount existing immutable L4D2 assets by hardlink into an isolated Windows server.
Binaries/addons/config and writable navigation/cache files are never linked.
Download the Windows binaries/bootstrap from Steam first; this script downloads nothing.
"""
import argparse,json,os,shutil
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--client',type=Path,required=True);p.add_argument('--server',type=Path,required=True);a=p.parse_args();src=a.client.resolve(strict=True);dst=a.server.resolve(strict=True)
if os.name!='nt' or src==dst or dst.is_relative_to(src) or src.is_relative_to(dst):p.error('Use separate Windows directories on the same volume')
if not(dst/'srcds.exe').is_file():p.error('Missing dedicated server executable')
rows=[]
games=['left4dead2','update','left4dead2_dlc1','left4dead2_dlc2','left4dead2_dlc3','hl2']
content={'sound','scenes','models','materials','scripts','missions','resource','particles','expressions','gfx','modes'}
for game in games:
 s=src/game;d=dst/game;d.mkdir(exist_ok=True)
 assets=list(s.glob('*.vpk'))+list((s/'maps').glob('*.bsp'))+list((s/'maps').glob('*.txt'))
 for sub in content:
  assets.extend(f for f in (s/sub).rglob('*') if f.is_file() and f.suffix.lower() not in {'.cache','.lst','.log','.tmp','.nav','.ain'})
 for f in assets:
  target=d/f.relative_to(s)
  if not target.resolve().is_relative_to(dst):p.error('Asset destination escapes private server')
  target.parent.mkdir(parents=True,exist_ok=True)
  if not target.exists():os.link(f,target)
  if os.path.samefile(f,target):rows.append({'source':str(f),'destination':str(target),'bytes':f.stat().st_size,'mtime_ns':f.stat().st_mtime_ns})
 for f in (s/'maps').glob('*.nav'):
  target=d/f.relative_to(s)
  if not target.resolve().is_relative_to(dst):p.error('Asset destination escapes private server')
  target.parent.mkdir(parents=True,exist_ok=True)
  if not target.exists():shutil.copy2(f,target)
(dst/'left4dead2/.custom-fakelag-isolated').touch()
result={'method':'hardlinks to immutable assets; private configs/addons/binaries/nav','linked_files':len(rows),'linked_logical_bytes':sum(r['bytes'] for r in rows),'files':rows}
(dst/'.custom-fakelag-resources.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k!='files'}))
