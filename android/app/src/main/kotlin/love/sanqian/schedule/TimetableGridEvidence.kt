package love.sanqian.schedule

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** Local table geometry, not a second course recognizer or a source of guessed schedules. */
object TimetableGridEvidence {
    private const val MAX_IMAGES = 20
    private const val MAX_PIXELS = 16_000_000L
    private const val MAX_DIMENSION = 8192
    private const val MAX_BATCH_PIXELS = 100_000_000L
    private const val MAX_TOKENS = 20_000
    private const val MAX_TOKEN_CHARS = 200_000
    private const val MAX_EDGES = 128
    private const val MAX_CELL_OCR_CROPS = 8
    private const val MAX_CELL_OCR_PIXELS = 4_000_000L
    private val clock = Regex("(?<!\\d)([0-2]?\\d)[:：]([0-5]\\d)\\s*[-–—~～至]+\\s*([0-2]?\\d)[:：]([0-5]\\d)(?!\\d)")
    private val weekday = Regex("(?:周|星期|礼拜)([一二三四五六日天1-7])")
    private val summaryLabel = Regex("上午|下午|晚上|晚间|早上|中午|全天")

    /**
     * Inputs must be the upright JPEGs produced by jpegFromPath, with boxes in that
     * same coordinate space. Crop OCR is local only; the API still receives those
     * original JPEGs, in their original order. Existing text and geometry are kept.
     */
    fun fillMissingText(
        images: List<AIImportImage>,
        cells: List<Map<String, Any?>>,
        cancelled: AtomicBoolean,
        recognize: (List<AIImportImage>) -> List<OcrPage>,
    ): List<Map<String, Any?>> {
        checkCancelled(cancelled)
        if (images.isEmpty() || images.size > MAX_IMAGES || cells.none(::hasMissingText)) return cells
        try {
            val dimensions = mutableMapOf<Int, Pair<Int, Int>>()
            for (index in cells.filter(::hasMissingText).mapNotNull(::imageIndex).distinct()) {
                checkCancelled(cancelled)
                val image = images.getOrNull(index) ?: continue
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(image.data, 0, image.data.size, bounds)
                if (bounds.outWidth !in 3..MAX_DIMENSION || bounds.outHeight !in 3..MAX_DIMENSION ||
                    bounds.outWidth.toLong() * bounds.outHeight > MAX_PIXELS) continue
                dimensions[index] = bounds.outWidth to bounds.outHeight
            }
            val requests = missingTextCrops(cells, dimensions, cancelled)
            val encoded = mutableListOf<AIImportImage>()
            val encodedRequests = mutableListOf<CellCrop>()
            for ((index, pageRequests) in requests.groupBy { it.imageIndex }) {
                checkCancelled(cancelled)
                val image = images[index]
                val bitmap = BitmapFactory.decodeByteArray(image.data, 0, image.data.size) ?: continue
                try {
                    if (dimensions[index] != (bitmap.width to bitmap.height)) continue
                    for (request in pageRequests) {
                        checkCancelled(cancelled)
                        val crop = Bitmap.createBitmap(bitmap, request.left, request.top, request.width, request.height)
                        try {
                            val output = ByteArrayOutputStream()
                            if (!crop.compress(Bitmap.CompressFormat.JPEG, 95, output)) continue
                            encoded.add(AIImportImage(output.toByteArray()))
                            encodedRequests.add(request)
                        } finally {
                            if (crop !== bitmap) crop.recycle()
                        }
                    }
                } finally {
                    bitmap.recycle()
                }
            }
            checkCancelled(cancelled)
            if (encoded.isEmpty()) return cells
            // One bounded local batch: Paddle can load its sessions at most once here.
            val pages = recognize(encoded)
            checkCancelled(cancelled)
            return mergeMissingText(cells, encodedRequests, pages, cancelled)
        } catch (error: DeepSeekTimetableClientError.Cancelled) {
            throw error
        } catch (_: CancellationException) {
            throw DeepSeekTimetableClientError.Cancelled
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            throw DeepSeekTimetableClientError.Cancelled
        } catch (_: Exception) {
            checkCancelled(cancelled)
            return cells
        } catch (_: OutOfMemoryError) {
            checkCancelled(cancelled)
            return cells
        }
    }

