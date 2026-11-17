from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]); manifest=json.loads((Path(__file__).parent/'finder.50-source-sha256.json').read_text())
for name,digest in manifest.items():
 assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
assert not (root/'macshot/Resources/WindowIcons').exists()
print(f'PASS: {len(manifest)} finder.50 source and resource files verified')
