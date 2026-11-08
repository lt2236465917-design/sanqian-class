package love.sanqian.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicBoolean

class TimetableGridEvidenceTest {
    @Test
    fun completeSummaryClockAndColumnAreKeptInsteadOfIndividualPeriods() {
        val cells = TimetableGridEvidence.buildFromPixels(listOf(grid(0)))
        assertEquals(2, cells.size)
        assertEquals(4, cells[0]["weekday"])
        assertEquals(540, cells[0]["startMinute"])
        assertEquals(720, cells[0]["endMinute"])
        assertEquals(listOf("课程甲 第3-5周"), cells[0]["texts"])
        assertEquals(7, cells[1]["weekday"])
        assertEquals(1140, cells[1]["startMinute"])
        assertEquals(1290, cells[1]["endMinute"])
        assertEquals("visibleHeader", cells[1]["headerSource"])
        assertFalse(cells.any { it["startMinute"] == 675 })
    }

    @Test
    fun incompleteHeaderUsesAnExplicitMatchingSevenColumnTemplate() {
        val template = grid(0, headerDays = listOf(1, 2, 3))
        val cropped = grid(1, headerDays = emptyList())
        val cells = TimetableGridEvidence.buildFromPixels(listOf(template, cropped))
        assertEquals(4, cells.size)
        val second = cells.filter { it["imageIndex"] == 1 }
        assertEquals(listOf(4, 7), second.map { it["weekday"] })
        assertTrue(second.all { it["headerSource"] == "sharedSevenColumnHeader" })
        assertTrue(TimetableGridEvidence.buildFromPixels(listOf(cropped)).isEmpty())
    }

    @Test
    fun conflictingHeadersAreNotSilentlyOverwrittenOrShared() {
        val valid = grid(0)
        val repeatedColumn = grid(1).let { it.copy(tokens = it.tokens + token(1, "周三", 420.0, 18.0, 50.0, 10.0)) }
        val repeatedDay = grid(2, headerDays = listOf(1, 2, 3, 3, 5, 6, 7))
        val cells = TimetableGridEvidence.buildFromPixels(listOf(valid, repeatedColumn, repeatedDay))
        assertEquals(2, cells.size)
        assertTrue(cells.all { it["imageIndex"] == 0 })
    }

    @Test
    fun visibleHeaderIsNotReplacedByTheSharedOrder() {
        val otherOrder = grid(1, headerDays = listOf(7, 6, 5, 4, 3, 2, 1))
        val cells = TimetableGridEvidence.buildFromPixels(listOf(grid(0), otherOrder)).filter { it["imageIndex"] == 1 }
        assertEquals(listOf(4, 1), cells.map { it["weekday"] })
        assertTrue(cells.all { it["headerSource"] == "visibleHeader" })
    }

    @Test
    fun differentColumnGeometryCannotBorrowAnotherPagesHeader() {
        val different = grid(1, emptyList(), listOf(130, 130, 88, 88, 88, 88, 88))
        val cells = TimetableGridEvidence.buildFromPixels(listOf(grid(0), different))
        assertTrue(cells.none { it["imageIndex"] == 1 })
    }

    @Test
    fun inkWithoutOcrStillProducesABoundedCellWithNoInventedText() {
        val page = grid(0)
        for (y in 70 until 78) for (x in 220 until 250) page.gray[y * WIDTH + x] = 0
        val cells = TimetableGridEvidence.buildFromPixels(listOf(page))
        val missed = cells.single { it["weekday"] == 2 }
        assertEquals(emptyList<String>(), missed["texts"])
        assertEquals(540, missed["startMinute"])
        @Suppress("UNCHECKED_CAST")
        val box = missed["box"] as List<Double>
        assertEquals(.25, box[0], .003)
        assertEquals(.1, box[1], .003)
    }

    @Test
    fun bodyWeekdayTextCannotEstablishATableHeader() {
        val page = grid(0, emptyList()).let { it.copy(tokens = it.tokens + token(0, "周四", 420.0, 80.0, 50.0, 10.0)) }
        assertTrue(TimetableGridEvidence.buildFromPixels(listOf(page)).isEmpty())
    }

