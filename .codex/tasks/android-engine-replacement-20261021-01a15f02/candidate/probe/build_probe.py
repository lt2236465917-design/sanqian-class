from pathlib import Path
import os,subprocess,zipfile
p=Path(__file__).resolve().parent
repo=p.parents[4]
sdk=Path('/Users/zhuanzmima0000/Library/Android/sdk')
bt=sdk/'build-tools/36.1.0'
jar=sdk/'platforms/android-36/android.jar'
classes=p/'classes'; classes.mkdir(exist_ok=True)
def run(args,**kw): subprocess.run([str(a) for a in args],check=True,**kw)
run(['javac','-encoding','UTF-8','-source','8','-target','8','-classpath',jar,'-d',classes,p/'LocalOcrProbe.java'])
run([bt/'d8','--min-api','24','--lib',jar,'--output',p,*classes.rglob('*.class')])
run([bt/'aapt','package','-f','-M',p/'AndroidManifest.xml','-I',jar,'-F',p/'unsigned.apk'])
with zipfile.ZipFile(p/'unsigned.apk','a') as z: z.write(p/'classes.dex','classes.dex')
run([bt/'zipalign','-f','4',p/'unsigned.apk',p/'aligned.apk'])
props={}
for line in (repo/'android/key.properties').read_text().splitlines():
 if '=' in line and not line.lstrip().startswith('#'):
  k,v=line.split('=',1); props[k.strip()]=v.strip()
store=Path(props['storeFile'])
if not store.is_absolute(): store=(repo/'android/app'/store).resolve()
env=os.environ.copy(); env['SANQIAN_PROBE_STORE_PASS']=props['storePassword']; env['SANQIAN_PROBE_KEY_PASS']=props['keyPassword']
run([bt/'apksigner','sign','--ks',store,'--ks-key-alias',props['keyAlias'],'--ks-pass','env:SANQIAN_PROBE_STORE_PASS','--key-pass','env:SANQIAN_PROBE_KEY_PASS','--out',p/'probe.apk',p/'aligned.apk'],env=env)
run([bt/'apksigner','verify',p/'probe.apk'])
print('Probe built and signature verified; target release APK unchanged.')
