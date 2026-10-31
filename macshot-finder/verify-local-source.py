"""Verify the finder.21 release tree, including its documented locale wording fix."""
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1]).resolve()
manifest = json.loads((Path(__file__).parent / 'finder.21-source-sha256.json').read_text())
for relative, expected in manifest.items():
    path = root / relative
    assert path.is_file(), f'Missing release source: {relative}'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, f'Source mismatch: {relative}'
print(f'PASS: {len(manifest)} source/resource files match the verified finder.21 release snapshot')
