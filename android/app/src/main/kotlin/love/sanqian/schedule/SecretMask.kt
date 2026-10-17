package love.sanqian.schedule

object SecretMask {
    const val PLACEHOLDER = "••••••••"

    fun apiKey(raw: String): String {
        val value = raw.trim()
        if (value.length <= 8) return PLACEHOLDER
        return value.take(3) + "••••" + value.takeLast(4)
    }
}
