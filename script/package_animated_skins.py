#!/usr/bin/env python3
"""Build reproducible standalone archives for every bundled schema-4 appearance."""
import hashlib,json,zipfile,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];B=ROOT/'SiriusMac/Skins/Bundled'
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);args=p.parse_args();args.output.mkdir(parents=True,exist_ok=True)
def resolve(name,skin):
 for x in [B/name,B/'Assets'/name,B/'Assets'/skin/name]:
  if x.is_file():return x
 raise FileNotFoundError(name)
reports=[]
for file in sorted(B.glob('*.json')):
 m=json.loads(file.read_text())
 if m.get('schemaVersion')!=4:continue
 name=file.stem;motion=m['motion'];refs=set(motion.get('spriteAssets',[]))|{motion['document'],motion['staticPose']}
 if motion.get('spriteScene'):refs.add(motion['spriteScene'])
 # Declarative faceplate decorations can share the motion static pose.
 for decoration in m.get('decorations',{}).values():
  if isinstance(decoration,str):refs.add(decoration)
 contents={'manifest.json':(json.dumps(m,indent=2)+'\n').encode()}
 for ref in refs:
  assert not ref.startswith('/') and '..' not in Path(ref).parts
  contents[ref]=resolve(ref,name).read_bytes()
 assert sum(map(len,contents.values()))<=64*1024*1024
 target=args.output/(name+'.canis97skin')
 with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_STORED) as z:
  for n,data in sorted(contents.items()):
   info=zipfile.ZipInfo(n,(2026,9,5,0,0,0));info.create_system=3;info.external_attr=0o100644<<16;z.writestr(info,data)
 with zipfile.ZipFile(target) as z:
  assert z.testzip() is None
  for n,data in contents.items():assert z.read(n)==data
 assert target.stat().st_size<=16*1024*1024
 reports.append(dict(skin=name,file=target.name,bytes=target.stat().st_size,sha256=hashlib.sha256(target.read_bytes()).hexdigest(),entries=len(contents)))
assert len(reports)==5,[r['skin'] for r in reports]
(args.output/'SHA256SUMS').write_text(''.join(f'{r["sha256"]}  {r["file"]}\n' for r in reports))
(args.output/'manifest.json').write_text(json.dumps(reports,indent=2)+'\n')
print(json.dumps(reports,indent=2))
