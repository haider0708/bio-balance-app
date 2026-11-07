#!/usr/bin/env python3
"""Fixed read-only root command for the restricted external monitoring key."""
import datetime,json,os,pathlib,subprocess,time

def command(argv, timeout=10):
    return subprocess.run(argv,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,timeout=timeout,check=False,text=True).stdout.strip()

def epoch(stamp):
    return float(command(['/usr/bin/date','--date='+stamp,'+%s']))

def monitor_stale(data, now, parse):
    """The local check has not run for 5 minutes. While it runs (a second a minute) systemd shows
    no exit time ("n/a"), so a run in progress is judged by when it started, not by the last exit."""
    running=data.get('ActiveState') in ('activating','active','reloading')
    stamp=data.get('ExecMainStartTimestamp' if running else 'ExecMainExitTimestamp','')
    try:return now-parse(stamp)>300
    except (ValueError,subprocess.SubprocessError):return True

def messaging_problems(data):
    """What the messaging check (scripts/check-messaging.sh) found, from its exit status:
    bit 1 = the WhatsApp session is down, bit 2 = messages failed for good, anything else = the check could not run."""
    if data.get('Result')=='success':return []
    try:status=int(data.get('ExecMainStatus',''))
    except ValueError:return ['MESSAGING_CHECK_FAILED']
    if status<=0 or status>3:return ['MESSAGING_CHECK_FAILED']
    return (['WHATSAPP_DOWN'] if status&1 else [])+(['JOBS_FAILED'] if status&2 else [])

def main():
    problems=[]
    stat=os.statvfs('/srv/biobalance-backups');free=stat.f_bavail*stat.f_frsize;total=stat.f_blocks*stat.f_frsize
    used=round((1-stat.f_bfree/stat.f_blocks)*100,1)
    if used>=85 or free<10*1024**3:problems.append('DISK_LOW')
    mem={line.split(':')[0]:int(line.split()[1]) for line in pathlib.Path('/proc/meminfo').read_text().splitlines() if len(line.split())>=2 and line.split()[1].isdigit()}
    if mem['MemAvailable']/mem['MemTotal']<.10:problems.append('MEMORY_LOW')
    if os.getloadavg()[1]>(os.cpu_count() or 1)*1.5:problems.append('CPU_HIGH')
    for unit,code in [('biobalance-backup.timer','BACKUP_TIMER'),('biobalance-monitor.timer','MONITOR_TIMER'),('biobalance-messaging.timer','MESSAGING_TIMER'),('biobalance-tls.timer','TLS_TIMER')]:
        if command(['/usr/bin/systemctl','is-active',unit])!='active':problems.append(code)
    for unit,code in [('biobalance-backup.service','BACKUP_FAILED'),('biobalance-monitor.service','LOCAL_CHECK_FAILED'),('biobalance-tls.service','TLS_RENEWAL_FAILED')]:
        props=command(['/usr/bin/systemctl','show',unit,'--property=Result,ActiveEnterTimestamp,InactiveEnterTimestamp,ActiveState,ExecMainStartTimestamp,ExecMainExitTimestamp'])
        data=dict(x.split('=',1) for x in props.splitlines() if '=' in x)
        if data.get('Result')!='success':problems.append(code)
        # Local monitor must actually have finished recently; enabled alone is insufficient.
        if unit=='biobalance-monitor.service' and monitor_stale(data,time.time(),epoch):problems.append('MONITOR_STALE')
    props=command(['/usr/bin/systemctl','show','biobalance-messaging.service','--property=Result,ExecMainStatus'])
    problems+=messaging_problems(dict(x.split('=',1) for x in props.splitlines() if '=' in x))
    completed=[p.stat().st_mtime for p in pathlib.Path('/srv/biobalance-backups').glob('*/SHA256SUMS') if p.is_file() and not p.is_symlink()]
    backup_age=int(time.time()-max(completed)) if completed else None
    if backup_age is None or backup_age>26*3600:problems.append('BACKUP_STALE')
    report={'schemaVersion':1,'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'problems':sorted(set(problems)),'diskUsedPercent':used,'diskFreeBytes':free,'backupAgeSeconds':backup_age,'rebootRequired':pathlib.Path('/var/run/reboot-required').exists()}
    print(json.dumps(report))
if __name__=='__main__':
    try:main()
    except Exception:
        print(json.dumps({'schemaVersion':1,'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'problems':['REPORT_FAILED']}))
