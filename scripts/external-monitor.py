#!/usr/bin/env python3
"""Independent HTTPS + restricted SSH check, incident deduplication and TLS email."""
import argparse,datetime,hashlib,json,os,pathlib,re,smtplib,ssl,subprocess,time,urllib.request
from email.message import EmailMessage

CODES={
 'API_UNREACHABLE':'API HTTPS indisponible', 'HOST_UNREACHABLE':'Contrôle du serveur inaccessible',
 'DISK_LOW':'Espace disque faible', 'MEMORY_LOW':'Mémoire disponible faible', 'CPU_HIGH':'Charge CPU élevée',
 'BACKUP_TIMER':'Planification des sauvegardes inactive','MONITOR_TIMER':'Planification des contrôles inactive',
 'BACKUP_FAILED':'Échec de sauvegarde','LOCAL_CHECK_FAILED':'Échec du contrôle local (services, jobs, sauvegardes ou certificat)',
 'MONITOR_STALE':'Contrôle local trop ancien','BACKUP_STALE':'Aucune sauvegarde récente','REPORT_FAILED':'Rapport du serveur invalide',
}
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None

def decide(previous, problems, now, diagnostic=False):
    """Only commit returned state after successful SMTP; failed sends remain retryable."""
    current=sorted(set(problems)); old=previous.get('incident',[]); last=previous.get('sentAt',0)
    state={'version':1,'incident':old,'sentAt':last,'healthyCount':0,'checkedAt':now}
    kind=None
    if current:
        if current!=old or now-last>=6*3600:kind='incident'
    elif old:
        state['healthyCount']=min(2,previous.get('healthyCount',0)+1)
        if state['healthyCount']>=2:kind='recovery'
    if diagnostic and kind is None:kind='diagnostic'
    if kind:
        state.update(incident=current if kind!='diagnostic' else old,sentAt=now if kind!='diagnostic' else last)
    return kind,state

def check_host():
    try:
        result=subprocess.run(['ssh','-F','/dev/null','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ConnectionAttempts=1','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile='+os.environ['MONITOR_KNOWN_HOSTS'],'-i',os.environ['MONITOR_SSH_KEY'],'biobalance-monitor@146.59.195.61','report'],capture_output=True,timeout=25,check=True)
        if len(result.stdout)>16384:raise ValueError('Oversized report')
        report=json.loads(result.stdout)
        age=time.time()-datetime.datetime.fromisoformat(report['checkedAt']).timestamp()
        if report['schemaVersion']!=1 or not -60<age<180:raise ValueError('Stale report')
        codes=report['problems']
        if not isinstance(codes,list) or any(c not in CODES for c in codes):raise ValueError('Invalid codes')
        return codes
    except (subprocess.SubprocessError,OSError):return ['HOST_UNREACHABLE']
    except (KeyError,ValueError,TypeError):return ['REPORT_FAILED']

def check_api():
    for attempt in range(3):
        try:
            req=urllib.request.Request('https://api.galylio.com/health',headers={'User-Agent':'BioBalance-Monitor/1.0','Accept':'application/json'})
            with urllib.request.build_opener(NoRedirect()).open(req,timeout=12) as response:
                if response.status==200 and json.loads(response.read(4096))=={'status':'ok'}:return []
        except Exception:pass
        if attempt<2:time.sleep(3)
    return ['API_UNREACHABLE']

def send(kind, problems, now):
    recipient=os.environ['MONITOR_EMAIL_TO'];sender=os.environ['MONITOR_SMTP_USER']
    if not all(re.fullmatch(r'[A-Za-z0-9.!#$%&\'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+',x) for x in (recipient,sender)):raise ValueError('Invalid email address')
    title={'incident':'BioBalance — alerte serveur','recovery':'BioBalance — service rétabli','diagnostic':'BioBalance — test de supervision'}[kind]
    lead={'incident':'Un contrôle nécessite votre attention.','recovery':'Deux contrôles successifs confirment le retour à la normale.','diagnostic':'La supervision externe est active. Ceci est un test, aucune panne n’a été provoquée.'}[kind]
    stamp=datetime.datetime.fromtimestamp(now,datetime.timezone.utc).strftime('%d/%m/%Y à %H:%M UTC')
    details='\n'.join('- '+CODES[x] for x in problems)
    msg=EmailMessage();msg['From']='BioBalance <'+sender+'>';msg['To']=recipient;msg['Subject']=title
    msg['Date']=datetime.datetime.fromtimestamp(now,datetime.timezone.utc)
    event=hashlib.sha256((kind+'|'+','.join(problems)+'|'+str(now)).encode()).hexdigest()[:32]
    msg['Message-ID']='<ops-'+event+'@'+sender.split('@')[1]+'>'
    msg.set_content(f'{lead}\n\n{details}\n\nContrôle du {stamp}.\nAPI : https://api.galylio.com/health\n\nBioBalance · Supervision technique\n')
    msg.add_alternative('<!doctype html><html lang="fr"><meta charset="utf-8"><body style="font-family:Arial,sans-serif;color:#252525;line-height:1.6"><main style="max-width:480px;margin:32px auto;padding:0 20px"><p style="font-size:14px;color:#666">BioBalance</p><h1 style="font-size:21px;font-weight:600">'+title.replace('BioBalance — ','')+'</h1><p>'+lead+'</p>'+(''.join('<p>• '+CODES[x]+'</p>' for x in problems))+'<p style="font-size:14px;color:#666">'+stamp+'</p></main></body></html>',subtype='html')
    with smtplib.SMTP_SSL('mail.galylio.com',465,context=ssl.create_default_context(),timeout=20) as smtp:
        smtp.login(sender,os.environ['MONITOR_SMTP_PASSWORD'])
        if smtp.send_message(msg):raise RuntimeError('Recipient rejected')

def main():
    p=argparse.ArgumentParser();p.add_argument('--state',type=pathlib.Path,required=True);p.add_argument('--diagnostic',action='store_true');a=p.parse_args()
    previous={}
    if a.state.exists():
        previous=json.loads(a.state.read_text())
        if previous.get('version')!=1 or not isinstance(previous.get('incident'),list) or any(x not in CODES for x in previous['incident']) or not isinstance(previous.get('sentAt'),int) or previous['sentAt']>time.time()+60:raise ValueError('Invalid previous monitor state')
    problems=sorted(set(check_api()+check_host()));now=int(time.time());kind,state=decide(previous,problems,now,a.diagnostic)
    if kind:send(kind,problems,now)
    a.state.parent.mkdir(parents=True,exist_ok=True)
    temp=a.state.with_suffix('.tmp');temp.write_text(json.dumps(state)+'\n');temp.replace(a.state)
    print(json.dumps({'problems':problems,'email':kind or 'not_needed'}))
    return 1 if problems else 0
if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'monitor':'failed','type':type(error).__name__}));raise SystemExit(2)
