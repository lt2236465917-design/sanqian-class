package com.lilystudio.wheretosleepinnju

import android.app.Activity
import android.os.Build
import java.lang.reflect.Proxy

object PredictiveBack {
    fun register(activity: Activity, onBack: () -> Unit): Any? {
        if (Build.VERSION.SDK_INT < 33) return null
        return try {
            val callbackClass = Class.forName("android.window.OnBackInvokedCallback")
            val callback = Proxy.newProxyInstance(
                callbackClass.classLoader,
                arrayOf(callbackClass),
            ) { proxy, method, args ->
                // The framework stores this callback in a HashMap. hashCode and
                // equals must return real values; a null int crashes on attach.
                predictiveBackResult(proxy, method.name, args, onBack)
            }
            val dispatcher = Activity::class.java.getMethod("getOnBackInvokedDispatcher").invoke(activity)
            dispatcher.javaClass.getMethod(
                "registerOnBackInvokedCallback",
                Int::class.javaPrimitiveType,
                callbackClass,
            ).invoke(dispatcher, 0, callback)
            callback
        } catch (_: Exception) {
            null
        }
    }

    fun unregister(activity: Activity, handle: Any?) {
        if (Build.VERSION.SDK_INT < 33 || handle == null) return
        try {
            val callbackClass = Class.forName("android.window.OnBackInvokedCallback")
            val dispatcher = Activity::class.java.getMethod("getOnBackInvokedDispatcher").invoke(activity)
            dispatcher.javaClass.getMethod(
                "unregisterOnBackInvokedCallback",
                callbackClass,
            ).invoke(dispatcher, handle)
        } catch (_: Exception) {
            // The cancel button still leaves the portal.
        }
    }
}

internal fun predictiveBackResult(
    proxy: Any,
    methodName: String,
    args: Array<Any?>?,
    onBack: () -> Unit,
): Any? {
    return when (methodName) {
        "onBackInvoked" -> {
            onBack()
            null
        }
        "hashCode" -> System.identityHashCode(proxy)
        "equals" -> proxy === args?.firstOrNull()
        "toString" -> "OnBackInvokedCallback"
        else -> null
    }
}
