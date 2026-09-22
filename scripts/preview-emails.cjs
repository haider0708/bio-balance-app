/* Render only synthetic examples; no database connection or live bearer codes. */
const { mkdirSync, writeFileSync } = require('node:fs');
const path = require('node:path');
const { renderEmail } = require('../apps/api/dist/shared/email/email-templates');
const destination = path.resolve(process.argv[2] ?? '.artifacts/email-previews');
// Previewing must not accidentally embed configured account links or real codes.
delete process.env.ACTIVATION_URL;
delete process.env.RECOVERY_URL;
const token = 'EXEMPLE-UNIQUEMENT-CODE-SANS-ACCES-BIOBALANCE';
const date = new Date('2026-09-24T13:30:00Z');
const samples = [
  ['invitation-manager', 'Invitation responsable', { kind: 'invite', token, organizationName: 'Partenaire BioBalance', expiresAt: date }],
  ['invitation-team', 'Invitation équipe', { kind: 'invite', token, storeName: 'Parapharmacie Tunis', expiresAt: date }],
  ['password-reset', 'Récupération du compte', { kind: 'reset', token, expiresAt: date }],
  ['password-changed', 'Confirmation de sécurité', { kind: 'password-changed', changedAt: date }],
  ['delivery-test', 'Test de livraison', { kind: 'delivery-test', reference: 'exemple-sans-envoi', sentAt: date }],
];
mkdirSync(destination, { recursive: true });
for (const [id, , input] of samples) {
  const content = renderEmail(input);
  writeFileSync(path.join(destination, id + '.html'), content.html);
  writeFileSync(path.join(destination, id + '.txt'), content.subject + '\n\n' + content.text);
}
writeFileSync(path.join(destination, 'index.html'), `<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>BioBalance · Emails</title><style>body{margin:0;color:#1c1e22;font:15px/1.5 system-ui;background:#f5f6f4}header{padding:20px 24px;border-bottom:1px solid #dde3d9;background:white}h1{font-size:20px;margin:0 0 6px}p{margin:0 0 16px;color:#606164}select,button{font:inherit;padding:10px;border:1px solid #dde3d9;border-radius:6px;background:white;color:#1c1e22;margin:0 8px 8px 0}main{padding:24px 8px}iframe{display:block;border:1px solid #dde3d9;border-radius:6px;background:white;width:100%;max-width:640px;height:1050px;margin:auto;box-sizing:border-box}</style><header><h1>BioBalance · Emails d’accès et de sécurité</h1><p>Aperçus fictifs. Les codes ne donnent aucun accès.</p><select aria-label="Modèle" onchange="document.querySelector('iframe').src=this.value">${samples.map(([id,label]) => `<option value="${id}.html">${label}</option>`).join('')}</select><button onclick="document.querySelector('iframe').style.maxWidth='640px'">Ordinateur</button><button onclick="document.querySelector('iframe').style.maxWidth='320px'">Téléphone 320 px</button></header><main><iframe title="Aperçu du message" src="invitation-manager.html"></iframe></main></html>`);
console.log(path.join(destination, 'index.html'));
