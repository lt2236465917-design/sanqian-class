package com.lilystudio.wheretosleepinnju

/**
 * The portal Activity returns its timetable through the process, not the
 * result Intent. A school timetable easily exceeds the Binder transaction
 * limit, and that exception kills the process while the Activity is finishing.
 * The next launch then replays the opening animation.
 */
internal object PortalResultBus {
    const val TOKEN = "memory"
    const val MAX_CHARS = 350_000

    private var json: String? = null

    fun offer(json: String): Boolean {
        if (json.length > MAX_CHARS) return false
        this.json = json
        return true
    }

    fun consume(): String? {
        val value = json
        json = null
        return value
    }

    fun clear() {
        json = null
    }
}