    internal data class CellCrop(val cellIndex: Int, val imageIndex: Int, val left: Int, val top: Int,
                                 val width: Int, val height: Int)

    internal fun missingTextCrops(
        cells: List<Map<String, Any?>>,
        dimensions: Map<Int, Pair<Int, Int>>,
        cancelled: AtomicBoolean = AtomicBoolean(false),
    ): List<CellCrop> {
        val requests = mutableListOf<CellCrop>()
        var pixels = 0L
        for ((cellIndex, cell) in cells.withIndex()) {
            checkCancelled(cancelled)
            if (requests.size >= MAX_CELL_OCR_CROPS) break
            if (!hasMissingText(cell)) continue
            val imageIndex = imageIndex(cell) ?: continue
            val (w, h) = dimensions[imageIndex] ?: continue
            if (w !in 3..MAX_DIMENSION || h !in 3..MAX_DIMENSION || w.toLong() * h > MAX_PIXELS) continue
            val rawBox = cell["box"] as? List<*> ?: continue
            if (rawBox.size != 4 || rawBox.any { it !is Number }) continue
            val values = rawBox.map { (it as Number).toDouble() }
            if (values.any { !it.isFinite() }) continue
            val (x, y, width, height) = values
            if (x < 0 || y < 0 || width <= 0 || height <= 0 || x + width > 1.000001 || y + height > 1.000001) continue
            // Round inward so OCR never sees text from a neighbouring cell.
            val left = ceil(x * w).toInt()
            val top = ceil(y * h).toInt()
            val right = floor(min(1.0, x + width) * w).toInt()
            val bottom = floor(min(1.0, y + height) * h).toInt()
            if (right <= left || bottom <= top) continue
            val count = (right - left).toLong() * (bottom - top)
            if (pixels + count > MAX_CELL_OCR_PIXELS) continue
            pixels += count
            requests.add(CellCrop(cellIndex, imageIndex, left, top, right - left, bottom - top))
        }
        return requests
    }

    internal fun mergeMissingText(
        cells: List<Map<String, Any?>>,
        requests: List<CellCrop>,
        pages: List<OcrPage>,
        cancelled: AtomicBoolean = AtomicBoolean(false),
    ): List<Map<String, Any?>> {
        checkCancelled(cancelled)
        if (pages.any { it.imageIndex !in requests.indices } || pages.map { it.imageIndex }.distinct().size != pages.size) return cells
        val updated = cells.toMutableList()
        for (page in pages) {
            checkCancelled(cancelled)
            val request = requests[page.imageIndex]
            val cell = cells.getOrNull(request.cellIndex) ?: continue
            if (!hasMissingText(cell) || imageIndex(cell) != request.imageIndex || !withinTokenBudget(page.tokens)) continue
            val texts = page.tokens.filter { validToken(it, page.imageIndex) }
                .sortedWith(compareBy(::centerY, ::centerX)).map { it.text.trim() }
            if (texts.isNotEmpty()) updated[request.cellIndex] = cell + mapOf("texts" to texts, "textSource" to "cellOCR")
        }
        return updated
    }

    private fun hasMissingText(cell: Map<String, Any?>) = (cell["texts"] as? List<*>)?.isEmpty() == true
    private fun imageIndex(cell: Map<String, Any?>): Int? {
        val value = (cell["imageIndex"] as? Number)?.toDouble() ?: return null
        return value.toInt().takeIf { value.isFinite() && value == it.toDouble() && it in 0 until MAX_IMAGES }
    }

