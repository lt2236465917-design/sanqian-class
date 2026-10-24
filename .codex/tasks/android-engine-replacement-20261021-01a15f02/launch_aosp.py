from pathlib import Path
import subprocess,os,json
root=Path(__file__).resolve().parent
sdk=Path('/Users/zhuanzmima0000/Library/Android/sdk')
name='sanqian_engine_01a15f02'
env=os.environ.copy();env['ANDROID_HOME']=str(sdk);env['ANDROID_SDK_ROOT']=str(sdk);env['AVDMANAGER_OPTS']='-Dcom.android.sdkmanager.toolsdir='+str(sdk/'cmdline-tools/latest')
avd=root/'avd'
subprocess.run(['avdmanager','create','avd','-n',name,'-k','system-images;android-35;default;arm64-v8a','-p',str(avd),'--device','pixel_6'],input='no\n',text=True,env=env,check=True,stdout=(root/'avd-create.log').open('w'),stderr=subprocess.STDOUT)
config=avd/'config.ini'
text=config.read_text()
settings={'hw.ramSize':'2048','disk.dataPartition.size':'2G','hw.keyboard':'yes','hw.lcd.width':'1080','hw.lcd.height':'1920','hw.lcd.density':'420','showDeviceFrame':'no','hw.camera.back':'emulated','hw.camera.front':'emulated','fastboot.forceColdBoot':'yes','hw.initialOrientation':'Portrait'}
lines=[s for s in text.splitlines() if s.split('=',1)[0].strip() not in settings]
config.write_text('\n'.join(lines+list(k+'='+v for k,v in settings.items()))+'\n')
args=[str(sdk/'emulator/emulator'),'-avd',name,'-port','5582','-no-window','-no-snapshot','-no-boot-anim','-no-audio','-gpu','swiftshader','-camera-back','imagefile:'+str(root/'camera-input.png'),'-camera-front','emulated']
log=(root/'emulator.log').open('w')
process=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
(root/'emulator-launch.json').write_text(json.dumps({'pid':process.pid,'args':args,'avd':str(avd),'name':name},indent=2)+'\n')
print('Started task-owned AOSP AVD',name,'PID',process.pid)
