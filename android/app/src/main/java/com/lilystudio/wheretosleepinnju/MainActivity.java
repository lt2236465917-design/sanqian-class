package com.lilystudio.wheretosleepinnju;

import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.drawable.BitmapDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.plugin.common.MethodChannel;


public class MainActivity extends FlutterActivity {
    private static final String ENGINE_ID = "sanqian.main";
    private static final String MASCOT_BRIDGE_CHANNEL = "sanqian/mascot_bridge";
    /** Set once the opening poster has been removed. A later Activity recreate must not cover the UI with it. */
    private static boolean openingPosterDismissed;
    private MethodChannel mascotBridgeChannel;
    private MethodChannel scheduleWidgetChannel;
    private MethodChannel settingsChannel;
    private View mascotBridge;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // The platform splash icon is a fixed circle and cannot match the
            // video. Drop it as soon as this window can draw the large logo.
            getSplashScreen().setOnExitAnimationListener(view -> view.remove());
        }
        super.onCreate(savedInstanceState);
        if (!openingPosterDismissed) installMascotBridge();
    }

    @Override
    protected void onDestroy() {
        if (mascotBridgeChannel != null) mascotBridgeChannel.setMethodCallHandler(null);
        if (scheduleWidgetChannel != null) scheduleWidgetChannel.setMethodCallHandler(null);
        if (settingsChannel != null) settingsChannel.setMethodCallHandler(null);
        super.onDestroy();
    }

    /**
     * The school portal sits on top of this Activity. Android can destroy the
     * stopped host while that page is open. Reuse the engine so returning from
     * 「读取并识别」does not rerun Dart and replay the opening animation.
     */
    @Override
    public FlutterEngine provideFlutterEngine(@NonNull Context context) {
        return FlutterEngineCache.getInstance().get(ENGINE_ID);
    }

    @Override
    public boolean shouldDestroyEngineWithHost() {
        return false;
    }

    @Override
    public boolean shouldRestoreAndSaveState() {
        // Restoration would push the saved snapshot into the still-running
        // isolate and replace the page that is waiting for the timetable.
        return false;
    }

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

    private void installMascotBridge() {
        int side = getResources().getDisplayMetrics().widthPixels;
        Bitmap source = BitmapFactory.decodeResource(getResources(), R.drawable.mascot_splash_icon);
        if (source == null) return;
        Bitmap scaled = source.getWidth() == side
                ? source
                : Bitmap.createScaledBitmap(source, side, side, true);
        if (scaled != source) source.recycle();

        BitmapDrawable background = new BitmapDrawable(getResources(), scaled);
        background.setGravity(Gravity.CENTER);
        getWindow().setBackgroundDrawable(background);

        FrameLayout bridge = new FrameLayout(this);
        bridge.setBackgroundColor(Color.WHITE);
        ImageView poster = new ImageView(this);
        poster.setImageBitmap(scaled);
        poster.setScaleType(ImageView.ScaleType.FIT_CENTER);
        bridge.addView(poster, new FrameLayout.LayoutParams(side, side, Gravity.CENTER));
        ((ViewGroup) getWindow().getDecorView()).addView(
                bridge,
                new ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT));
        mascotBridge = bridge;
        mainHandler.postDelayed(this::removeMascotBridge, 12000);
    }

    private void removeMascotBridge() {
        openingPosterDismissed = true;
        mainHandler.removeCallbacksAndMessages(null);
        if (mascotBridge == null) return;
        ViewGroup parent = (ViewGroup) mascotBridge.getParent();
        if (parent != null) parent.removeView(mascotBridge);
        mascotBridge = null;
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine);
        mascotBridgeChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), MASCOT_BRIDGE_CHANNEL);
        mascotBridgeChannel.setMethodCallHandler((call, result) -> {
            if ("flutterPosterReady".equals(call.method)) {
                removeMascotBridge();
                result.success(null);
            } else {
                result.notImplemented();
            }
        });
        if (!flutterEngine.getPlugins().has(ScheduleImportPlugin.class)) {
            flutterEngine.getPlugins().add(new ScheduleImportPlugin());
        }
        scheduleWidgetChannel = new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            "sanqian/widget"
        );
        settingsChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "sanqian/settings");
        settingsChannel.setMethodCallHandler((call, result) -> {
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
