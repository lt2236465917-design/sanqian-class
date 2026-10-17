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

-keep class love.sanqian.schedule.ScheduleWidgetProvider { *; }
-keep class love.sanqian.schedule.ScheduleWidgetRefreshReceiver { *; }
-keep class love.sanqian.schedule.ScheduleWidgetBootReceiver { *; }
-keep class love.sanqian.schedule.ScheduleReminderReceiver { *; }
-keep class love.sanqian.schedule.ScheduleReminderScheduler { *; }
-keep class love.sanqian.schedule.ScheduleImportPlugin { *; }

# device_calendar serializes native models with Gson field names for Dart.
# R8 renaming breaks calendar/event lookup and can duplicate exported events.
-keep class com.builttoroam.devicecalendar.** { *; }
