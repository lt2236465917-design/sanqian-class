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
import java.io.File
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
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val generation = java.util.concurrent.atomic.AtomicInteger(0)
    private val connection = AtomicReference<HttpURLConnection?>(null)
    private var running: Future<*>? = null
    private var portalResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        store = ScheduleCredentialsStore.get(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
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
        if (current == null || portalResult != null) {
            result.error("schedule_import", ImportBridgeError.unavailable.message, null)
            return
        }
        portalResult = result
        current.startActivityForResult(Intent(current, SchoolPortalActivity::class.java), REQUEST_PORTAL)
    }

    private fun recognize(result: MethodChannel.Result, work: (DeepSeekTimetableClient) -> DeepSeekTimetableResult) {
        if (!busy.compareAndSet(false, true)) {
            result.error("schedule_import", ImportBridgeError.busy.message, null)
            return
        }
        cancelled.set(false)
        val ticket = generation.incrementAndGet()
        running = executor.submit {
            try {
                val key = store.loadDeepSeekAPIKey() ?: throw DeepSeekTimetableClientError.MissingAPIKey
                val client = DeepSeekTimetableClient(key, cancelled) { connection.set(it) }
                val output = work(client)
                if (cancelled.get() || generation.get() != ticket) throw DeepSeekTimetableClientError.Cancelled
                val parsed = DeepSeekTimetableClient.jsonToAny(JSONObject(output.jsonText))
                if (generation.get() == ticket) complete(result, success = parsed, error = null)
            } catch (error: Exception) {
                if (generation.get() == ticket) complete(result, success = null, error = error)
            } finally {
                if (generation.get() == ticket) {
                    connection.set(null)
                    busy.set(false)
                }
            }
        }
    }

    private fun complete(result: MethodChannel.Result, success: Any?, error: Exception?) {
        mainHandler.post {
            if (error != null) result.error(code(error), error.message, null)
            else result.success(success)
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
        if (permissionResult != null) {
            result.error("notification_permission", "正在请求通知权限", null)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(current, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFY)
    }

    private fun syncDerivedData(args: Map<*, *>): Map<String, Any?> {
        var widgetError: String? = "Android 桌面组件尚未接入"
        val activityContext = activity?.applicationContext
        if (activityContext != null) {
            try {
                val safe = mapOf(
                    "schemaVersion" to 1,
                    "tableId" to (args["tableId"] ?: 0),
                    "revision" to (args["revision"] ?: ""),
                    "generatedAtMs" to (args["generatedAtMs"] ?: 0),
                    "occurrences" to (args["occurrences"] ?: emptyList<Any>())
                )
                val file = File(activityContext.filesDir, "personal-schedule.json")
                file.writeText(toJsonValue(safe).toString())
            } catch (_: Exception) {
                widgetError = "共享课表写入失败"
            }
        }
        val occurrences = (args["occurrences"] as? List<*>)?.mapNotNull { row ->
            (row as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value }
        } ?: emptyList()
        val leads = (args["leadMinutes"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() } ?: emptyList()
        val context = activityContext ?: return mapOf("widgetError" to widgetError, "count" to 0, "permission" to "denied")
        val status = ScheduleReminderScheduler(context).replace(occurrences, leads).toMutableMap()
        status["widgetError"] = widgetError
        return status
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PORTAL) return false
        val pending = portalResult ?: return true
        portalResult = null
        if (resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return true
        }
        val json = data?.getStringExtra(SchoolPortalActivity.EXTRA_RESULT)
        if (json.isNullOrEmpty()) {
            pending.success(null)
            return true
        }
        try {
            pending.success(DeepSeekTimetableClient.jsonToAny(JSONObject(json)))
        } catch (error: Exception) {
            pending.error("schedule_import", error.message, null)
        }
        return true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_NOTIFY) return false
        val pending = permissionResult ?: return true
        permissionResult = null
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
