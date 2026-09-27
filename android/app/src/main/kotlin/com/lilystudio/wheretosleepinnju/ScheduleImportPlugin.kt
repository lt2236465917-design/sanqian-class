package com.lilystudio.wheretosleepinnju

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONObject
import java.net.HttpURLConnection
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class ScheduleImportPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var store: ScheduleCredentialsStore
    private var appContext: android.content.Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val generation = java.util.concurrent.atomic.AtomicInteger(0)
    private val connection = AtomicReference<HttpURLConnection?>(null)
    private var running: Future<*>? = null
    private val bridge = PendingBridgeResults()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        store = ScheduleCredentialsStore.get(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        abandonPending("插件已卸载")
        if (this::channel.isInitialized) channel.setMethodCallHandler(null)
        appContext = null
        executor.shutdownNow()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachHostKeepingPortal()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        // The school portal is a second Activity. Android destroys this stopped
        // host while that page is still open. The openPortal call has to stay
        // pending so the timetable can be delivered to the same Dart isolate.
        detachHostKeepingPortal()
    }

    private fun detachHostKeepingPortal() {
        generation.incrementAndGet()
        cancelRecognition()
        running?.cancel(true)
        running = null
        busy.set(false)
        bridge.cancelAllExcept(setOf("portal"), "cancelled", "界面已销毁")
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasAPIKey" -> result.success(store.hasDeepSeekAPIKey())
                "saveAPIKey" -> {
                    store.saveDeepSeekAPIKey(call.argument<String>("key") ?: "")
                    result.success(true)
                }
                "deleteAPIKey" -> {
                    store.deleteDeepSeekAPIKey()
                    result.success(true)
                }
                "schoolAccount" -> {
                    val info = store.schoolAccountMetadata()
                    result.success(info?.let { mapOf("account" to it.account, "accountLocalId" to it.accountLocalId) })
                }
                "saveSchoolAccount" -> {
                    val info = store.saveSchoolCredentials(
                        call.argument<String>("account") ?: "",
                        call.argument<String>("password") ?: ""
                    )
                    result.success(mapOf("account" to info.account, "accountLocalId" to info.accountLocalId))
                }
                "deleteSchoolAccount" -> {
                    store.deleteSchoolCredentials()
                    result.success(true)
                }
                "loadLegacyJwCredentials" -> {
                    val saved = store.loadLegacyJw()
                    result.success(saved?.let { mapOf("username" to it.first, "password" to it.second) })
                }
                "saveLegacyJwCredentials" -> {
                    store.saveLegacyJw(
                        call.argument<String>("username") ?: "",
                        call.argument<String>("password") ?: ""
                    )
                    result.success(true)
                }
                "deleteLegacyJwCredentials" -> {
                    store.deleteLegacyJw()
                    result.success(true)
                }
                "openPortal" -> openPortal(result)
                "cancelRecognition" -> {
                    cancelRecognition()
                    result.success(true)
                }
                "recognizeText" -> recognize(result) { client ->
                    client.recognizeText(call.argument<String>("text") ?: "")
                }
                "recognizePhotos" -> recognize(result) { client ->
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    if (paths.isEmpty() || paths.size > 20) throw ImportBridgeError.images
                    val images = paths.mapIndexed { index, path ->
                        if (cancelled.get()) throw DeepSeekTimetableClientError.Cancelled
                        DeepSeekTimetableClient.jpegFromPath(path, index)
                    }
                    client.recognizeImages(images)
                }
                "requestReminderPermission" -> requestReminderPermission(result)
                "clearLegacyReminders" -> {
                    val context = appContext ?: throw IllegalStateException("暂时无法清理旧提醒，请重试。")
                    ScheduleReminderScheduler(context).clear()
                    result.success(true)
                }
                "syncDerivedData" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    result.success(syncDerivedData(args))
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error(code(error), error.message, null)
        }
    }

    private fun openPortal(result: MethodChannel.Result) {
        val current = activity
        if (current == null || bridge.contains("portal")) {
            result.error("schedule_import", ImportBridgeError.unavailable.message, null)
            return
        }
        val reply = bridge.track("portal", replyOf(result))
        try {
            current.startActivityForResult(Intent(current, SchoolPortalActivity::class.java), REQUEST_PORTAL)
        } catch (error: Exception) {
            reply.error("schedule_import", error.message)
        }
    }

    private fun recognize(result: MethodChannel.Result, work: (DeepSeekTimetableClient) -> DeepSeekTimetableResult) {
        if (!busy.compareAndSet(false, true)) {
            result.error("schedule_import", ImportBridgeError.busy.message, null)
            return
        }
        cancelled.set(false)
        val ticket = generation.incrementAndGet()
        val reply = bridge.track("recognize", replyOf(result))
        running = executor.submit {
            try {
                val key = store.loadDeepSeekAPIKey() ?: throw DeepSeekTimetableClientError.MissingAPIKey
                val client = DeepSeekTimetableClient(key, cancelled) { connection.set(it) }
                val output = work(client)
                if (cancelled.get() || generation.get() != ticket) throw DeepSeekTimetableClientError.Cancelled
                val parsed = DeepSeekTimetableClient.jsonToAny(JSONObject(output.jsonText))
                if (generation.get() == ticket) finish(reply, parsed, null)
            } catch (error: Exception) {
                if (generation.get() == ticket) finish(reply, null, error)
            } finally {
                if (generation.get() == ticket) {
                    connection.set(null)
                    busy.set(false)
                }
            }
        }
    }

    private fun finish(reply: OnceBridgeResult, success: Any?, error: Exception?) {
        mainHandler.post {
            if (error != null) reply.error(code(error), error.message)
            else reply.success(success)
        }
    }

    private fun abandonPending(message: String) {
        generation.incrementAndGet()
        cancelRecognition()
        running?.cancel(true)
        running = null
        bridge.cancelAll("cancelled", message)
        busy.set(false)
    }

    private fun replyOf(result: MethodChannel.Result) = object : BridgeReply {
        override fun success(value: Any?) {
            result.success(value)
        }

        override fun error(code: String, message: String?) {
            result.error(code, message, null)
        }
    }

    private fun cancelRecognition() {
        cancelled.set(true)
        connection.getAndSet(null)?.disconnect()
    }

    private fun requestReminderPermission(result: MethodChannel.Result) {
        val current = activity
        if (current == null) {
            result.error("notification_permission", "当前无法请求通知权限", null)
            return
        }
        if (Build.VERSION.SDK_INT < 33) {
            result.success(NotificationReady.enabled(current))
            return
        }
        if (ContextCompat.checkSelfPermission(current, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (bridge.contains("permission")) {
            result.error("notification_permission", "正在请求通知权限", null)
            return
        }
        bridge.track("permission", replyOf(result))
        ActivityCompat.requestPermissions(current, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFY)
    }

    private fun syncDerivedData(args: Map<*, *>): Map<String, Any?> {
        val context = appContext ?: return mapOf("widgetError" to "桌面小组件暂时无法更新")
        try {
            ScheduleWidgetStore.write(context, args)
        } catch (_: Exception) {
            return mapOf("widgetError" to "共享课表写入失败")
        }
        return try {
            ScheduleWidgetUpdater.refresh(context)
            emptyMap()
        } catch (_: Exception) {
            mapOf("widgetError" to "桌面小组件暂时无法刷新")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PORTAL) return false
        val pending = bridge.take("portal") ?: return true
        if (resultCode != Activity.RESULT_OK) {
            PortalResultBus.clear()
            pending.success(null)
            return true
        }
        val token = data?.getStringExtra(SchoolPortalActivity.EXTRA_RESULT)
        val json = if (token == PortalResultBus.TOKEN) PortalResultBus.consume() else token
        if (json.isNullOrEmpty() || json == PortalResultBus.TOKEN) {
            pending.success(null)
            return true
        }
        try {
            pending.success(DeepSeekTimetableClient.jsonToAny(JSONObject(json)))
        } catch (error: Exception) {
            pending.error("schedule_import", error.message)
        }
        return true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_NOTIFY) return false
        val pending = bridge.take("permission") ?: return true
        pending.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        return true
    }

    private fun code(error: Exception): String {
        return when (error) {
            is DeepSeekTimetableClientError -> "recognition"
            else -> "schedule_import"
        }
    }

    companion object {
        const val CHANNEL = "sanqian/schedule_import"
        private const val REQUEST_PORTAL = 0x51A1
        private const val REQUEST_NOTIFY = 0x51A2
    }
}

private object NotificationReady {
    fun enabled(activity: Activity): Boolean {
        return androidx.core.app.NotificationManagerCompat.from(activity).areNotificationsEnabled()
    }
}