    fun build(
        images: List<AIImportImage>,
        pages: List<OcrPage>,
        cancelled: AtomicBoolean = AtomicBoolean(false),
    ): List<Map<String, Any?>> {
        checkCancelled(cancelled)
        if (images.isEmpty() || images.size > MAX_IMAGES || pages.size > MAX_IMAGES) return emptyList()
        if (pages.map { it.imageIndex }.distinct().size != pages.size) return emptyList()
        val layouts = mutableListOf<Layout>()
        var batchPixels = 0L
        for (page in pages) {
            checkCancelled(cancelled)
            if (page.imageIndex !in images.indices || !withinTokenBudget(page.tokens)) continue
            val image = images[page.imageIndex]
            var bitmap: Bitmap? = null
            try {
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(image.data, 0, image.data.size, options)
                val count = options.outWidth.toLong() * options.outHeight
                if (options.outWidth !in 3..MAX_DIMENSION || options.outHeight !in 3..MAX_DIMENSION || count > MAX_PIXELS || count <= 0) continue
                if (batchPixels + count > MAX_BATCH_PIXELS) break
                batchPixels += count
                bitmap = BitmapFactory.decodeByteArray(image.data, 0, image.data.size) ?: continue
                val width = bitmap.width
                val height = bitmap.height
                if (width != options.outWidth || height != options.outHeight) continue
                val pixels = ByteArray(count.toInt())
                val row = IntArray(width)
                for (y in 0 until height) {
                    if (y % 32 == 0) checkCancelled(cancelled)
                    bitmap.getPixels(row, 0, width, 0, y, width, 1)
                    for (x in 0 until width) {
                        val rgb = row[x]
                        pixels[y * width + x] = (((rgb ushr 16 and 255) * 299 +
                            (rgb ushr 8 and 255) * 587 + (rgb and 255) * 114 + 500) / 1000).toByte()
                    }
                }
                layout(PixelPage(page.imageIndex, width, height, pixels, page.tokens), cancelled)?.let(layouts::add)
            } catch (error: DeepSeekTimetableClientError.Cancelled) {
                throw error
            } catch (_: RuntimeException) {
                // Evidence is optional. Bad/unsupported image decoding must not abort recognition.
            } catch (_: OutOfMemoryError) {
                // The image request can still proceed without this optional pixel pass.
                break
            } finally {
                bitmap?.recycle()
            }
        }
        checkCancelled(cancelled)
        return evidence(layouts)
    }

    /** Same pixel algorithm without Android decoding, for deterministic geometry tests. */
    internal data class PixelPage(
        val imageIndex: Int,
        val width: Int,
        val height: Int,
        val gray: ByteArray,
        val tokens: List<OcrToken>,
    )

    internal fun buildFromPixels(
        pages: List<PixelPage>,
        cancelled: AtomicBoolean = AtomicBoolean(false),
    ): List<Map<String, Any?>> {
        checkCancelled(cancelled)
        if (pages.size > MAX_IMAGES || pages.map { it.imageIndex }.distinct().size != pages.size) return emptyList()
        if (pages.sumOf { it.width.toLong() * it.height } > MAX_BATCH_PIXELS) return emptyList()
        val layouts = pages.mapNotNull { layout(it, cancelled) }
        checkCancelled(cancelled)
        return evidence(layouts)
    }

    private data class Cell(val row: Int, val column: Int, val start: Int, val end: Int,
                            val label: String, val box: List<Double>, val texts: List<String>)
    private data class Layout(val imageIndex: Int, val columns: List<Int>, val boundaries: List<Double>, val headers: Map<Int, Int>,
                              val conflictingHeaders: Boolean, val cells: List<Cell>)

