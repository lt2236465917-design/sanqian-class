-keep class com.umeng.** {*;}

-keep class com.uc.** {*;}

-keepclassmembers class * {
   public <init> (org.json.JSONObject);
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-keep class com.zui.** {*;}
-keep class com.miui.** {*;}
-keep class com.heytap.** {*;}
-keep class a.** {*;}
-keep class com.vivo.** {*;}

-keep class com.lilystudio.wheretosleepinnju.ScheduleWidgetProvider { *; }
-keep class com.lilystudio.wheretosleepinnju.ScheduleWidgetRefreshReceiver { *; }
-keep class com.lilystudio.wheretosleepinnju.ScheduleWidgetBootReceiver { *; }
-keep class com.lilystudio.wheretosleepinnju.ScheduleReminderReceiver { *; }
-keep class com.lilystudio.wheretosleepinnju.ScheduleReminderScheduler { *; }
-keep class com.lilystudio.wheretosleepinnju.ScheduleImportPlugin { *; }
-keep class com.lilystudio.wheretosleepinnju.MlKitChineseTimetableOcr { *; }
