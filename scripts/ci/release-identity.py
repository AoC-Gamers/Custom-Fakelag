import argparse, os, re
p=argparse.ArgumentParser();p.add_argument('--platform',choices=['linux','windows'],required=True);a=p.parse_args()
ref=os.environ.get('GITHUB_REF_NAME','local');sha=os.environ.get('GITHUB_SHA','local')
if ref in ('main','master'): channel,tag,title,pre='latest','channel/latest','Latest','false'
elif ref=='develop': channel,tag,title,pre='develop','channel/develop','Develop','true'
elif os.environ.get('GITHUB_REF_TYPE')=='tag' and re.fullmatch(r'v\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?',ref): channel,tag,title,pre=ref[1:],ref,ref,'false'
else: channel,tag,title,pre=sha[:7],'','','false'
if not re.fullmatch(r'[a-zA-Z0-9.-]+',channel):raise ValueError('Invalid channel')
values={'basename':f'custom-fakelag-{channel}-{a.platform}','release_tag':tag,'release_name':title,'prerelease':pre}
text=''.join(f'{k}={v}\n' for k,v in values.items())
if os.environ.get('GITHUB_OUTPUT'):
 with open(os.environ['GITHUB_OUTPUT'],'a') as f:f.write(text)
else:print(text,end='')
