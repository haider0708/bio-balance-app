#!/usr/bin/env python3
"""Prepare an isolated Compose lab without replacing an existing lab's secrets/data."""
import base64,json,pathlib,secrets,subprocess
root=pathlib.Path(__file__).resolve().parents[2]
lab=root/'.artifacts/deployment-lab'
lab.mkdir(mode=0o700,parents=True,exist_ok=True)
if (lab/'.env').exists():
    print('Existing deployment lab preserved');raise SystemExit(0)
for folder in ['certificates','acme','secrets','bootstrap','backups']:(lab/folder).mkdir(mode=0o700)
owner=secrets.token_hex(24);app=secrets.token_hex(24)
settings={
 'API_IMAGE':'biobalance-api:step11-local','MEDIA_IMAGE':'biobalance-media:step11-local',
 'POSTGRES_USER':'biobalance_owner','POSTGRES_PASSWORD':owner,'POSTGRES_DB':'biobalance_deployment_test',
 'DATABASE_URL':f'postgresql://biobalance_app:{app}@postgres:5432/biobalance_deployment_test',
 'MIGRATION_DATABASE_URL':f'postgresql://biobalance_owner:{owner}@postgres:5432/biobalance_deployment_test',
 'APP_PASSWORD':app,'MFA_ENCRYPTION_KEY':base64.b64encode(secrets.token_bytes(32)).decode(),
 'SMTP_HOST':'mailpit','SMTP_PORT':'1025','SMTP_SECURE':'false','SMTP_REQUIRE_TLS':'false',
 'SMTP_FROM':'BioBalance test <no-reply@example.test>',
 'FIREBASE_CREDENTIALS_FILE':str(lab/'secrets/firebase.json'),
}
(lab/'.env').write_text(''.join(f'{key}={json.dumps(value)}\n' for key,value in settings.items()))
(lab/'.env').chmod(0o600)
(lab/'secrets/firebase.json').write_text('{}');(lab/'secrets/firebase.json').chmod(0o600)
subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','30',
 '-keyout',str(lab/'certificates/privkey.pem'),'-out',str(lab/'certificates/fullchain.pem'),
 '-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
(lab/'override.yml').write_text(f'''services:
  nginx:
    ports: !override ['127.0.0.1:18080:80','127.0.0.1:18443:443']
    volumes:
      - {lab}/certificates:/etc/nginx/certificates:ro
      - {lab}/acme:/var/www/acme:ro
  mailpit:
    image: axllent/mailpit:v1.27
    networks: [private]
    ports: ['127.0.0.1:18025:8025']
''')
print('Isolated deployment lab prepared')
