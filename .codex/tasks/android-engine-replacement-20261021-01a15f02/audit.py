from pathlib import Path
import zipfile,hashlib,struct,json,subprocess,re
repo=Path.cwd();p=repo/'.codex/tasks/android-engine-replacement-20261021-01a15f02';apk=repo/'build/app/outputs/flutter-apk/app-release.apk';b=apk.read_bytes();result={'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b),'native':[],'forbiddenEntries':[],'forbiddenDexStrings':[]}
with zipfile.ZipFile(apk) as z:
 for n in z.namelist():
  if any(t in n.lower() for t in ['mlkit','ml_kit','barhopper','play-services']):result['forbiddenEntries'].append(n)
  data=z.read(n)
  if n.endswith('.dex'):
   for token in [b'com/google/mlkit',b'com/google/android/gms',b'com/google/android/libraries/barhopper']:
    if token in data:result['forbiddenDexStrings'].append([n,token.decode()])
  if n.endswith('.so'):
   cls=data[4];off=struct.unpack_from('<Q' if cls==2 else '<I',data,32 if cls==2 else 28)[0];ent,num=struct.unpack_from('<HH',data,54 if cls==2 else 42);align=[]
   for i in range(num):
    pos=off+i*ent
    if struct.unpack_from('<I',data,pos)[0]==1:align.append(struct.unpack_from('<Q' if cls==2 else '<I',data,pos+(48 if cls==2 else 28))[0])
   result['native'].append({'path':n,'bytes':len(data),'loadAlign':align})
 result['models']=[{'path':n,'sha256':hashlib.sha256(z.read(n)).hexdigest(),'bytes':z.getinfo(n).file_size} for n in z.namelist() if n.endswith('.onnx')]
bt=Path('/Users/zhuanzmima0000/Library/Android/sdk/build-tools/36.1.0')
r=subprocess.run([str(bt/'zipalign'),'-c','-P','16','-v','4',str(apk)],capture_output=True,text=True);result['zipalignExit']=r.returncode;(p/'zipalign.txt').write_text(r.stdout+r.stderr)
r=subprocess.run([str(bt/'aapt'),'dump','badging',str(apk)],capture_output=True,text=True);(p/'badging.txt').write_text(r.stdout);result['package']=r.stdout.splitlines()[0]
r=subprocess.run([str(bt/'aapt'),'dump','xmltree',str(apk),'AndroidManifest.xml'],capture_output=True,text=True);(p/'merged-manifest.txt').write_text(r.stdout);result['manifestForbidden']=bool(re.search('mlkit|com.google.android.gms|play.services',r.stdout,re.I))
r=subprocess.run([str(bt/'apksigner'),'verify','--print-certs',str(apk)],capture_output=True,text=True);(p/'signature-public.txt').write_text(r.stdout);result['signatureVerified']=r.returncode==0
result['iosGitDiff']=subprocess.check_output(['git','diff','--name-only','--','ios'],text=True).splitlines()
src=Path('/Users/zhuanzmima0000/.pub-cache/hosted/pub.dev/mobile_scanner-7.1.3');fork=repo/'packages/mobile_scanner';result['upstreamChanged']={}
for folder in ['lib','darwin']:
 changes=[]
 for f in (src/folder).rglob('*'):
  if f.is_file():
   dest=fork/f.relative_to(src)
   if not dest.exists() or dest.read_bytes()!=f.read_bytes():changes.append(str(f.relative_to(src)))
 result['upstreamChanged'][folder]=changes
(p/'audit.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k not in ['native','models']},indent=2))
