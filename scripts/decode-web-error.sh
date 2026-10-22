#!/usr/bin/env bash
# Reads a minified stack frame of the web console with the source map of the build that made it.
# The build's commit is shown in the error's version ("3.3.2 (42) 1a2b3c4d"); its map is kept private on the server.
# Usage: scripts/decode-web-error.sh <commit> <line> <column>    (the "main.dart.js:LINE:COLUMN" of a stack frame)
set -euo pipefail
[[ $# -eq 3 ]] || { echo "Usage: $0 <commit> <line> <column>" >&2; exit 2; }
host=${DEPLOY_HOST:-go2code}
work=$(mktemp -d)
map="$work/main.dart.js.map"
trap 'rm -rf "$work"' EXIT
ssh "$host" "sudo cat /opt/biobalance-web-maps/$1/main.dart.js.map" > "$map"
npm install --silent --no-audit --no-fund --prefix "$work" source-map@0.7.4 >/dev/null
NODE_PATH="$work/node_modules" node -e '
const { SourceMapConsumer } = require("source-map");
const raw = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
SourceMapConsumer.with(raw, null, (c) => {
  const o = c.originalPositionFor({ line: Number(process.argv[2]), column: Number(process.argv[3]) });
  console.log(`${o.name ?? "?"}  ${o.source}:${o.line}:${o.column}`);
});
' "$map" "$2" "$3"
