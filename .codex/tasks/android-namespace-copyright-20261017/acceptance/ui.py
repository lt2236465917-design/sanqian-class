from pathlib import Path
import subprocess,sys,xml.etree.ElementTree as ET,re
ROOT=Path(__file__).resolve().parent
ADB='/Users/zhuanzmima0000/Library/Android/sdk/platform-tools/adb'
def adb(*args):return subprocess.run([ADB,'-s','emulator-5554',*args],check=True,capture_output=True).stdout
def dump(name):
 adb('shell','uiautomator','dump','/sdcard/sanqian-acceptance.xml')
 data=adb('exec-out','cat','/sdcard/sanqian-acceptance.xml');(ROOT/(name+'.xml')).write_bytes(data)
 nodes=list(ET.fromstring(data).iter('node'))
 for i,n in enumerate(nodes):
  text=n.get('text') or n.get('content-desc') or ('[input]' if n.get('class')=='android.widget.EditText' else '')
  if text and n.get('password')!='true':print(i,repr(text),n.get('bounds'),'editable' if n.get('class')=='android.widget.EditText' else '')
 return nodes
def tap_label(name,label):
 nodes=dump(name)
 found=[n for n in nodes if n.get('text')==label or n.get('content-desc')==label or (n.get('text') or n.get('content-desc') or '').startswith(label+'\n')]
 assert len(found)==1,(label,len(found))
 a=list(map(int,re.findall(r'\d+',found[0].get('bounds'))))
 adb('shell','input','tap',str((a[0]+a[2])//2),str((a[1]+a[3])//2))
 import time;time.sleep(.6)
if __name__=='__main__':
 if sys.argv[1]=='dump':dump(sys.argv[2])
 elif sys.argv[1]=='tap':
  nodes=list(ET.parse(ROOT/(sys.argv[2]+'.xml')).iter('node'));n=nodes[int(sys.argv[3])];a=list(map(int,re.findall(r'\d+',n.get('bounds'))));adb('shell','input','tap',str((a[0]+a[2])//2),str((a[1]+a[3])//2))
 elif sys.argv[1]=='text':adb('shell','input','text',sys.argv[2])
 elif sys.argv[1]=='back':adb('shell','input','keyevent','KEYCODE_BACK')
