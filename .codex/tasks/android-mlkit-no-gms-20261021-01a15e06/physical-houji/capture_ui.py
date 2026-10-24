from pathlib import Path
import subprocess,json,sys,xml.etree.ElementTree as ET,time
root=Path(__file__).resolve().parent
adb='/Users/zhuanzmima0000/Library/Android/sdk/platform-tools/adb'
serial='985ef9ce'
def run(*args): return subprocess.check_output([adb,'-s',serial,*args],text=True)
label=sys.argv[1] if len(sys.argv)>1 else 'ui'
remote='/data/local/tmp/sanqian-physical-validation-ui.xml'
run('shell','uiautomator','dump',remote)
xml=run('shell','cat',remote)
tree=ET.fromstring(xml)
allowed={'love.sanqian.schedule','com.google.android.providers.media.module','com.android.providers.media.module','com.android.permissioncontroller','com.lbe.security.miui','com.miui.gallery','com.miui.securitycenter','com.google.android.permissioncontroller','com.miui.packageinstaller'}
packages={n.attrib.get('package') for n in tree.iter('node')}
if not packages.intersection(allowed):
 print('Foreground is outside validation scope:',sorted(str(s) for s in packages));sys.exit(0)
(root/(label+'.xml')).write_text(xml)
for node in tree.iter('node'):
 a=node.attrib
 if a.get('text') or a.get('content-desc'):
  print(json.dumps({k:a.get(k) for k in ['text','content-desc','resource-id','bounds','clickable']},ensure_ascii=False))
