#!/usr/bin/env bash
set -euo pipefail
# Lockfile-pinned install; only these required native/toolchain hooks may execute.
# npm 11.19 enforces the versioned allowScripts policy with strict mode.
npm ci --ignore-scripts --no-audit --no-fund
npm rebuild --ignore-scripts=false argon2 prisma @prisma/engines esbuild
