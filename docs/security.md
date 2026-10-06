# Security

- **Regions are isolated by the database.** Row-level security (forced, with a database role that cannot bypass it) limits every query to the caller's role, region, point of sale or depot. A forgotten filter in the code cannot leak another region's data; tests forge filters to prove it.
- **Sign-in.** Argon2id passwords (admission-controlled so a flood cannot exhaust the server), random 256-bit session tokens stored hashed, 30-day sessions (12 hours for the admin), attempt limits per address and per email, identical answers for unknown and wrong accounts. The admin also needs a TOTP code from an authenticator app; each code works once. The secret is stored encrypted with `MFA_ENCRYPTION_KEY`.
- **Invitations and recovery** use one-time 8-character codes, valid only together with the person's email, stored hashed, expiring (72 hours / 30 minutes) and removed from the job queue once handled.
- **Approvals are enforced by the server**, not by the screens: a pending point of sale cannot sell, a pending member cannot sign in, unapproved stock is not stock.
- **Uploads** are streamed to disk with a size limit per purpose, checked by their real first bytes (JPEG, PNG, WebP, PDF, MP4), stored under server-generated names, and served with `nosniff`. Proof photos are readable only by their author, the admin and the region's responsable.
- **Append-only history** (stock movements, sale revisions, wallet entries, audit log) is enforced by database triggers.
- **Money** is whole millimes in 64-bit integers; payouts lock the person's wallet so concurrent requests cannot overspend.
- **Transport and edge:** HTTPS only (Cloudflare Full-strict, origin restricted to Cloudflare), HSTS, request rate limits, small JSON bodies, `no-store` on API responses, containers read-only with dropped capabilities.
- **CSV exports** neutralise cells that start with `=`, `+`, `-` or `@`.
- **Secrets** (`backend.env`, signing keys, the admin setup file) never enter the repository.
