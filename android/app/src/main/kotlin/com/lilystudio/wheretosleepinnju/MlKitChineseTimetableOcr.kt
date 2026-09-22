package com.lilystudio.wheretosleepinnju

import android.graphics.BitmapFactory
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

fun interface TimetableOcr {
    fun recognize(images: List<AIImportImage>, cancelled: AtomicBoolean): List<OcrPage>
}

/**
 * Bundled ML Kit Chinese recognizer. The model is inside the APK.
 * It is constructed only after the user asks for OCR review, and it reads the
 * same upright JPEG bytes that the default photo request sends.
 * Chinese on-device recognition does not provide a real confidence score; values
 * below zero stay null instead of a fabricated score.
 */
class MlKitChineseTimetableOcr : TimetableOcr {
    override fun recognize(images: List<AIImportImage>, cancelled: AtomicBoolean): List<OcrPage> {
        try {
            return recognizeSafely(images, cancelled)
        } catch (error: DeepSeekTimetableClientError) {
            throw error
        } catch (_: Throwable) {
            throw DeepSeekTimetableClientError.InvalidOCRContext
        }
    }

    private fun recognizeSafely(images: List<AIImportImage>, cancelled: AtomicBoolean): List<OcrPage> {
        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        try {
            return images.mapIndexed { index, image ->
                if (cancelled.get()) throw DeepSeekTimetableClientError.Cancelled
                val bitmap = BitmapFactory.decodeByteArray(image.data, 0, image.data.size)
                    ?: throw DeepSeekTimetableClientError.InvalidImage(index)
                try {
                    val task = recognizer.process(InputImage.fromBitmap(bitmap, 0))
                    while (!task.isComplete) {
                        if (cancelled.get()) throw DeepSeekTimetableClientError.Cancelled
                        try {
                            Tasks.await(task, 200, TimeUnit.MILLISECONDS)
                        } catch (_: java.util.concurrent.TimeoutException) {
                            // Poll so cancel can stop the review before a network call.
                        } catch (_: java.util.concurrent.ExecutionException) {
                            throw DeepSeekTimetableClientError.InvalidOCRContext
                        }
                    }
                    if (cancelled.get()) throw DeepSeekTimetableClientError.Cancelled
                    if (!task.isSuccessful) throw DeepSeekTimetableClientError.InvalidOCRContext
                    val vision = task.result ?: throw DeepSeekTimetableClientError.InvalidOCRContext
                    val tokens = mutableListOf<OcrToken>()
                    for (block in vision.textBlocks) {
                        for (line in block.lines) {
                            val elements = line.elements
                            if (elements.isEmpty()) {
                                addToken(tokens, index, line.text, line.boundingBox, line.confidence, bitmap.width, bitmap.height)
                            } else {
                                for (element in elements) {
                                    addToken(
                                        tokens,
                                        index,
                                        element.text,
                                        element.boundingBox,
                                        element.confidence,
                                        bitmap.width,
                                        bitmap.height,
                                    )
                                }
                            }
                        }
                    }
                    OcrPage(index, tokens)
                } finally {
                    bitmap.recycle()
                }
            }
        } finally {
            recognizer.close()
        }
    }

    private fun addToken(
        tokens: MutableList<OcrToken>,
        imageIndex: Int,
        rawText: String?,
        box: android.graphics.Rect?,
        confidence: Float,
        width: Int,
        height: Int,
    ) {
        val text = rawText?.trim().orEmpty()
        if (text.isEmpty() || box == null || width <= 0 || height <= 0) return
        val normalized = OcrGeometry.normalize(
            box.left.toDouble(),
            box.top.toDouble(),
            box.right.toDouble(),
            box.bottom.toDouble(),
            width,
            height,
            OcrGeometry.NORMAL,
        )
        tokens.add(
            OcrToken(
                imageIndex = imageIndex,
                text = text,
                boundingBox = normalized,
                confidence = confidence.takeIf { it >= 0f }?.toDouble(),
            ),
        )
    }
}