    private fun layout(page: PixelPage, cancelled: AtomicBoolean): Layout? {
        checkCancelled(cancelled)
        val w = page.width
        val h = page.height
        val count = w.toLong() * h
        if (page.imageIndex !in 0 until MAX_IMAGES || w !in 3..MAX_DIMENSION || h !in 3..MAX_DIMENSION || count > MAX_PIXELS ||
            count != page.gray.size.toLong() || !withinTokenBudget(page.tokens)) return null
        val tokens = page.tokens.filter { validToken(it, page.imageIndex) }
        if (tokens.isEmpty()) return null
        val vertical = IntArray(w - 2)
        for (y in 0 until h) {
            if (y % 32 == 0) checkCancelled(cancelled)
            val offset = y * w
            for (x in 1 until w - 1) {
                if (abs(gray(page, offset + x + 1) - gray(page, offset + x - 1)) > 12) vertical[x - 1]++
            }
        }
        val xs = lines(vertical, h).toMutableList()
        if (xs.size < 5 || xs.size > MAX_EDGES) return null
        if (xs.first() > 0) xs.add(0, 0)
        if (xs.last() < w - 1) xs.add(w)
        val clockTokens = tokens.filter { times(it.text).isNotEmpty() }
        val clockColumns = clockTokens.mapNotNull { column(centerX(it) * w, xs) }.groupingBy { it }.eachCount()
        val maxClockCount = clockColumns.values.maxOrNull()?.takeIf { it >= 2 } ?: return null
        val labelColumn = clockColumns.filterValues { it == maxClockCount }.keys.singleOrNull() ?: return null
        val columns = (labelColumn + 1 until xs.lastIndex).filter { xs[it + 1] - xs[it] >= w * .04 }
        if (columns.size !in 2..7) return null
        val widths = columns.map { xs[it + 1] - xs[it] }
        if (widths.max() > widths.min() * 1.5) return null
        val left = xs[labelColumn]
        val right = xs[columns.last() + 1]
        val horizontal = IntArray(h - 2)
        for (y in 1 until h - 1) {
            if (y % 32 == 0) checkCancelled(cancelled)
            var hits = 0
            for (x in left until right) {
                if (abs(gray(page, (y + 1) * w + x) - gray(page, (y - 1) * w + x)) > 12) hits++
            }
            horizontal[y - 1] = hits
        }
        val detectedRows = lines(horizontal, right - left)
        if (detectedRows.size > MAX_EDGES) return null
        val ys = (listOf(0, h) + detectedRows).distinct().sorted()
        val firstClockRow = clockTokens.filter { column(centerX(it) * w, xs) == labelColumn }
            .mapNotNull { column(centerY(it) * h, ys) }.minOrNull() ?: return null
        val headerValues = mutableMapOf<Int, MutableSet<Int>>()
        for (token in tokens) {
            val tokenRow = column(centerY(token) * h, ys) ?: continue
            if (tokenRow >= firstClockRow) continue
            val match = weekday.matchEntire(token.text.filterNot { it.isWhitespace() }) ?: continue
            val col = column(centerX(token) * w, xs) ?: continue
            if (col !in columns) continue
            val symbol = match.groupValues[1]
            val day = symbol.toIntOrNull() ?: min(7, "一二三四五六日天".indexOf(symbol) + 1)
            headerValues.getOrPut(col) { mutableSetOf() }.add(day)
        }
        val headers = headerValues.filterValues { it.size == 1 }.mapValues { it.value.single() }
        val conflicting = headerValues.any { it.value.size != 1 } || headers.values.distinct().size != headers.size
        val rowTokens = tokens.groupBy { column(centerY(it) * h, ys) }
        val cells = mutableListOf<Cell>()
        for (row in 0 until ys.lastIndex) {
            checkCancelled(cancelled)
            val candidates = rowTokens[row].orEmpty()
            val labels = candidates.filter { column(centerX(it) * w, xs) == labelColumn }
                .sortedWith(compareBy(::centerY, ::centerX))
            val rowTimes = labels.flatMap { times(it.text) }.distinct()
            if (rowTimes.size != 1) continue
            val (start, end) = rowTimes.single()
            val label = labels.joinToString(" ") { it.text }
            if (!summaryLabel.containsMatchIn(label) && !("课" in label && "第" !in label && end - start >= 90)) continue
            for (col in columns) {
                val texts = candidates.filter { token ->
                    val b = token.boundingBox
                    val overlap = max(0.0, min((b.x + b.width) * w, xs[col + 1].toDouble()) - max(b.x * w, xs[col].toDouble()))
                    overlap >= .5 * min(b.width * w, (xs[col + 1] - xs[col]).toDouble())
                }.sortedWith(compareBy(::centerY, ::centerX)).map { it.text }
                if (texts.isEmpty() && !hasInk(page, xs[col] + 4, ys[row] + 4,
                        xs[col + 1] - 4, ys[row + 1] - 4, cancelled)) continue
                cells.add(Cell(row, col, start, end, label,
                    listOf(xs[col].toDouble() / w, ys[row].toDouble() / h,
                        (xs[col + 1] - xs[col]).toDouble() / w, (ys[row + 1] - ys[row]).toDouble() / h), texts))
            }
        }
        val dataLeft = xs[columns.first()]
        val dataWidth = xs[columns.last() + 1] - dataLeft
        val boundaries = (columns.map { xs[it] } + xs[columns.last() + 1]).map { (it - dataLeft).toDouble() / dataWidth }
        return Layout(page.imageIndex, columns, boundaries, headers, conflicting, cells)
    }

