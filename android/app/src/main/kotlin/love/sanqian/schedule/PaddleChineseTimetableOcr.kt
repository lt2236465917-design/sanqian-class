package love.sanqian.schedule

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import java.nio.FloatBuffer
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.*

/** Bundled PP-OCRv4 mobile models (RapidOCR ONNX conversion), CPU only.
 * Input is the same upright JPEG used by the image import. No model download or network I/O.
 * Sessions belong to this review and are always closed, including cancellation/failure.
 */
class PaddleChineseTimetableOcr(private val context: Context) : TimetableOcr {
    private class Scratch {
        val pixels = IntArray(2048)
        val visited = BooleanArray(960 * 960)
        val queue = IntArray(960 * 960)
        val floats: FloatBuffer = ByteBuffer.allocateDirect(960 * 960 * 3 * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
    }
    private val scratch get() = sharedScratch

    private fun modelPath(name: String, check: () -> Unit): String {
        val expected = when(name) {
            "ch_PP-OCRv4_det_mobile.onnx" -> "d2a7720d45a54257208b1e13e36a8479894cb74155a5efe29462512d42f49da9"
            else -> "48fc40f24f6d2a207a2b1091d3437eb3cc3eb6b676dc3ef9c37384005483683b"
        }
        val directory = File(context.noBackupFilesDir, "ocr-v4").apply { mkdirs() }
        val file = File(directory, name)
        fun digest(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val bytes = ByteArray(65536)
                while (true) { check(); val size=input.read(bytes); if(size<0) break; digest.update(bytes,0,size) }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
        synchronized(MODEL_LOCK) {
            if (!file.exists() || digest(file) != expected) {
                val temporary = File(directory, "$name.tmp")
                try {
                    context.assets.open("ocr/$name").use { input -> temporary.outputStream().use { output ->
                        val bytes = ByteArray(65536)
                        while(true) { check(); val size=input.read(bytes); if(size<0) break; output.write(bytes,0,size) }
                    } }
                    if(digest(temporary)!=expected || !temporary.renameTo(file)) {
                        throw DeepSeekTimetableClientError.InvalidOCRContext
                    }
                } finally { temporary.delete() }
            }
        }
        return file.absolutePath
    }
    companion object {
        private val MODEL_LOCK = Any()
        private val recognitionLock = java.util.concurrent.locks.ReentrantLock()
        private val sharedScratch by lazy { Scratch() }
    }

    override fun recognize(images: List<AIImportImage>, cancelled: AtomicBoolean): List<OcrPage> {
        fun checkCancelled() {
            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                throw DeepSeekTimetableClientError.Cancelled
            }
        }
        checkCancelled()
        try {
            while (!recognitionLock.tryLock(50, TimeUnit.MILLISECONDS)) checkCancelled()
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            throw DeepSeekTimetableClientError.Cancelled
        }
        try {
            checkCancelled()
            val env = OrtEnvironment.getEnvironment()
            val keys = listOf("") + context.assets.open("ocr/ppocr_keys_v1.txt")
                .bufferedReader(Charsets.UTF_8).use { it.readLines() } + listOf(" ")
            OrtSession.SessionOptions().use { options ->
                options.setIntraOpNumThreads(1)
                options.setInterOpNumThreads(1)
                // Bound peak memory when many differently sized timetable cells are read.
                options.setMemoryPatternOptimization(false)
                options.setCPUArenaAllocator(false)
                fun session(name: String): OrtSession = env.createSession(modelPath(name, ::checkCancelled), options)
                session("ch_PP-OCRv4_det_mobile.onnx").use { detector ->
                    checkCancelled()
                    session("ch_PP-OCRv4_rec_mobile.onnx").use { recognizer ->
                        checkCancelled()
                        OrtSession.RunOptions().use { runOptions ->
                            val worker = Thread.currentThread()
                            val watchdog = Executors.newSingleThreadScheduledExecutor()
                            // ORT supports termination during a native run. Join the poller before
                            // closing its RunOptions, so cancellation cannot access a freed handle.
                            val poll = watchdog.scheduleAtFixedRate({
                                if (cancelled.get() || worker.isInterrupted) {
                                    runOptions.setTerminate(true)
                                }
                            }, 0, 30, TimeUnit.MILLISECONDS)
                            try {
                                return images.mapIndexed { index, image ->
                                    checkCancelled()
                                    val bitmap = BitmapFactory.decodeByteArray(image.data, 0, image.data.size)
                                        ?: throw DeepSeekTimetableClientError.InvalidImage(index)
                                    try {
                                        val regions = detect(bitmap, env, detector, runOptions, ::checkCancelled)
                                        val tokens = regions.mapNotNull { region ->
                                            checkCancelled()
                                            val crop = crop(bitmap, region)
                                            try {
                                                val (text, confidence) = read(crop, env, recognizer, runOptions, keys)
                                                checkCancelled()
                                                if (text.isBlank() || confidence < 0.5) null else {
                                                    val box = OcrGeometry.clipToUnit(OcrGeometry.normalize(
                                                        region.minOf { it.first }.toDouble(), region.minOf { it.second }.toDouble(),
                                                        region.maxOf { it.first }.toDouble(), region.maxOf { it.second }.toDouble(),
                                                        bitmap.width, bitmap.height,
                                                    ))
                                                    box?.let { OcrToken(index, text.trim(), it, confidence) }
                                                }
                                            } finally { crop.recycle() }
                                        }
                                        OcrPage(index, tokens)
                                    } finally { bitmap.recycle() }
                                }
                            } finally {
                                poll.cancel(false)
                                watchdog.shutdown()
                                var interrupted = Thread.interrupted()
                                while (!watchdog.isTerminated) {
                                    try { watchdog.awaitTermination(100, TimeUnit.MILLISECONDS) }
                                    catch (_: InterruptedException) { interrupted = true }
                                }
                                if (interrupted) Thread.currentThread().interrupt()
                            }
                        }
                    }
                }
            }
        } catch (error: DeepSeekTimetableClientError) {
            throw error
        } catch (_: Exception) {
            checkCancelled()
            throw DeepSeekTimetableClientError.InvalidOCRContext
        } finally { recognitionLock.unlock() }
    }

