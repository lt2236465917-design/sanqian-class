package com.lilystudio.wheretosleepinnju

/**
 * Web storage and cookies must finish before a portal WebView is created.
 * The cookie callback Boolean means a cookie was removed, not that cleanup
 * failed. An empty store still calls [onReady]. A thrown error stays
 * retryable and does not call [onReady].
 */
object PortalStorageReset {
    fun reset(
        deleteWebStorage: () -> Unit,
        removeAllCookies: (((Boolean) -> Unit) -> Unit),
        onReady: () -> Unit,
        onFailure: (String) -> Unit,
    ) {
        try {
            deleteWebStorage()
        } catch (_: Exception) {
            onFailure("无法清除网页存储，门户未打开。请点底部「重试」。")
            return
        }
        try {
            removeAllCookies { _ ->
                onReady()
            }
        } catch (_: Exception) {
            onFailure("无法清除登录 Cookie，门户未打开。请点底部「重试」。")
        }
    }
}

/**
 * A cleanup callback can arrive after the activity is destroyed without
 * [android.app.Activity.isFinishing] being true, which happens on recreate.
 * [epoch] is the attempt that started cleanup. [currentEpoch] advances when
 * that attempt is no longer allowed to create a portal.
 */
fun portalCleanupMayOpen(
    epoch: Int,
    currentEpoch: Int,
    finishing: Boolean,
    destroyed: Boolean,
): Boolean = epoch == currentEpoch && !finishing && !destroyed
