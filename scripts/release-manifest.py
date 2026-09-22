#!/usr/bin/env python3
"""Record build inputs and hashes; packaging independently rechecks signatures."""
import datetime
import json
from pathlib import Path
import sys
from release_integrity import sha256, source_identity

root = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1]).resolve()
artifacts = {p.relative_to(output).as_posix(): sha256(p)
             for p in sorted(output.rglob('*')) if p.is_file() and p.name != 'manifest.json'}
manifest = {
    'createdUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    **source_identity(root),
    'mode': sys.argv[2], 'platform': sys.argv[3], 'entrypoint': 'lib/main.dart',
    'productionAccepted': False, 'sha256': artifacts,
}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