    private fun tensor(bitmap: Bitmap, width: Int, height: Int, detection: Boolean, env: OrtEnvironment): OnnxTensor {
        val resized = Bitmap.createScaledBitmap(bitmap, width, height, true)
        try {
            val pixels = scratch.pixels
            val size = width * height
            val data = scratch.floats
            data.clear()
            data.limit(size * 3)
            val mean = floatArrayOf(0.485f, 0.456f, 0.406f)
            val std = floatArrayOf(0.229f, 0.224f, 0.225f)
            for (row in 0 until height) {
              resized.getPixels(pixels, 0, width, 0, row, width, 1)
              for (column in 0 until width) {
                val i = row * width + column
                // Paddle/OpenCV models consume BGR, including the detector normalization.
                for (c in 0..2) {
                    val channel = when(c) { 0 -> Color.blue(pixels[column]); 1 -> Color.green(pixels[column]); else -> Color.red(pixels[column]) }
                    val v = channel / 255f
                    data.put(c * size + i, if (detection) (v - mean[c]) / std[c] else (v - 0.5f) / 0.5f)
                }
            }
            }
            return OnnxTensor.createTensor(env, data, longArrayOf(1, 3, height.toLong(), width.toLong()))
        } finally { if (resized !== bitmap) resized.recycle() }
    }