    @Test
    fun ambiguousClockRangesAreNotConvertedIntoAWholePeriod() {
        val page = grid(0).let { it.copy(tokens = it.tokens + token(0, "10:00-11:00", 8.0, 110.0, 82.0, 10.0)) }
        val cells = TimetableGridEvidence.buildFromPixels(listOf(page))
        assertEquals(1, cells.size)
        assertEquals(1140, cells.single()["startMinute"])
    }

    @Test
    fun nonTablesBadCoordinatesAndOversizedInputsAreIgnored() {
        val page = grid(0)
        assertTrue(TimetableGridEvidence.buildFromPixels(listOf(page.copy(gray = ByteArray(WIDTH * HEIGHT) { -1 }))).isEmpty())
        assertTrue(TimetableGridEvidence.buildFromPixels(listOf(page.copy(width = 20_000_000))).isEmpty())
        val badCoordinates = page.copy(tokens = page.tokens.map { it.copy(boundingBox = OcrBox(Double.NaN, .2, .1, .1)) })
        assertTrue(TimetableGridEvidence.buildFromPixels(listOf(badCoordinates)).isEmpty())
        val oversizedText = page.copy(tokens = page.tokens + token(0, "字".repeat(200_001), 100.0, 100.0, 50.0, 10.0))
        assertTrue(TimetableGridEvidence.buildFromPixels(listOf(oversizedText)).isEmpty())
    }

    @Test(expected = DeepSeekTimetableClientError.Cancelled::class)
    fun cancellationIsNotTreatedAsMissingEvidence() {
        TimetableGridEvidence.buildFromPixels(listOf(grid(0)), AtomicBoolean(true))
    }

    @Test
    fun cellCropRoundsInwardAndIgnoresAlreadyReadOrInvalidCells() {
        val empty = emptyCell(0) + mapOf("box" to listOf(.101, .202, .302, .404))
        val cells = listOf(empty,
            emptyCell(0) + mapOf("texts" to listOf("已有课程")),
            emptyCell(0) + mapOf("box" to listOf(-.1, .2, .3, .4)),
            emptyCell(0) + mapOf("box" to listOf(0.0, 0.0, Double.NaN, .4)),
            emptyCell(0) + mapOf("box" to listOf(0.0, 0.0, .3, .4, null)),
            emptyCell(1))
        val requests = TimetableGridEvidence.missingTextCrops(cells, mapOf(0 to (100 to 100)))
        assertEquals(listOf(TimetableGridEvidence.CellCrop(0, 0, 11, 21, 29, 39)), requests)
    }

    @Test
    fun cellCropBatchCapsEightCropsAndFourMillionPixels() {
        val small = List(12) { emptyCell(0) + mapOf("box" to listOf(.1, .1, .1, .1)) }
        val bounded = TimetableGridEvidence.missingTextCrops(small, mapOf(0 to (100 to 100)))
        assertEquals(8, bounded.size)
        assertEquals((0..7).toList(), bounded.map { it.cellIndex })
        val full = TimetableGridEvidence.missingTextCrops(List(3) { emptyCell(0) }, mapOf(0 to (2000 to 2000)))
        assertEquals(1, full.size)
        assertEquals(4_000_000L, full.sumOf { it.width.toLong() * it.height })
        assertTrue(TimetableGridEvidence.missingTextCrops(listOf(emptyCell(0)), mapOf(0 to (4000 to 4000))).isEmpty())
    }

    @Test
    fun cropOcrMapsBatchIndicesBackWithoutChangingCellIdentityOrSlots() {
        val cells = listOf(emptyCell(5), emptyCell(2), emptyCell(3) + mapOf("texts" to listOf("保留原文")))
        val requests = listOf(TimetableGridEvidence.CellCrop(1, 2, 0, 0, 10, 10),
            TimetableGridEvidence.CellCrop(0, 5, 0, 0, 10, 10))
        fun word(index: Int, text: String, x: Double, y: Double) = OcrToken(index, text, OcrBox(x, y, .1, .05), .9)
        val pages = listOf(
            OcrPage(1, listOf(word(1, "原图五", .1, .1))),
            OcrPage(0, listOf(word(0, "第二行", .1, .3), word(0, "右词", .5, .1), word(0, "左词", .1, .1))))
        val result = TimetableGridEvidence.mergeMissingText(cells, requests, pages)
        assertEquals(listOf("原图五"), result[0]["texts"])
        assertEquals(listOf("左词", "右词", "第二行"), result[1]["texts"])
        assertEquals("cellOCR", result[0]["textSource"])
        for (i in 0..1) assertEquals(cells[i].filterKeys { it != "texts" }, result[i].filterKeys { it !in listOf("texts", "textSource") })
        assertEquals(cells[2], result[2])
        assertEquals(cells, TimetableGridEvidence.mergeMissingText(cells, requests, listOf(pages[0], pages[0])))
        assertEquals(cells, TimetableGridEvidence.mergeMissingText(cells, requests, listOf(OcrPage(8, emptyList()))))
        assertEquals(cells, TimetableGridEvidence.mergeMissingText(cells, requests, listOf(OcrPage(0, emptyList()))))
    }

