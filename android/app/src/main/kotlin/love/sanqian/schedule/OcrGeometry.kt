package love.sanqian.schedule

import kotlin.math.roundToInt

/**
 * Maps a pixel rectangle into the upright image, using the same orientation
 * cases as [DeepSeekTimetableClient]'s EXIF rotation. Origin is the top left.
 * Bitmap.createBitmap shifts the rotated bounds so the result stays positive.
 */
internal object OcrGeometry {
    const val NORMAL = 1
    const val FLIP_HORIZONTAL = 2
    const val ROTATE_180 = 3
    const val FLIP_VERTICAL = 4
    const val TRANSPOSE = 5
    const val ROTATE_90 = 6
    const val TRANSVERSE = 7
    const val ROTATE_270 = 8

    fun uprightSize(width: Int, height: Int, orientation: Int): Pair<Int, Int> {
        return when (orientation) {
            ROTATE_90, ROTATE_270, TRANSPOSE, TRANSVERSE -> height to width
            else -> width to height
        }
    }

    fun normalize(
        left: Double,
        top: Double,
        right: Double,
        bottom: Double,
        width: Int,
        height: Int,
        orientation: Int = NORMAL,
    ): OcrBox {
        val (uprightWidth, uprightHeight) = uprightSize(width, height, orientation)
        val corners = listOf(
            left to top,
            right to top,
            right to bottom,
            left to bottom,
        ).map { (x, y) -> uprightPoint(x, y, width, height, orientation) }
        val minX = corners.minOf { it.first }
        val minY = corners.minOf { it.second }
        val maxX = corners.maxOf { it.first }
        val maxY = corners.maxOf { it.second }
        return OcrBox(
            x = minX / uprightWidth,
            y = minY / uprightHeight,
            width = (maxX - minX) / uprightWidth,
            height = (maxY - minY) / uprightHeight,
        )
    }

    fun uprightPoint(x: Double, y: Double, width: Int, height: Int, orientation: Int): Pair<Double, Double> {
        val w = width.toDouble()
        val h = height.toDouble()
        return when (orientation) {
            ROTATE_90 -> (h - y) to x
            ROTATE_180 -> (w - x) to (h - y)
            ROTATE_270 -> y to (w - x)
            FLIP_HORIZONTAL -> (w - x) to y
            FLIP_VERTICAL -> x to (h - y)
            TRANSPOSE -> y to x
            TRANSVERSE -> (h - y) to (w - x)
            else -> x to y
        }
    }

    fun rounded(value: Double): Double {
        return (value.coerceIn(0.0, 1.0) * 10000.0).roundToInt() / 10000.0
    }

    /**
     * Recognition rectangles can extend slightly past the bitmap. Pull a
     * near-edge box back into the unit square. A box that misses the image,
     * or sticks out by more than about one percent, is dropped instead of
     * failing the whole review.
     */
    fun clipToUnit(box: OcrBox): OcrBox? {
        val values = listOf(box.x, box.y, box.width, box.height)
        if (values.any { !it.isFinite() } || box.width <= 0.0 || box.height <= 0.0) return null
        val slack = 0.01
        if (box.x < -slack || box.y < -slack || box.x > 1.0 + slack || box.y > 1.0 + slack) {
            return null
        }
        if (box.x + box.width > 1.0 + slack || box.y + box.height > 1.0 + slack) return null
        val x = box.x.coerceIn(0.0, 1.0)
        val y = box.y.coerceIn(0.0, 1.0)
        val right = (box.x + box.width).coerceIn(0.0, 1.0)
        val bottom = (box.y + box.height).coerceIn(0.0, 1.0)
        val width = right - x
        val height = bottom - y
        if (width <= 0.0 || height <= 0.0) return null
        return OcrBox(x, y, width, height)
    }
}
