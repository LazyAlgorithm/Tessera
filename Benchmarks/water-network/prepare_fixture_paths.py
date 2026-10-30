"""Point legacy test fixture native-library paths at this checkout. Run in an isolated checkout."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[2]
changed=[]
for p in (root/'Tests').glob('*/BeefProj.toml'):
 s=p.read_text();new=s.replace('/home/zerker24/BeefProjects/Tessera/build/native',str(root/'build/native'))
 if new!=s:p.write_text(new);changed.append(str(p.relative_to(root)))
print(json.dumps({'native_path':str(root/'build/native'),'changed':changed},indent=2))
