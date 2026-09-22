#!/usr/bin/env python3
"""Fixed read-only root command for the restricted external monitoring key."""
import datetime,json,os,pathlib,subprocess,time

def command(argv, timeout=10):
    return subprocess.run(argv,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=timeout,check=False,text=True).stdout.strip()

def main():
    problems=[]
    stat=os.statvfs('/srv/biobalance-backups');free=stat.f_bavail*stat.f_frsize;total=stat.f_blocks*stat.f_frsize
    used=round((1-stat.f_bfree/stat.f_blocks)*100,1)
    if used>=85 or free<10*1024**3:problems.append('DISK_LOW')
    mem={line.split(':')[0]:int(line.split()[1]) for line in pathlib.Path('/proc/meminfo').read_text().splitlines() if len(line.split())>=2 and line.split()[1].isdigit()}
    if mem['MemAvailable']/mem['MemTotal']<.10:problems.append('MEMORY_LOW')
    if os.getloadavg()[1]>(os.cpu_count() or 1)*1.5:problems.append('CPU_HIGH')
    for unit,code in [('biobalance-backup.timer','BACKUP_TIMER'),('biobalance-monitor.timer','MONITOR_TIMER')]:
        if command(['/usr/bin/systemctl','is-active',unit])!='active':problems.append(code)
    for unit,code in [('biobalance-backup.service','BACKUP_FAILED'),('biobalance-monitor.service','LOCAL_CHECK_FAILED')]:
        props=command(['/usr/bin/systemctl','show',unit,'--property=Result,ActiveEnterTimestamp,InactiveEnterTimestamp,ActiveState,ExecMainStartTimestamp,ExecMainExitTimestamp'])
        data=dict(x.split('=',1) for x in props.splitlines() if '=' in x)
        if data.get('Result')!='success':problems.append(code)
        # Local monitor must actually have finished recently; enabled alone is insufficient.
        if unit=='biobalance-monitor.service':
            stamp=data.get('ExecMainExitTimestamp','')
            try:
                seconds=float(command(['/usr/bin/date','--date='+stamp,'+%s']))
                if time.time()-seconds>300:problems.append('MONITOR_STALE')
            except (ValueError,subprocess.SubprocessError):problems.append('MONITOR_STALE')
    completed=[p.stat().st_mtime for p in pathlib.Path('/srv/biobalance-backups').glob('*/SHA256SUMS') if p.is_file() and not p.is_symlink()]
    backup_age=int(time.time()-max(completed)) if completed else None
    if backup_age is None or backup_age>26*3600:problems.append('BACKUP_STALE')
    report={'schemaVersion':1,'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'problems':sorted(set(problems)),'diskUsedPercent':used,'diskFreeBytes':free,'backupAgeSeconds':backup_age,'rebootRequired':pathlib.Path('/var/run/reboot-required').exists()}
    print(json.dumps(report))
if __name__=='__main__':
    try:main()
    except Exception:
        print(json.dumps({'schemaVersion':1,'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'problems':['REPORT_FAILED']}))