    private fun evidence(layouts: List<Layout>): List<Map<String, Any?>> {
        fun ordered(layout: Layout) = !layout.conflictingHeaders && layout.headers.all { (col, day) ->
            day == layout.columns.indexOf(col) + 1
        }
        val templates = layouts.filter { it.columns.size == 7 && it.headers.size >= 3 && ordered(it) }
        return layouts.flatMap { layout ->
            if (layout.conflictingHeaders) return@flatMap emptyList()
            val useShared = layout.columns.size == 7 && ordered(layout) && templates.any { template ->
                template.boundaries.zip(layout.boundaries).all { (a, b) -> abs(a - b) <= .03 }
            }
            val headers = if (useShared) layout.columns.withIndex().associate { it.value to it.index + 1 } else layout.headers
            layout.cells.mapNotNull { cell ->
                val day = headers[cell.column] ?: return@mapNotNull null
                linkedMapOf<String, Any?>(
                    "id" to "p${layout.imageIndex}r${cell.row}c${cell.column}",
                    "imageIndex" to layout.imageIndex,
                    "weekday" to day,
                    "startMinute" to cell.start,
                    "endMinute" to cell.end,
                    "headerSource" to if (cell.column in layout.headers) "visibleHeader" else "sharedSevenColumnHeader",
                    "rowLabel" to cell.label,
                    "box" to cell.box,
                    "texts" to cell.texts,
                )
            }
        }
    }

    private fun times(text: String): List<Pair<Int, Int>> = clock.findAll(text).mapNotNull { match ->
        val (h1, m1, h2, m2) = match.groupValues.drop(1).map(String::toInt)
        val start = h1 * 60 + m1
        val end = h2 * 60 + m2
        if (h1 < 24 && h2 < 24 && start < end) start to end else null
    }.toList()

    private fun lines(hits: IntArray, span: Int): List<Int> {
        val result = mutableListOf<Int>()
        var sum = 0L
        var count = 0
        var previous = -4
        for (i in hits.indices) {
            if (hits[i] <= span * .6) continue
            val value = i + 1
            if (count > 0 && value - previous > 3) {
                result.add((sum.toDouble() / count + .5).toInt())
                sum = 0
                count = 0
            }
            sum += value
            count++
            previous = value
        }
        if (count > 0) result.add((sum.toDouble() / count + .5).toInt())
        return result
    }

    private fun hasInk(page: PixelPage, left: Int, top: Int, right: Int, bottom: Int, cancelled: AtomicBoolean): Boolean {
        if (left >= right || top >= bottom) return false
        val histogram = IntArray(256)
        val size = (right - left) * (bottom - top)
        for (y in top until bottom) {
            if (y % 32 == 0) checkCancelled(cancelled)
            for (x in left until right) histogram[gray(page, y * page.width + x)]++
        }
        var cumulative = 0
        var median = 0
        for (i in histogram.indices) {
            cumulative += histogram[i]
            if (cumulative > size / 2) { median = i; break }
        }
        val contrasting = histogram.indices.filter { abs(it - median) > 40 }.sumOf { histogram[it] }
        return contrasting.toDouble() / size >= .003
    }

    private fun column(position: Double, edges: List<Int>): Int? =
        (0 until edges.lastIndex).firstOrNull { edges[it] <= position && position < edges[it + 1] }

    private fun centerX(token: OcrToken) = token.boundingBox.x + token.boundingBox.width / 2
    private fun centerY(token: OcrToken) = token.boundingBox.y + token.boundingBox.height / 2
    private fun gray(page: PixelPage, offset: Int) = page.gray[offset].toInt() and 255
    private fun withinTokenBudget(tokens: List<OcrToken>) = tokens.size <= MAX_TOKENS &&
        tokens.sumOf { it.text.length.toLong() } <= MAX_TOKEN_CHARS

    private fun validToken(token: OcrToken, imageIndex: Int): Boolean {
        val b = token.boundingBox
        return token.imageIndex == imageIndex && token.text.isNotBlank() &&
            listOf(b.x, b.y, b.width, b.height).all { it.isFinite() } &&
            b.width > 0 && b.height > 0 && b.x >= 0 && b.y >= 0 &&
            b.x + b.width <= 1.000001 && b.y + b.height <= 1.000001
    }

    private fun checkCancelled(cancelled: AtomicBoolean) {
        if (cancelled.get() || Thread.currentThread().isInterrupted) throw DeepSeekTimetableClientError.Cancelled
    }
}
