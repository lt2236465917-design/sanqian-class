package com.lilystudio.wheretosleepinnju;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Runs on update, boot, and clock changes. A failure here must not flash-crash the app. */
public class ScheduleWidgetBootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
            || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
            || Intent.ACTION_TIME_CHANGED.equals(action)
            || Intent.ACTION_TIMEZONE_CHANGED.equals(action)) {
            ScheduleWidgetUpdater.INSTANCE.refresh(context);
        }
    }
}
