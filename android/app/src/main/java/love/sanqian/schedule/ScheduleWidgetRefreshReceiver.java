package love.sanqian.schedule;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class ScheduleWidgetRefreshReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        ScheduleWidgetUpdater.INSTANCE.refresh(context);
    }
}
