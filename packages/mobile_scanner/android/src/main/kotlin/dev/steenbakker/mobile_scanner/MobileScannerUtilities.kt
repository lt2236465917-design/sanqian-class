package dev.steenbakker.mobile_scanner

import android.graphics.Rect
import zxingcpp.BarcodeReader

val BarcodeReader.Result.bounds: Rect
    get() {
        val points = listOf(position.topLeft, position.topRight, position.bottomRight, position.bottomLeft)
        return Rect(points.minOf { it.x }, points.minOf { it.y }, points.maxOf { it.x }, points.maxOf { it.y })
    }

val BarcodeReader.Result.data: Map<String, Any?>
    get() = mapOf(
        "corners" to listOf(position.topLeft, position.topRight, position.bottomRight, position.bottomLeft)
            .map { mapOf("x" to it.x.toDouble(), "y" to it.y.toDouble()) },
        "displayValue" to text,
        "format" to 256,
        "rawBytes" to bytes,
        "rawValue" to text,
        "size" to mapOf("width" to bounds.width().toDouble(), "height" to bounds.height().toDouble()),
        "type" to 7,
    )
