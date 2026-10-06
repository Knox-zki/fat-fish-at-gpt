#!/usr/bin/env python3
from pathlib import Path
import json, plistlib, shutil, subprocess
root=Path(__file__).resolve().parents[1]
assets=root/'assets'
app=root/'dist/DSLPet.app';mac=app/'Contents/MacOS';res=app/'Contents/Resources';mac.mkdir(parents=True,exist_ok=True);res.mkdir(parents=True,exist_ok=True)
subprocess.run(['/usr/bin/swiftc','-swift-version','5','-O','-module-cache-path',str(root/'.swift-cache'),*[str(root/'Sources'/f) for f in ['Engine.swift','App.swift','Notices.swift','Reply.swift','main.swift']],'-o',str(mac/'DSLPet')],check=True)
manifest=json.loads((assets/'animations.json').read_text())
for a in manifest:
 dst=res/'assets'/a['key'];dst.mkdir(parents=True,exist_ok=True)
 shutil.copy2(assets/a['key']/'animation.json',dst/'animation.json')
 shutil.copytree(assets/a['key']/'逐帧PNG',dst/'逐帧PNG',dirs_exist_ok=True)
for n in ['animations.json','待机.png']:shutil.copy2(assets/n,res/'assets'/n)
shutil.copy2(root/'scripts/bridge.py',res/'bridge.py')
shutil.copy2(root/'scripts/reply.py',res/'reply.py')
info={'CFBundleExecutable':'DSLPet','CFBundleIdentifier':'local.chennuo.dsl-pet','CFBundleName':'小 DSL','CFBundleDisplayName':'小 DSL 悬浮桌宠','CFBundleVersion':'8','CFBundleShortVersionString':'0.3.1','CFBundlePackageType':'APPL','LSUIElement':True,'NSHighResolutionCapable':True,'LSMinimumSystemVersion':'13.0'}
with (app/'Contents/Info.plist').open('wb') as f:plistlib.dump(info,f)
subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(app)],check=True)
subprocess.run([str(mac/'DSLPet'),'--self-test',str(res/'assets/animations.json')],check=True)
print(app)
