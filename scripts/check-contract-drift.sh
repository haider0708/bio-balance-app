#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
npm run api:contract
python3 scripts/generate-dart-client.py
git diff --exit-code -- contracts/openapi/biobalance.json apps/mobile/lib/data/services/api/generated apps/mobile/test/generated
if [[ -n "$(git ls-files --others --exclude-standard contracts/openapi apps/mobile/lib/data/services/api/generated apps/mobile/test/generated)" ]]; then
  echo 'Generated contract files must be committed.' >&2
  exit 1
fi
