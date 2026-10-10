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

-keep class local.sanqian.schedule.ScheduleWidgetProvider { *; }
-keep class local.sanqian.schedule.ScheduleWidgetRefreshReceiver { *; }
-keep class local.sanqian.schedule.ScheduleWidgetBootReceiver { *; }
-keep class local.sanqian.schedule.ScheduleReminderReceiver { *; }
-keep class local.sanqian.schedule.ScheduleReminderScheduler { *; }
-keep class local.sanqian.schedule.ScheduleImportPlugin { *; }
