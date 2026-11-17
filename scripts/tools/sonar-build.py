"""Capture actual compiler invocations in an isolated native build (AMBuild 2.1)."""
import argparse,json,os,shlex,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
out=a.output.resolve()
if ROOT/'.build' not in out.parents:raise ValueError('Expected managed .build output')
# Native backend cleans only this build. Keep capture wrappers alongside it.
wrappers=out.parent/(out.name+'-capture');wrappers.mkdir(parents=True,exist_ok=True)
log=wrappers/'commands.jsonl';log.write_text('')
env={k:v for k,v in os.environ.items() if not k.startswith('SONAR_')}
for variable,default in [('CC','gcc'),('CXX','g++')]:
 compiler=shlex.split(env.get(variable,default))
 compiler[0]=shutil.which(compiler[0]) or compiler[0]
 wrapper=wrappers/variable.lower()
 wrapper.write_text('#!'+sys.executable+'\n'+'''import fcntl,json,os,subprocess,sys
from pathlib import Path
command='''+repr(compiler)+'''+sys.argv[1:]
if '-c' in command:
 sources=[str(Path(x).resolve()) for x in command if not x.startswith('-') and Path(x).suffix in ('.c','.cpp') and Path(x).is_file()]
 for source in sources:
  with open('''+repr(str(log))+''','a') as f:
   fcntl.flock(f,fcntl.LOCK_EX)
   f.write(json.dumps({'directory':os.getcwd(),'file':source,'arguments':command})+'\\n')
raise SystemExit(subprocess.call(command))
''')
 wrapper.chmod(0o755);env[variable]=str(wrapper)
subprocess.run(['make','--no-print-directory','-f',str(ROOT/'Makefile'),'build-exts-linux','LINUX_BUILD_DIR='+str(out)],cwd=ROOT,env=env,check=True)
subprocess.run(['make','--no-print-directory','-f',str(ROOT/'Makefile'),'test-diagnostic-linux'],cwd=ROOT,env=env,check=True)
entries=[json.loads(x) for x in log.read_text().splitlines()]
if not entries:raise ValueError('No actual compiler invocations captured')
(out/'compile_commands.json').write_text(json.dumps(entries,indent=2)+'\n')
print('Captured',len(entries),'actual compilation commands')