    private fun detect(bitmap: Bitmap, env: OrtEnvironment, session: OrtSession, options: OrtSession.RunOptions,
                       check: () -> Unit): List<List<Pair<Float, Float>>> {
        val scale = min(1.0, 960.0 / max(bitmap.width, bitmap.height))
        val width = max(32, (bitmap.width * scale / 32).roundToInt() * 32)
        val height = max(32, (bitmap.height * scale / 32).roundToInt() * 32)
        tensor(bitmap, width, height, true, env).use { input ->
            session.run(mapOf(session.inputNames.first() to input), options).use { result ->
                val output = result[0] as OnnxTensor
                val shape = output.info.shape
                val h = shape[2].toInt(); val w = shape[3].toInt()
                val map = output.floatBuffer
                val visited = scratch.visited
                java.util.Arrays.fill(visited, 0, h * w, false)
                val queue = scratch.queue
                val regions = mutableListOf<List<Pair<Float, Float>>>()
                for (start in 0 until h * w) {
                    if (start % w == 0) check()
                    if (visited[start] || map[start] < 0.3f) continue
                    var head = 0; var tail = 1; queue[0] = start; visited[start] = true
                    var sum = 0.0; var sx = 0.0; var sy = 0.0
                    while (head < tail) {
                        val pos = queue[head++]; val x = pos % w; val y = pos / w
                        sum += map[pos]; sx += x; sy += y
                        for (dy in -1..1) for (dx in -1..1) {
                            val nx = x + dx; val ny = y + dy
                            if (nx !in 0 until w || ny !in 0 until h) continue
                            val n = ny * w + nx
                            if (!visited[n] && map[n] >= 0.3f) { visited[n] = true; queue[tail++] = n }
                        }
                    }
                    if (tail < 6 || sum / tail < 0.6) continue
                    // Oriented rectangle from the probability component; perspective-crop it
                    // before CTC recognition. No external image-processing native library.
                    val cx = sx / tail; val cy = sy / tail
                    var xx = 0.0; var yy = 0.0; var xy = 0.0
                    for (i in 0 until tail) {
                        val x = queue[i] % w - cx; val y = queue[i] / w - cy
                        xx += x*x; yy += y*y; xy += x*y
                    }
                    val angle = 0.5 * atan2(2*xy, xx-yy)
                    val ux = cos(angle); val uy = sin(angle)
                    var l = Double.POSITIVE_INFINITY; var r = Double.NEGATIVE_INFINITY
                    var t = Double.POSITIVE_INFINITY; var b = Double.NEGATIVE_INFINITY
                    for (i in 0 until tail) {
                        val x = queue[i] % w - cx; val y = queue[i] / w - cy
                        val u = x*ux+y*uy; val v = -x*uy+y*ux
                        l=min(l,u); r=max(r,u); t=min(t,v); b=max(b,v)
                    }
                    if (min(r-l,b-t) < 2) continue
                    // DB unclip distance = area * ratio / perimeter; expanded rectangle.
                    val margin = (r-l)*(b-t)*1.5/(2*(r-l+b-t))
                    l-=margin; r+=margin; t-=margin; b+=margin
                    val region = listOf(l to t, r to t, r to b, l to b).map { (u,v) ->
                        ((cx+u*ux-v*uy)*bitmap.width/w).toFloat().coerceIn(0f,bitmap.width.toFloat()) to
                            ((cy+u*uy+v*ux)*bitmap.height/h).toFloat().coerceIn(0f,bitmap.height.toFloat())
                    }
                    regions.add(region)
                    if (regions.size > 2000) throw DeepSeekTimetableClientError.InvalidOCRContext
                }
                return regions.sortedWith(compareBy({ it.minOf { p -> p.second } }, { it.minOf { p -> p.first } }))
            }
        }
    }

    private fun crop(bitmap: Bitmap, p: List<Pair<Float,Float>>): Bitmap {
        fun distance(a: Pair<Float,Float>, b: Pair<Float,Float>) = hypot(a.first-b.first, a.second-b.second)
        val width = max(1, max(distance(p[0],p[1]),distance(p[2],p[3])).roundToInt())
        val height = max(1,max(distance(p[0],p[3]),distance(p[1],p[2])).roundToInt())
        val out = Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888)
        val matrix=Matrix()
        matrix.setPolyToPoly(p.flatMap { listOf(it.first,it.second) }.toFloatArray(),0,
            floatArrayOf(0f,0f,width.toFloat(),0f,width.toFloat(),height.toFloat(),0f,height.toFloat()),0,4)
        Canvas(out).apply { drawColor(Color.WHITE); drawBitmap(bitmap,matrix,Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)) }
        if (height > width*1.5) {
            val rotated=Bitmap.createBitmap(out,0,0,width,height,Matrix().apply { postRotate(90f) },true)
            out.recycle(); return rotated
        }
        return out
    }

    private fun read(bitmap: Bitmap, env: OrtEnvironment, session: OrtSession, options: OrtSession.RunOptions,
                     keys: List<String>): Pair<String,Double> {
        val width = max(8, ceil(48.0*bitmap.width/bitmap.height).toInt()).coerceAtMost(2048)
        tensor(bitmap,width,48,false,env).use { input ->
            session.run(mapOf(session.inputNames.first() to input),options).use { result ->
                val output=result[0] as OnnxTensor
                val shape=output.info.shape; val steps=shape[1].toInt(); val classes=shape[2].toInt()
                if (classes != keys.size) throw DeepSeekTimetableClientError.InvalidOCRContext
                val values=output.floatBuffer; val text=StringBuilder(); var last=0; var confidence=0.0; var count=0
                for (step in 0 until steps) {
                    var best=0; var score=Float.NEGATIVE_INFINITY
                    for (c in 0 until classes) { val v=values.get(); if(v>score) {score=v;best=c} }
                    if(best!=0 && best!=last) {text.append(keys[best]);confidence+=score;count++}
                    last=best
                }
                return text.toString() to if(count==0) 0.0 else (confidence/count).coerceIn(0.0,1.0)
            }
        }
    }
}
