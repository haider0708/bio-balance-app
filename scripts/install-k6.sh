#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tooling/k6
curl -fsSL https://github.com/grafana/k6/releases/download/v2.3.0/k6-v2.3.0-linux-amd64.tar.gz -o .tooling/k6/archive.tar.gz
printf '%s\n' '39c3117b6af817592dcd0ce4242105c0a7af10948c2a425306f0be8f7a8a8ab1  .tooling/k6/archive.tar.gz' | sha256sum -c -
tar -xzf .tooling/k6/archive.tar.gz --strip-components=1 -C .tooling/k6
.tooling/k6/k6 version
