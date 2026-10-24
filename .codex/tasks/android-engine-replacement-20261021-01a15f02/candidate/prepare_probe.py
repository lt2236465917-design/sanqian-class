from pathlib import Path
import re,shutil,json,hashlib
p=Path(__file__).resolve().parent; repo=p.parents[3]
maptext=(repo/'build/app/outputs/mapping/release/mapping.txt').read_text()
def cls(name):
 return re.search(r'^love.sanqian.schedule.'+name+r' -> (.*):$',maptext,re.M)[1]
def meth(name,method):
 block=maptext.split('love.sanqian.schedule.'+name+' -> ')[1].split('\n',1)[1].split('\n# ')[0]
 # obtain full class section instead (metadata lines are part of it)
 block=re.search(r'^love.sanqian.schedule.'+name+r' -> [^\n]*:\n(.*?)(?=^[A-Za-z][^\n]* -> [^\n]*:|\Z)',maptext,re.M|re.S)[1]
 return re.search(r'\b'+method+r'\(\).* -> (\w+)',block)[1]
s=(p.parent/'baseline/probe/LocalOcrProbe.java').read_text()
s=s.replace('n5.a',cls('AIImportImage')).replace('love.sanqian.schedule.d','love.sanqian.schedule.PaddleChineseTimetableOcr').replace('ocrClass.getDeclaredConstructor()','ocrClass.getDeclaredConstructor(Context.class)').replace('getDeclaredMethod("b",List.class','getDeclaredMethod("recognize",List.class').replace('ocrConstructor.newInstance()','ocrConstructor.newInstance(ctx)')
s=s.replace('getDeclaredMethod("b"); getTokens','getDeclaredMethod("'+meth('OcrPage','getTokens')+'"); getTokens').replace('getDeclaredMethod("f"); getText','getDeclaredMethod("'+meth('OcrToken','getText')+'"); getText')
s=s.replace('long start=SystemClock.elapsedRealtime();','long pssBefore=android.os.Debug.getPss(); long start=SystemClock.elapsedRealtime();')
s=s.replace('row.put("run",run+1);','row.put("run",run+1); row.put("pssBeforeKB",pssBefore); row.put("pssAfterKB",android.os.Debug.getPss());')
s=s.replace('output.put("runs",runs);','''output.put("runs",runs);
      try { recognize.invoke(ocrConstructor.newInstance(ctx),Collections.singletonList(input),new AtomicBoolean(true)); throw new IllegalStateException("Pre-cancel not honored"); }
      catch(InvocationTargetException e) { output.put("precancel",e.getCause().toString()); }
      Bitmap blank=Bitmap.createBitmap(640,480,Bitmap.Config.ARGB_8888); new Canvas(blank).drawColor(Color.WHITE);
      ByteArrayOutputStream bb=new ByteArrayOutputStream();blank.compress(Bitmap.CompressFormat.JPEG,95,bb);blank.recycle();
      Object bi=imageConstructor.newInstance(bb.toByteArray(),"image/jpeg");
      List<?> empty=(List<?>)recognize.invoke(ocrConstructor.newInstance(ctx),Collections.singletonList(bi),new AtomicBoolean(false));
      Method gt=empty.get(0).getClass().getDeclaredMethod("GETTOKENS");gt.setAccessible(true);
      output.put("blankTokens",((List<?>)gt.invoke(empty.get(0))).size());
      if(((List<?>)gt.invoke(empty.get(0))).size()!=0) throw new IllegalStateException("Blank hallucination");
'''.replace('GETTOKENS',meth('OcrPage','getTokens')))
(p/'probe/LocalOcrProbe.java').write_text(s)
shutil.copy2(repo/'build/app/outputs/mapping/release/mapping.txt',p/'mapping-current.txt')
print('Probe targets current mapping:',cls('AIImportImage'))
