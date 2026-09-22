package com.lilystudio.wheretosleepinnju;

import android.content.Intent;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;


public class MainActivity extends FlutterActivity {
    private MethodChannel scheduleWidgetChannel;

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (intent.getBooleanExtra(ScheduleWidgetUpdater.EXTRA_OPEN_SCHEDULE, false)) {
            intent.removeExtra(ScheduleWidgetUpdater.EXTRA_OPEN_SCHEDULE);
            if (scheduleWidgetChannel != null) {
                scheduleWidgetChannel.invokeMethod("openSchedule", null);
            }
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        flutterEngine.getPlugins().add(new ScheduleImportPlugin());
        scheduleWidgetChannel = new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            "sanqian/widget"
        );
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "sanqian/settings")
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("openAppSettings")) {
                    try {
                        startActivity(new android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:" + getPackageName())));
                        result.success(true);
                    } catch (Exception error) { result.success(false); }
                } else { result.notImplemented(); }
            });
    }

//    @Override
//    public void configureFlutterEngine(FlutterEngine flutterEngine) {
//        GeneratedPluginRegistrant.registerWith(flutterEngine);
//    }
//
//    @Override
//    protected void onCreate(Bundle savedInstanceState) {
//        super.onCreate(savedInstanceState);
//        com.lilystudio.wheretosleepinnju.UmengSdkPlugin.setContext(this);
//        android.util.Log.i("UMLog", "onCreate@MainActivity");
//    }
//
//    @Override
//    protected void onPause() {
//        super.onPause();
//        MobclickAgent.onPause(this);
//        android.util.Log.i("UMLog", "onPause@MainActivity");
//    }
//
//    @Override
//    protected void onResume() {
//        super.onResume();
//        MobclickAgent.onResume(this);
//        android.util.Log.i("UMLog", "onResume@MainActivity");
//    }
}
