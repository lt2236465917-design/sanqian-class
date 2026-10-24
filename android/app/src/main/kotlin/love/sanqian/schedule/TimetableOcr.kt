package love.sanqian.schedule

import java.util.concurrent.atomic.AtomicBoolean

fun interface TimetableOcr {
    fun recognize(images: List<AIImportImage>, cancelled: AtomicBoolean): List<OcrPage>
}
