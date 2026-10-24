from pathlib import Path
import shutil,re,sys
p=Path(__file__).resolve().parent;repo=p.parents[3]
mode=sys.argv[1];s=(p/'LocalOcrProbe.template.java').read_text()
if mode=='old':vals=['n5.a','love.sanqian.schedule.d','','','b']
else:
 mapping=(repo/'build/app/outputs/mapping/release/mapping.txt').read_text()
 vals=[re.search(r'^love.sanqian.schedule.AIImportImage -> (.*):$',mapping,re.M)[1],'love.sanqian.schedule.PaddleChineseTimetableOcr','Context.class','ctx','recognize']
for key,v in zip(['IMAGE_CLASS','OCR_CLASS','CTOR_TYPES','CTOR_ARGS','RECOGNIZE_METHOD'],vals):s=s.replace(key,v)
(p/'LocalOcrProbe.java').write_text(s)
for f in ['AndroidManifest.xml','build_probe.py']:shutil.copy2(p.parent/'baseline/probe'/f,p/f)
s=(p/'build_probe.py').read_text().replace('repo=p.parents[4]','repo=p.parents[3]');(p/'build_probe.py').write_text(s)
