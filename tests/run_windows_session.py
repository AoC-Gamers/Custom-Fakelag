import argparse,json,time
from pathlib import Path
from windows_console import WindowsConsole
p=argparse.ArgumentParser(description='Owned isolated native Windows SRCDS console session');p.add_argument('--srcds',type=Path,required=True);p.add_argument('--game',type=Path,required=True);p.add_argument('--commands',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--ip',default='127.0.0.1');p.add_argument('--port',type=int,default=27025);a=p.parse_args()
if not(a.game/'.custom-fakelag-isolated').is_file():p.error('Private gamedir marker required')
if a.commands.exists() and a.commands.read_text().strip():p.error('Use an empty command file; mutations are never replayed')
a.commands.touch();root=a.srcds.resolve().parent
import os
c=WindowsConsole([str(a.srcds.resolve()),'-console','-condebug','-insecure','-ip',a.ip,'-port',str(a.port),'-game',os.path.relpath(a.game.resolve(),root),'+map','c1m1_hotel'],str(root));a.output.write_text(json.dumps({'pid':c.process.pid,'state':'running'})+'\n');offset=0
try:
 while c.process.poll() is None:
  text=a.commands.read_text();pending=text[offset:];offset=len(text)
  for line in pending.splitlines():
   if line.strip():
    c.command(line);time.sleep(.5)
    with a.output.open('a') as log:log.write(json.dumps({'command':line,'time':time.monotonic(),'console':c.read_output()})+'\n')
  time.sleep(.1)
finally:
 with a.output.open('a') as log:log.write(json.dumps({'state':'stopped','exit_code':c.process.poll()})+'\n')
 c.close()
