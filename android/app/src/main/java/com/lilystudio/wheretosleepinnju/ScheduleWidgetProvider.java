package com.lilystudio.wheretosleepinnju;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.os.Bundle;

/**
 * Java entry so a Xiaomi launcher can pass a null widget id array without
 * hitting a Kotlin non-null check and killing the process on install.
 */
public class ScheduleWidgetProvider extends AppWidgetProvider {
    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        ScheduleWidgetUpdater.INSTANCE.refresh(context);
    }

    @Override
    public void onAppWidgetOptionsChanged(
        Context context,
        AppWidgetManager appWidgetManager,
        int appWidgetId,
        Bundle newOptions
    ) {
        ScheduleWidgetUpdater.INSTANCE.refresh(context);
    }

    @Override
    public void onEnabled(Context context) {
        ScheduleWidgetUpdater.INSTANCE.refresh(context);
    }

    @Override
    public void onDisabled(Context context) {
        ScheduleWidgetUpdater.INSTANCE.cancelRefresh(context);
    }
}
