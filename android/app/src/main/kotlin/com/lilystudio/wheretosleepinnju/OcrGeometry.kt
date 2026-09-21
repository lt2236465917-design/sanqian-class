package com.lilystudio.wheretosleepinnju

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
}
