package com.lilystudio.wheretosleepinnju

import java.util.concurrent.atomic.AtomicBoolean

interface BridgeReply {
    fun success(value: Any?)
    fun error(code: String, message: String?)
}

/** Completes a Flutter result at most once, including after detach races. */
class OnceBridgeResult(private val raw: BridgeReply) {
    private val done = AtomicBoolean(false)
    var onDone: (() -> Unit)? = null

    fun success(value: Any?): Boolean {
        if (!done.compareAndSet(false, true)) return false
        try {
            raw.success(value)
        } catch (_: Exception) {
        } finally {
            onDone?.invoke()
        }
        return true
    }

    fun error(code: String, message: String?): Boolean {
        if (!done.compareAndSet(false, true)) return false
        try {
            raw.error(code, message)
        } catch (_: Exception) {
        } finally {
            onDone?.invoke()
        }
        return true
    }
}

class PendingBridgeResults {
    private val pending = LinkedHashMap<String, OnceBridgeResult>()

    fun contains(key: String): Boolean = pending.containsKey(key)

    fun take(key: String): OnceBridgeResult? = pending.remove(key)

    fun track(key: String, reply: BridgeReply): OnceBridgeResult {
        val once = OnceBridgeResult(reply)
        once.onDone = {
            if (pending[key] === once) pending.remove(key)
        }
        pending[key] = once
        return once
    }

    fun cancelAll(code: String, message: String): Int {
        val items = pending.values.toList()
        pending.clear()
        var count = 0
        for (item in items) {
            if (item.error(code, message)) count += 1
        }
        return count
    }

    /** Leaves [keep] pending. Used when the host Activity is destroyed underneath the portal. */
    fun cancelAllExcept(keep: Set<String>, code: String, message: String): Int {
        val keys = pending.keys.filter { it !in keep }
        var count = 0
        for (key in keys) {
            val item = pending.remove(key) ?: continue
            if (item.error(code, message)) count += 1
        }
        return count
    }
}
