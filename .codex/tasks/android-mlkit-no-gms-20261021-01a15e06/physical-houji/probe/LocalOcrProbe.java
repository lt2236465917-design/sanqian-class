package probe;
import android.app.Instrumentation;
import android.os.Bundle;
import android.os.SystemClock;
import android.graphics.*;
import android.net.ConnectivityManager;
import android.content.Context;
import org.json.*;
import java.util.*;
import java.io.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.concurrent.atomic.AtomicBoolean;

// Only for release APK 1c2f3a90... using its saved R8 mapping. No network client or model copy.
public final class LocalOcrProbe extends Instrumentation {
  @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
  private boolean present(String pkg) {
    try { getTargetContext().getPackageManager().getPackageInfo(pkg,0); return true; }
    catch (android.content.pm.PackageManager.NameNotFoundException e) { return false; }
  }
  private static String hash(byte[] data) throws Exception {
    StringBuilder s=new StringBuilder(); for(byte b:MessageDigest.getInstance("SHA-256").digest(data)) s.append(String.format("%02x",b)); return s.toString();
  }
  @Override public void onStart() {
    JSONObject output=new JSONObject(); Bundle result=new Bundle();
    try {
      Context ctx=getTargetContext();
      output.put("targetPackage",ctx.getPackageName());
      output.put("sdk",android.os.Build.VERSION.SDK_INT);
      output.put("abi",android.os.Build.SUPPORTED_ABIS[0]);
      output.put("gmsPresent",present("com.google.android.gms"));
      output.put("vendingPresent",present("com.android.vending"));
      ConnectivityManager cm=(ConnectivityManager)ctx.getSystemService(Context.CONNECTIVITY_SERVICE);
      output.put("activeNetwork",String.valueOf(cm.getActiveNetwork()));
      if(cm.getActiveNetwork()!=null) throw new IllegalStateException("Physical device is not offline");
      Bitmap bitmap=Bitmap.createBitmap(1600,900,Bitmap.Config.ARGB_8888);
      Canvas canvas=new Canvas(bitmap); canvas.drawColor(Color.WHITE);
      Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG); paint.setColor(Color.BLACK); paint.setTextSize(56); paint.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));
      String[] lines={"三千上课 课程表","星期一 高等数学","第一节 08:00-09:35","教学楼 A101","星期二 大学英语","教师 张老师"};
      for(int i=0;i<lines.length;i++) canvas.drawText(lines[i],80,110+i*125,paint);
      ByteArrayOutputStream bytes=new ByteArrayOutputStream(); bitmap.compress(Bitmap.CompressFormat.JPEG,95,bytes); byte[] jpeg=bytes.toByteArray(); bitmap.recycle();
      output.put("sampleType","synthetic Chinese timetable text, Android Canvas, JPEG 1600x900");
      output.put("sampleSha256",hash(jpeg)); output.put("expectedLines",new JSONArray(Arrays.asList(lines)));
      ClassLoader loader=ctx.getClassLoader();
      Class<?> imageClass=loader.loadClass("n5.a");
      Constructor<?> imageConstructor=imageClass.getDeclaredConstructor(byte[].class,String.class); imageConstructor.setAccessible(true);
      Object input=imageConstructor.newInstance(jpeg,"image/jpeg");
      Class<?> ocrClass=loader.loadClass("love.sanqian.schedule.d");
      Constructor<?> ocrConstructor=ocrClass.getDeclaredConstructor(); ocrConstructor.setAccessible(true);
      Method recognize=ocrClass.getDeclaredMethod("b",List.class,AtomicBoolean.class); recognize.setAccessible(true);
      JSONArray runs=new JSONArray();
      for(int run=0;run<2;run++) {
        long start=SystemClock.elapsedRealtime();
        List<?> pages=(List<?>)recognize.invoke(ocrConstructor.newInstance(),Collections.singletonList(input),new AtomicBoolean(false));
        long elapsed=SystemClock.elapsedRealtime()-start; JSONArray tokens=new JSONArray(); StringBuilder recognized=new StringBuilder();
        for(Object page:pages) {
          Method getTokens=page.getClass().getDeclaredMethod("b"); getTokens.setAccessible(true);
          for(Object token:(List<?>)getTokens.invoke(page)) {
            Method getText=token.getClass().getDeclaredMethod("f"); getText.setAccessible(true);
            String txt=(String)getText.invoke(token); tokens.put(txt); recognized.append(txt);
          }
        }
        boolean pass=recognized.toString().contains("高等数学")&&recognized.toString().contains("大学英语")&&recognized.toString().contains("A101");
        JSONObject row=new JSONObject(); row.put("run",run+1); row.put("elapsedMs",elapsed); row.put("pageCount",pages.size()); row.put("tokens",tokens); row.put("keyTextMatched",pass); runs.put(row);
        if(!pass) throw new IllegalStateException("Expected text not recognized: "+recognized);
      }
      output.put("runs",runs); output.put("status","PASS_PHYSICAL_OFFLINE_LOCAL_RELEASE_METHOD_ONLY_GMS_PRESENT");
      result.putString("result",output.toString()); finish(-1,result);
    } catch(Throwable failure) {
      try { output.put("status","FAIL"); output.put("error",failure.toString()); if(failure.getCause()!=null) output.put("cause",failure.getCause().toString()); } catch(Exception ignored){}
      result.putString("result",output.toString()); finish(1,result);
    }
  }
}