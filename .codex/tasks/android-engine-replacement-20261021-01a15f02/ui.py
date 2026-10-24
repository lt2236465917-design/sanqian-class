from pathlib import Path
import subprocess,sys,xml.etree.ElementTree as E,re
p=Path(__file__).parent
adb=['/Users/zhuanzmima0000/Library/Android/sdk/platform-tools/adb','-s','emulator-5582']
def run(*a):return subprocess.check_output(adb+list(a))
run('shell','uiautomator','dump','/sdcard/sanqian-engine-window.xml')
s=run('shell','cat','/sdcard/sanqian-engine-window.xml');root=E.fromstring(s)
parents={child:parent for parent in root.iter() for child in parent}
for n in root.iter('node'):
 label=n.get('text') or n.get('content-desc')
 if not label:continue
 target=n
 while target.get('clickable')!='true' and target in parents:target=parents[target]
 if len(sys.argv)>1 and sys.argv[1]=='tap' and sys.argv[2] in label and target.get('clickable')=='true':
  n=target
  x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));run('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));print('Tapped',label);break
 print(label.replace('\n',' / '),n.get('bounds'))
if len(sys.argv)>1 and sys.argv[1]=='save':
 (p/(sys.argv[2]+'.xml')).write_bytes(s)
 (p/(sys.argv[2]+'.png')).write_bytes(run('exec-out','screencap','-p'))
