from pathlib import Path
import subprocess,json,sys,xml.etree.ElementTree as ET,time
root=Path(__file__).resolve().parent
adb='/Users/zhuanzmima0000/Library/Android/sdk/platform-tools/adb'
serial='emulator-5580'
def run(*args): return subprocess.check_output([adb,'-s',serial,*args],text=True)
if len(sys.argv)>1 and sys.argv[1]=='baseline':
 out={}
 for key in ['ro.build.version.release','ro.build.version.sdk','ro.product.cpu.abi','ro.build.fingerprint']:
  out[key]=run('shell','getprop',key).strip()
 out['packages']=run('shell','pm','list','packages','-u').splitlines()
 out['gmsInstalledOrUninstalledRecord']=any(s in p for p in out['packages'] for s in ['com.google.android.gms','com.android.vending','com.google.android.gsf'])
 out['connectivity']=run('shell','dumpsys','connectivity')
 out['airplane']=run('shell','settings','get','global','airplane_mode_on').strip()
 out['pageSize']=run('shell','getconf','PAGE_SIZE').strip()
 out['imageSourceProperties']=Path('/Users/zhuanzmima0000/Library/Android/sdk/system-images/android-35/default/arm64-v8a/source.properties').read_text()
 (root/'device-baseline.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({k:v for k,v in out.items() if k not in ['packages','connectivity']},ensure_ascii=False,indent=2))
else:
 label=sys.argv[1] if len(sys.argv)>1 else 'ui'
 remote='/sdcard/sanqian-validation-ui.xml'
 run('shell','uiautomator','dump',remote)
 xml=run('shell','cat',remote)
 (root/(label+'.xml')).write_text(xml)
 tree=ET.fromstring(xml)
 for node in tree.iter('node'):
  a=node.attrib
  if a.get('text') or a.get('content-desc'):
   print(json.dumps({k:a.get(k) for k in ['text','content-desc','resource-id','bounds','clickable']},ensure_ascii=False))
