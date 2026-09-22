#!/usr/bin/env python3
"""Restore only the small state artifact produced by this trusted workflow on main."""
import io,json,os,pathlib,subprocess,zipfile
repo=os.environ['GITHUB_REPOSITORY']
if repo!='haider0708/bio-balance-app':raise SystemExit('Unexpected repository')
def gh(route,binary=False):
    out=subprocess.run(['gh','api',route],check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=30).stdout
    if len(out)>2*1024*1024:raise ValueError('Oversized GitHub response')
    return out if binary else json.loads(out)
artifacts=gh(f'repos/{repo}/actions/artifacts?name=ops-monitor-state&per_page=20')['artifacts']
for artifact in sorted(artifacts,key=lambda x:x['id'],reverse=True):
    if artifact['expired']:continue
    run=gh(f'repos/{repo}/actions/runs/{artifact["workflow_run"]["id"]}')
    if run['path']!='.github/workflows/operations-monitor.yml' or run['head_branch']!='main' or run['event'] not in {'schedule','workflow_dispatch'}:continue
    if artifact['size_in_bytes']>65536:raise ValueError('Oversized state artifact')
    archive=zipfile.ZipFile(io.BytesIO(gh(f'repos/{repo}/actions/artifacts/{artifact["id"]}/zip',True)))
    items=archive.infolist()
    if len(items)!=1 or items[0].filename!='state.json' or items[0].file_size>4096:raise ValueError('Unexpected state archive')
    content=archive.read(items[0]);json.loads(content)
    pathlib.Path('.monitor').mkdir(exist_ok=True);pathlib.Path('.monitor/state.json').write_bytes(content)
    print('Previous monitoring state restored');break
else:print('First independent monitoring run')