    @Test
    fun noEmptyCellsNeverDecodeOrInvokeAnotherOcrPass() {
        val cells = listOf(emptyCell(0) + mapOf("texts" to listOf("已识别")))
        var calls = 0
        val result = TimetableGridEvidence.fillMissingText(listOf(AIImportImage(byteArrayOf(1))), cells, AtomicBoolean(false)) {
            calls++
            emptyList()
        }
        assertEquals(cells, result)
        assertEquals(0, calls)
    }

    @Test(expected = DeepSeekTimetableClientError.Cancelled::class)
    fun cancelledCropPassDoesNotDecodeOrInvokeOcr() {
        TimetableGridEvidence.fillMissingText(listOf(AIImportImage(byteArrayOf(1))), listOf(emptyCell(0)), AtomicBoolean(true)) {
            throw AssertionError("cancelled request reached OCR")
        }
    }

    private fun emptyCell(imageIndex: Int): Map<String, Any?> = mapOf(
        "id" to "p${imageIndex}r1c3", "imageIndex" to imageIndex, "weekday" to 3,
        "startMinute" to 1140, "endMinute" to 1290, "headerSource" to "visibleHeader",
        "rowLabel" to "晚上课", "box" to listOf(0.0, 0.0, 1.0, 1.0), "texts" to emptyList<String>(),
    )

    private fun grid(
        imageIndex: Int,
        headerDays: List<Int> = (1..7).toList(),
        widths: List<Int> = List(7) { 100 },
    ): TimetableGridEvidence.PixelPage {
        val gray = ByteArray(WIDTH * HEIGHT) { -1 }
        val xs = listOf(0, 100) + widths.runningFold(100) { total, value -> total + value }.drop(1)
        for (rawX in xs) {
            val x = rawX.coerceAtMost(WIDTH - 1)
            for (y in 0 until HEIGHT) gray[y * WIDTH + x] = 0
        }
        for (y in listOf(0, 40, 140, 240, 340, HEIGHT - 1)) {
            for (x in 0 until WIDTH) gray[y * WIDTH + x] = 0
        }
        val tokens = headerDays.mapIndexed { index, day ->
            token(imageIndex, "周${"一二三四五六日"[day - 1]}", xs[index + 1] + 20.0, 15.0, 50.0, 10.0)
        } + listOf(
            token(imageIndex, "上午课", 12.0, 65.0, 75.0, 10.0),
            token(imageIndex, "09:00--12:00", 8.0, 90.0, 82.0, 10.0),
            token(imageIndex, "第4节", 12.0, 165.0, 75.0, 10.0),
            token(imageIndex, "11:15-12:00", 8.0, 190.0, 82.0, 10.0),
            token(imageIndex, "晚上课", 12.0, 265.0, 75.0, 10.0),
            token(imageIndex, "19:00--21:30", 8.0, 290.0, 82.0, 10.0),
            token(imageIndex, "课程甲 第3-5周", xs[4] + 10.0, 80.0, 70.0, 10.0),
            token(imageIndex, "重复的小节行", xs[4] + 10.0, 180.0, 70.0, 10.0),
            token(imageIndex, "课程乙", xs[7] + 10.0, 280.0, 70.0, 10.0),
        )
        return TimetableGridEvidence.PixelPage(imageIndex, WIDTH, HEIGHT, gray, tokens)
    }

    private fun token(imageIndex: Int, text: String, x: Double, y: Double, width: Double, height: Double) =
        OcrToken(imageIndex, text, OcrBox(x / WIDTH, y / HEIGHT, width / WIDTH, height / HEIGHT), .99)

    companion object {
        private const val WIDTH = 800
        private const val HEIGHT = 400
    }
}
