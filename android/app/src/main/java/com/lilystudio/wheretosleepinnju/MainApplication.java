package com.lilystudio.wheretosleepinnju;

/** Personal timetable: no upstream analytics initialization. */
public class MainApplication extends android.app.Application {
    @Override
    public void onCreate() {
        super.onCreate();
        // ML Kit's startup provider throws NullPointerException on some Xiaomi
        // and Android 11 devices while the process is coming up after install.
        // Initialize here so a failure stays inside the app instead of 闪退.
        try {
            com.google.mlkit.common.MlKit.initialize(this);
        } catch (Throwable ignored) {
        }
    }
}
