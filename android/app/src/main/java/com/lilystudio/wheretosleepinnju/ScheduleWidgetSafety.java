package com.lilystudio.wheretosleepinnju;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.os.Bundle;

/** Xiaomi's AppWidgetManager can return null ids or options during a package replace. */
public final class ScheduleWidgetSafety {
    private ScheduleWidgetSafety() {}

    public static int[] widgetIds(Context context) {
        if (context == null) return new int[0];
        Context app = context.getApplicationContext() != null ? context.getApplicationContext() : context;
        try {
            AppWidgetManager manager = AppWidgetManager.getInstance(app);
            if (manager == null) return new int[0];
            return ScheduleWidgetIds.usable(
                manager.getAppWidgetIds(new ComponentName(app, ScheduleWidgetProvider.class))
            );
        } catch (Throwable ignored) {
            return new int[0];
        }
    }

    public static Bundle options(AppWidgetManager manager, int widgetId) {
        if (manager == null) return new Bundle();
        try {
            Bundle options = manager.getAppWidgetOptions(widgetId);
            return options == null ? new Bundle() : options;
        } catch (Throwable ignored) {
            return new Bundle();
        }
    }
}
