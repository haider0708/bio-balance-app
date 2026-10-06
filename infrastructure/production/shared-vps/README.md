# BioBalance on the shared go2code VPS

This override is specific to that server. Apache already serves other sites on ports 80 and 443. It terminates HTTPS for `api.galylio.com` and forwards to Nginx on `127.0.0.1:18081`; Nginx applies the rate limits and balances two API processes. The files hold no secret: the real environment lives in `/etc/biobalance/backend.env` (root, mode 0600). Operator command: `sudo biobalance-compose …`. The `172.29.90.0/24` network was checked free; do not reuse this override elsewhere without checking the network and ports.

## Cloudflare and HTTPS

- DNS `A api → 146.59.195.61`, proxied, SSL/TLS mode **Full (strict)**.
- `apache-http.conf` serves public ACME challenges and redirects everything else to HTTPS.
- `apache-https.conf` uses this host's Let's Encrypt certificate and includes `cloudflare-origin.conf`, which restricts origin HTTPS to Cloudflare addresses and the loopback. `CF-Connecting-IP` is only trusted from Cloudflare's published ranges; Apache replaces every other forwarding header and Nginx trusts only the Docker gateway.
- `biobalance-tls.timer` renews the certificate twice a day; the deploy hook checks and reloads Apache.
- Cloudflare accepts request bodies up to 100 MB, so the largest upload the API allows is 90 MiB (training videos). Do not enable forced caching or browser challenges on API routes.

When Nginx's mounted file changes, recreate **only** its container after validating the syntax (replacing the file can change its inode). Never use `down -v` for an update.

## Resources and operations

Ceilings: two API processes of 512 MiB (1.5 CPU each), worker 384 MiB / 0.5 CPU, PostgreSQL 2 GiB / 4 CPU, Nginx 128 MiB. These caps do not reserve capacity against the other sites on the host.

Local backups go to `/srv/biobalance-backups` (4 GiB budget, 10 GiB operational reserve; up to 7 daily and 4 weekly copies, never deleting the last valid one). `biobalance-backup.timer` and `biobalance-monitor.timer` read `/etc/biobalance/backup.env`. The monitor checks services, resources, jobs, backup freshness, the public HTTPS endpoint and the certificate (more than 7 days left). See the [runbook](../../../docs/runbook.md). Backups on this VPS do not survive losing the whole server.
