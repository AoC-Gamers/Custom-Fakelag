"""Summarize observer records without treating pointer readability as validity."""
import argparse, json
from pathlib import Path

def summarize(paths):
    result={'records':0,'identified_snapshots':0,'events':{},'fields':{},
        'limits':'Snapshots are non-atomic. Outside-module fields do not alone prove a freed object or crash cause.'}
    parent=None
    for path in paths:
        for line in path.read_text(encoding='utf-8').splitlines():
            row=dict(token.split('=',1) for token in line.split())
            result['records']+=1
            event=row.get('event','unknown')
            result['events'][event]=result['events'].get(event,0)+1
            if event!='context_field':
                parent={k:row[k] for k in ('event','unix','elapsed_ms','seq','sv_lan','context','identified') if k in row}
                if row.get('identified')=='1': result['identified_snapshots']+=1
                continue
            offset=row['offset']
            item=result['fields'].setdefault(offset,{'first_steam_chain':None,'first_nonsteam_after_steam_chain':None,'last':None})
            sample={k:row[k] for k in ('unix','elapsed_ms','seq','offset','object','vtable','method','reads','vtable_in_steam','method_in_steam','method_executable')}
            sample['parent_snapshot']=parent
            healthy=all(row[key]=='1' for key in ('vtable_in_steam','method_in_steam','method_executable')) and row['reads']=='7'
            if healthy and item['first_steam_chain'] is None: item['first_steam_chain']=sample
            if not healthy and item['first_steam_chain'] and item['first_nonsteam_after_steam_chain'] is None:
                item['first_nonsteam_after_steam_chain']=sample
            item['last']=sample
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('paths',nargs='+',type=Path)
    a=p.parse_args();print(json.dumps(summarize(a.paths),indent=2))
