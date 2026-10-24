import subprocess, sys, xml.etree.ElementTree as ET, json, re
ADB = '/Users/zhuanzmima0000/Library/Android/sdk/platform-tools/adb'
def adb(*args):
    return subprocess.check_output([ADB, '-s', 'emulator-5556', *args], stderr=subprocess.DEVNULL)
def nodes():
    adb('shell', 'uiautomator', 'dump', '/sdcard/window.xml')
    return list(ET.fromstring(adb('exec-out', 'cat', '/sdcard/window.xml')).iter('node'))
if __name__ == '__main__':
    action=sys.argv[1]
    if action == 'dump':
        for n in nodes():
            a=n.attrib
            if a.get('text') or a.get('content-desc') or a.get('class')=='android.widget.EditText':
                print(json.dumps({k:a.get(k) for k in ['text','content-desc','class','bounds','password','enabled']},ensure_ascii=False))
    elif action == 'tap':
        matches=[n for n in nodes() if sys.argv[2] in [n.get('text'),n.get('content-desc'),n.get('resource-id')]]
        assert len(matches)==1, f'{len(matches)} matches'
        x1,y1,x2,y2=map(int,re.findall(r'\d+',matches[0].get('bounds')))
        adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
