package love.sanqian.schedule

/**
 * Hands a parsed timetable to the Flutter host.
 *
 * [offer] must keep the payload in process memory. [finish] only carries a
 * short token. A school WebView's saved state can make [finish] throw before
 * the activity is marked finished; the payload stays stored so a second
 * attempt can still deliver it.
 */
internal object PortalResultHandoff {
    fun deliver(
        json: String,
        offer: (String) -> Boolean,
        detachViews: () -> Unit,
        finish: () -> Unit
    ): String? {
        if (!offer(json)) {
            return "这次读到的课表太长，没有带回。请分页面读取，或改用多图课表导入。"
        }
        return try {
            finish()
            null
        } catch (_: Throwable) {
            try {
                detachViews()
                finish()
                null
            } catch (_: Throwable) {
                "课表已经读到，但页面没能关闭。请点底部「读取并识别」再试一次。"
            }
        }
    }
}
