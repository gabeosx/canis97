#!/usr/bin/env python3
"""Verify shipping bundle membership and optionally the built app's exact bytes."""
from pathlib import Path
import hashlib,json,re,sys
repo=Path(__file__).resolve().parents[1];root=repo/'SiriusMac/Skins/Bundled'
manifest=json.loads((root/'Abyssal97.json').read_text());motion=manifest['motion']
files=['Abyssal97.json',motion['document'],motion['spriteScene'],motion['staticPose'],*motion['spriteAssets']]
files=list(dict.fromkeys(files));assert len(files)==23
assert manifest['schemaVersion']==4 and manifest['identifier']=='com.gabeosx.abyssal97'
assert manifest['displayName']=='Abyssal 97 — Living Ocean'
assert '"Abyssal97"' in (repo/'SiriusMac/Skins/SkinAppearance.swift').read_text()
project=(repo/'SiriusMac.xcodeproj/project.pbxproj').read_text()
resource=re.search(r'/\* Resources \*/ = \{isa = PBXResourcesBuildPhase;.*?files = \((.*?)\);',project,re.S)[1]
report={}
for name in files:
 assert Path(name).name==name and name.startswith('Abyssal97')
 source=root/('Assets/Abyssal97/'+name if name.endswith('.png') else name)
 assert source.is_file(),source
 assert resource.count('/* '+name+' in Resources */')==1,name
 data=source.read_bytes();report[name]=hashlib.sha256(data).hexdigest()
 if len(sys.argv)>1:
  built=Path(sys.argv[1])/'Contents/Resources'/name
  assert built.read_bytes()==data, f'Built copy differs: {name}'
scene=json.loads((root/motion['spriteScene']).read_text())
assert scene['formatVersion']==2 and len(scene['performances'])==28
assert {l['asset'] for l in scene['layers']}==set(motion['spriteAssets'])
provenance=json.loads((root/'BundledThemeProvenance.json').read_text())
record=next(x for x in provenance['themes'] if x['identifier']==manifest['identifier'])
assert set(record['assetFiles'])=={x for x in files if x.endswith('.png')}
print('PASS: Abyssal bundled catalog, 23 unique namespaced resources, repertoire and provenance'+('; built app bytes identical' if len(sys.argv)>1 else ''))
