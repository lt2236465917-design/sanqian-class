package probe;
import android.app.Instrumentation;
import android.os.*;
import android.graphics.*;
import android.net.ConnectivityManager;
import android.content.Context;
import org.json.*;
import java.util.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.concurrent.atomic.*;
import java.security.MessageDigest;

public final class LocalOcrProbe extends Instrumentation {
  @Override public void onCreate(Bundle args) {super.onCreate(args);start();}
  static Object fieldOfType(Object o,Class<?> type) throws Exception {
    for(Field f:o.getClass().getDeclaredFields()) if(type.isAssignableFrom(f.getType())) {f.setAccessible(true);return f.get(o);}
    throw new IllegalStateException("Missing field "+type);
  }
  static String text(Object token)throws Exception {return (String)fieldOfType(token,String.class);}
  static int distance(String a,String b){int[] p=new int[b.length()+1];for(int j=0;j<p.length;j++)p[j]=j;
    for(int i=1;i<=a.length();i++){int[] q=new int[b.length()+1];q[0]=i;for(int j=1;j<q.length;j++)q[j]=Math.min(Math.min(q[j-1]+1,p[j]+1),p[j-1]+(a.charAt(i-1)==b.charAt(j-1)?0:1));p=q;}return p[b.length()];}
  static String hash(byte[] b)throws Exception{StringBuilder s=new StringBuilder();for(byte v:MessageDigest.getInstance("SHA-256").digest(b))s.append(String.format("%02x",v));return s.toString();}
  final List<RectF> goldBoxes=new ArrayList<>();
  static String hashFile(File file)throws Exception {
    MessageDigest digest=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[65536];
    try(InputStream input=new FileInputStream(file)){int n;while((n=input.read(buffer))>=0)digest.update(buffer,0,n);}
    StringBuilder s=new StringBuilder();for(byte v:digest.digest())s.append(String.format("%02x",v));return s.toString();
  }
  Bitmap sample(int kind,List<String> gold) {
    goldBoxes.clear();Bitmap bm=Bitmap.createBitmap(1600,1000,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(bm);c.drawColor(Color.WHITE);
    Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);p.setColor(Color.BLACK);p.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));
    if(kind==0){p.setTextSize(56);String[] a={"三千上课 课程表","星期一 高等数学","第一节 08:00-09:35","教学楼 A101","星期二 大学英语","教师 张老师"};for(int i=0;i<a.length;i++){c.drawText(a[i],80,110+i*125,p);gold.add(a[i]);goldBoxes.add(new RectF(80,110+i*125+p.ascent(),80+p.measureText(a[i]),110+i*125+p.descent()));}}
    else {p.setTextSize(kind==2?26:38);String[] a={"课程名称","星期一","星期二","高等数学","08:00-09:35","教学楼A101","大学英语","10:10-11:45","文科楼B203","大学物理","14:00-15:35","实验楼C305","第1-16周","张老师","李老师"};
      Paint line=new Paint();line.setColor(Color.rgb(160,160,160));line.setStrokeWidth(2);
      for(int i=0;i<=5;i++)c.drawLine(60,80+i*170,1540,80+i*170,line);for(int j=0;j<=3;j++)c.drawLine(60+j*493,80,60+j*493,930,line);
      for(int i=0;i<a.length;i++){c.drawText(a[i],90+(i%3)*493,170+(i/3)*170,p);gold.add(a[i]);goldBoxes.add(new RectF(90+(i%3)*493,170+(i/3)*170+p.ascent(),90+(i%3)*493+p.measureText(a[i]),170+(i/3)*170+p.descent()));}
    }
    if(kind==3){Matrix m=new Matrix();m.postRotate(7);RectF extent=new RectF(0,0,bm.getWidth(),bm.getHeight());m.mapRect(extent);for(RectF box:goldBoxes){m.mapRect(box);box.offset(-extent.left,-extent.top);}
      Bitmap rot=Bitmap.createBitmap(bm,0,0,bm.getWidth(),bm.getHeight(),m,true);bm.recycle();return rot;}return bm;
  }
  @Override public void onStart(){JSONObject out=new JSONObject();Bundle bundle=new Bundle();try{
    Context ctx=getTargetContext();ClassLoader loader=ctx.getClassLoader();
    for(String pkg:new String[]{"com.google.android.gms","com.google.android.gsf","com.android.vending"}){
      boolean exists;try{ctx.getPackageManager().getPackageInfo(pkg,0);exists=true;}catch(Exception e){exists=false;}out.put(pkg,exists);if(exists)throw new IllegalStateException("GMS installed");}
    ConnectivityManager net=(ConnectivityManager)ctx.getSystemService(Context.CONNECTIVITY_SERVICE);if(net.getActiveNetwork()!=null)throw new IllegalStateException("Network active");out.put("apkSha256",hashFile(new File(ctx.getApplicationInfo().sourceDir)));
    File cached=new File(ctx.getNoBackupFilesDir(),"ocr-v4");out.put("modelCacheBefore",cached.exists()&&cached.list()!=null?new JSONArray(Arrays.asList(cached.list())):new JSONArray());
    out.put("networkStart",String.valueOf(net.getActiveNetwork()));
    Class<?> image=loader.loadClass("L3.a");Constructor<?> ic=image.getDeclaredConstructor(byte[].class,String.class);ic.setAccessible(true);
    Class<?> ocr=loader.loadClass("love.sanqian.schedule.PaddleChineseTimetableOcr");Constructor<?> oc=ocr.getDeclaredConstructor(Context.class);oc.setAccessible(true);
    Method recognize=ocr.getDeclaredMethod("recognize",List.class,AtomicBoolean.class);recognize.setAccessible(true);
    JSONArray rows=new JSONArray();Object last=null;
    long initialPss=Debug.getPss();AtomicLong peak=new AtomicLong(initialPss);AtomicBoolean monitor=new AtomicBoolean(true);
    Thread sampler=new Thread(()->{while(monitor.get()){peak.accumulateAndGet(Debug.getPss(),Math::max);SystemClock.sleep(20);}});sampler.start();
    try {for(int kind=0;kind<4;kind++){
      List<String> gold=new ArrayList<>();Bitmap bm=sample(kind,gold);ByteArrayOutputStream bytes=new ByteArrayOutputStream();int imageWidth=bm.getWidth(),imageHeight=bm.getHeight();bm.compress(Bitmap.CompressFormat.JPEG,95,bytes);bm.recycle();byte[] jpeg=bytes.toByteArray();last=ic.newInstance(jpeg,"image/jpeg");
      File f=new File(ctx.getExternalFilesDir(null),"engine-sample-"+kind+".jpg");try(FileOutputStream stream=new FileOutputStream(f)){stream.write(jpeg);}
      long start=SystemClock.elapsedRealtime();List<?> pages=(List<?>)recognize.invoke(oc.newInstance(ctx),Collections.singletonList(last),new AtomicBoolean(false));long ms=SystemClock.elapsedRealtime()-start;
      JSONArray tokens=new JSONArray();StringBuilder actual=new StringBuilder();boolean valid=true;
      for(Object page:pages)for(Object token:(List<?>)fieldOfType(page,List.class)){
        String value=text(token);actual.append(value);JSONObject t=new JSONObject();t.put("text",value);boolean hasBox=false;
        for(Field cf:token.getClass().getDeclaredFields())if(cf.getType()==Double.class){cf.setAccessible(true);Object confidence=cf.get(token);t.put("confidence",confidence==null?JSONObject.NULL:confidence);if(confidence!=null)valid&=Double.isFinite((Double)confidence)&&(Double)confidence>=0&&(Double)confidence<=1;}

        for(Field field:token.getClass().getDeclaredFields()){
          field.setAccessible(true);Object v=field.get(token);if(v==null||v instanceof String||v instanceof Number)continue;
          String b=v.toString();if(b.startsWith("OcrBox(")){hasBox=true;t.put("box",b);java.util.regex.Matcher m=java.util.regex.Pattern.compile("[=]([^,)]+)").matcher(b);double[] a=new double[4];int n=0;while(m.find()&&n<4)a[n++]=Double.parseDouble(m.group(1));valid&=n==4&&Double.isFinite(a[0])&&Double.isFinite(a[1])&&a[0]>=0&&a[1]>=0&&a[2]>0&&a[3]>0&&a[0]+a[2]<=1.00001&&a[1]+a[3]<=1.00001;}
        }valid &= hasBox;tokens.put(t);
      }
      String expected=String.join("",gold).replaceAll("\\s+","");String observed=actual.toString().replaceAll("\\s+","");int exact=0;for(String line:gold)if(observed.contains(line.replaceAll("\\s+","")))exact++;
      JSONObject row=new JSONObject();row.put("kind",kind);row.put("width", imageWidth);row.put("height",imageHeight);row.put("synthetic",true);row.put("sha256",hash(jpeg));row.put("gold",new JSONArray(gold));JSONArray boxes=new JSONArray();for(RectF box:goldBoxes)boxes.put(new JSONArray(Arrays.asList(box.left,box.top,box.right,box.bottom)));row.put("goldBoxes",boxes);row.put("tokens",tokens);row.put("elapsedMs",ms);row.put("exactFields",exact);row.put("totalFields",gold.size());row.put("orderedCharacterEdits",distance(expected,observed));row.put("goldCharacters",expected.length());row.put("boxesInUnit",valid);rows.put(row);
    }}finally{monitor.set(false);sampler.join();}
    out.put("runs",rows);out.put("initialPssKB",initialPss);out.put("peakPssKB",peak.get());
    AtomicBoolean cancel=new AtomicBoolean(false);Object finalImage=last;AtomicReference<Throwable> failure=new AtomicReference<>();
    Thread job=new Thread(()->{try{recognize.invoke(oc.newInstance(ctx),Collections.singletonList(finalImage),cancel);}catch(Throwable e){failure.set(e instanceof InvocationTargetException?e.getCause():e);}});job.start();SystemClock.sleep(150);long now=SystemClock.elapsedRealtime();cancel.set(true);job.join(3000);out.put("cancelJoined",!job.isAlive());out.put("cancelLatencyMs",SystemClock.elapsedRealtime()-now);out.put("cancelError",String.valueOf(failure.get()));
    try {recognize.invoke(oc.newInstance(ctx),Collections.singletonList(ic.newInstance(new byte[]{1,2,3},"image/jpeg")),new AtomicBoolean(false));throw new IllegalStateException("Invalid image accepted");}catch(InvocationTargetException bad){out.put("invalidImageError",bad.getCause().toString());}
    try {recognize.invoke(oc.newInstance(ctx),Collections.singletonList(last),new AtomicBoolean(true));throw new IllegalStateException("Pre-cancel accepted");}catch(InvocationTargetException cancelled){out.put("preCancelError",cancelled.getCause().toString());}
    Bitmap blank=Bitmap.createBitmap(640,480,Bitmap.Config.ARGB_8888);new Canvas(blank).drawColor(Color.WHITE);ByteArrayOutputStream blankBytes=new ByteArrayOutputStream();blank.compress(Bitmap.CompressFormat.JPEG,95,blankBytes);blank.recycle();
    List<?> blankPages=(List<?>)recognize.invoke(oc.newInstance(ctx),Collections.singletonList(ic.newInstance(blankBytes.toByteArray(),"image/jpeg")),new AtomicBoolean(false));int blankCount=0;for(Object page:blankPages)blankCount+=((List<?>)fieldOfType(page,List.class)).size();out.put("blankTokens",blankCount);if(blankCount!=0)throw new IllegalStateException("Blank hallucination");
    out.put("networkEnd",String.valueOf(net.getActiveNetwork()));if(net.getActiveNetwork()!=null)throw new IllegalStateException("Network became active");out.put("status","EXECUTED_SYNTHETIC_BENCHMARK");bundle.putString("result",out.toString());finish(-1,bundle);
  }catch(Throwable e){try{out.put("status","FAIL");out.put("error",e.toString());out.put("cause",String.valueOf(e.getCause()));}catch(Exception ignored){}bundle.putString("result",out.toString());finish(1,bundle);}}
}
