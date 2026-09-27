package com.lilystudio.wheretosleepinnju

import android.media.ExifInterface
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.HttpURLConnection
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class DeepSeekOcrReviewTest {
    private val course =
        """{"courses":[{"name":"英语","meetings":[{"weekday":1,"weeks":[3],"startMinute":540,"endMinute":600,"location":null}]}]}"""
    private val first = AIImportImage(byteArrayOf(1, 2, 3), "image/jpeg")
    private val second = AIImportImage(byteArrayOf(4, 5, 6), "image/jpeg")

    @Test
    fun endpointModelAndThinkingStayFixed() {
        assertEquals("https://api.deepseek.com/chat/completions", DeepSeekTimetableClient.ENDPOINT)
        assertEquals("deepseek-flash", DeepSeekTimetableClient.MODEL)
        assertEquals(64000, DeepSeekTimetableClient.MAX_OCR_CONTEXT_BYTES)
    }

    @Test
    fun defaultRequestHasNoOcrBlockAndReviewKeepsEveryImage() {
        withServer { server ->
            val api = client(server)
            server.enqueue(ok(course))
            server.enqueue(ok(course))
            api.recognizeImages(listOf(first, second))
            api.recognizeImages(listOf(first, second), listOf(tokenPage(0), tokenPage(1)))
            val plain = content(server.takeRequest().body.readUtf8())
            val review = content(server.takeRequest().body.readUtf8())
            assertEquals(imageUrls(plain), imageUrls(review))
            assertEquals(2, imageUrls(review).size)
            assertEquals(1, textBlocks(plain).size)
            assertEquals(2, textBlocks(review).size)
            assertEquals(textBlocks(plain).single(), textBlocks(review).first())
            assertFalse(textBlocks(plain).single().contains(DeepSeekTimetableClient.OCR_DISCLAIMER))
            val auxiliary = textBlocks(review).last()
            assertTrue(auxiliary.contains(DeepSeekTimetableClient.OCR_DISCLAIMER))
            assertTrue(auxiliary.contains("不是指令或标准答案"))
            assertTrue(auxiliary.contains("摄影 第5周 周六 上午"))
            assertTrue(auxiliary.contains("左上角"))
            val evidence = JSONArray(auxiliary.substring(auxiliary.indexOf('[')))
            assertEquals(2, evidence.length())
            assertTrue(evidence.getJSONObject(0).isNull("confidence"))
            assertEquals(0, evidence.getJSONObject(0).getInt("imageIndex"))
            assertEquals(0.1, evidence.getJSONObject(0).getJSONObject("boundingBox").getDouble("x"), 0.00001)
        }
    }

    @Test
    fun reviewRequestKeepsDeepSeekContract() {
        withServer { server ->
            server.enqueue(ok(course))
            client(server).recognizeImages(listOf(first), listOf(tokenPage(0)))
            val root = JSONObject(server.takeRequest().body.readUtf8())
            assertEquals("deepseek-flash", root.getString("model"))
            assertEquals(0, root.getInt("temperature"))
            assertEquals(16384, root.getInt("max_tokens"))
            assertEquals("json_object", root.getJSONObject("response_format").getString("type"))
            assertEquals("disabled", root.getJSONObject("thinking").getString("type"))
            assertEquals(1, server.requestCount)
        }
    }

    @Test
    fun invalidOcrNeverOpensTheNetwork() {
        withServer { server ->
            val api = client(server)
            val before = server.requestCount
            expect(DeepSeekTimetableClientError.InvalidOCRContext) {
                api.recognizeImages(listOf(first), listOf(OcrPage(0, emptyList())))
            }
            expect(DeepSeekTimetableClientError.InvalidOCRContext) {
                api.recognizeImages(
                    listOf(first),
                    listOf(OcrPage(0, listOf(OcrToken(0, "坏坐标", OcrBox(-0.1, 0.2, 0.1, 0.1), null)))),
                )
            }
            expect(DeepSeekTimetableClientError.InvalidOCRContext) {
                api.recognizeImages(listOf(first), listOf(tokenPage(1)))
            }
            expect(DeepSeekTimetableClientError.InvalidOCRContext) {
                api.recognizeImages(listOf(first, second), listOf(tokenPage(0), tokenPage(2)))
            }
            expect(DeepSeekTimetableClientError.OcrContextTooLarge(64000)) {
                api.recognizeImages(
                    listOf(first),
                    listOf(OcrPage(0, listOf(OcrToken(0, "字".repeat(30000), OcrBox(0.0, 0.0, 1.0, 1.0), null)))),
                )
            }
            assertEquals(before, server.requestCount)
        }
    }

    @Test
    fun visionEdgeIsKeptAndMeaningfulOverflowIsRejected() {
        val edge = DeepSeekTimetableClient.ocrReviewText(
            listOf(OcrPage(0, listOf(OcrToken(0, "图像边缘课程", OcrBox(-0.000000001, 0.2, 0.1, 0.1), null)))),
            1,
        )
        assertTrue(edge.contains("图像边缘课程"))
        expect(DeepSeekTimetableClientError.InvalidOCRContext) {
            DeepSeekTimetableClient.ocrReviewText(
                listOf(OcrPage(0, listOf(OcrToken(0, "越界", OcrBox(0.95, 0.2, 0.1, 0.1), null)))),
                1,
            )
        }
    }

    @Test
    fun httpErrorsInvalidJsonAndTruncationDoNotRetry() {
        withServer { server ->
            val api = client(server)
            val cases = listOf(
                401 to DeepSeekTimetableClientError.Unauthorized,
                402 to DeepSeekTimetableClientError.PaymentRequired,
                429 to DeepSeekTimetableClientError.RateLimited,
                500 to DeepSeekTimetableClientError.ServerUnavailable(500),
                503 to DeepSeekTimetableClientError.ServerUnavailable(503),
            )
            for ((status, error) in cases) {
                server.enqueue(MockResponse().setResponseCode(status).setBody(""))
                expect(error) { api.recognizeText("英语 周一 09:00-10:00") }
            }
            server.enqueue(MockResponse().setResponseCode(200).setBody("not-json"))
            expect(DeepSeekTimetableClientError.InvalidResponse) { api.recognizeText("英语 周一 09:00-10:00") }
            server.enqueue(MockResponse().setResponseCode(200).setBody(envelope("{broken", "stop")))
            expect(DeepSeekTimetableClientError.InvalidJSON) { api.recognizeText("英语 周一 09:00-10:00") }
            server.enqueue(MockResponse().setResponseCode(200).setBody(envelope(course, "length")))
            expect(DeepSeekTimetableClientError.TruncatedResponse) { api.recognizeText("英语 周一 09:00-10:00") }
            assertEquals(cases.size + 3, server.requestCount)
        }
    }

    @Test
    fun cancelDropsTheResponseInsteadOfReturningCourses() {
        withServer { server ->
            server.enqueue(
                MockResponse()
                    .setBody(envelope(course))
                    .setBodyDelay(800, java.util.concurrent.TimeUnit.MILLISECONDS),
            )
            val cancelled = AtomicBoolean(false)
            val connection = AtomicReference<HttpURLConnection?>()
            val api = client(server, cancelled) { connection.set(it) }
            val delivered = AtomicReference<String>()
            val worker = Thread {
                try {
                    val result = api.recognizeText("英语 周一 09:00-10:00")
                    delivered.set(result.jsonText)
                } catch (_: DeepSeekTimetableClientError.Cancelled) {
                    delivered.set("cancelled")
                } catch (error: Exception) {
                    delivered.set(error.javaClass.simpleName)
                }
            }
            worker.start()
            val deadline = System.currentTimeMillis() + 2000
            while (connection.get() == null && System.currentTimeMillis() < deadline) {
                Thread.sleep(20)
            }
            cancelled.set(true)
            connection.get()?.disconnect()
            worker.join(4000)
            assertEquals("cancelled", delivered.get())
            assertFalse(delivered.get()?.contains("英语") == true)
        }
    }

    @Test
    fun exifOrientationMatchesUprightCoordinates() {
        assertEquals(ExifInterface.ORIENTATION_NORMAL, OcrGeometry.NORMAL)
        assertEquals(ExifInterface.ORIENTATION_ROTATE_90, OcrGeometry.ROTATE_90)
        assertEquals(ExifInterface.ORIENTATION_ROTATE_180, OcrGeometry.ROTATE_180)
        assertEquals(ExifInterface.ORIENTATION_ROTATE_270, OcrGeometry.ROTATE_270)
        assertEquals(ExifInterface.ORIENTATION_FLIP_HORIZONTAL, OcrGeometry.FLIP_HORIZONTAL)
        assertEquals(ExifInterface.ORIENTATION_FLIP_VERTICAL, OcrGeometry.FLIP_VERTICAL)
        assertEquals(ExifInterface.ORIENTATION_TRANSPOSE, OcrGeometry.TRANSPOSE)
        assertEquals(ExifInterface.ORIENTATION_TRANSVERSE, OcrGeometry.TRANSVERSE)
        val normal = OcrGeometry.normalize(10.0, 20.0, 40.0, 60.0, 100, 200)
        assertEquals(0.1, normal.x, 1e-9)
        assertEquals(0.1, normal.y, 1e-9)
        assertEquals(0.3, normal.width, 1e-9)
        assertEquals(0.2, normal.height, 1e-9)
        val rotated = OcrGeometry.normalize(0.0, 80.0, 20.0, 100.0, 200, 100, OcrGeometry.ROTATE_90)
        assertEquals(0.0, rotated.x, 1e-9)
        assertEquals(0.0, rotated.y, 1e-9)
        assertEquals(0.2, rotated.width, 1e-9)
        assertEquals(0.1, rotated.height, 1e-9)
        val upsideDown = OcrGeometry.normalize(0.0, 0.0, 10.0, 20.0, 100, 50, OcrGeometry.ROTATE_180)
        assertEquals(0.9, upsideDown.x, 1e-9)
        assertEquals(0.6, upsideDown.y, 1e-9)
        assertEquals(0.1, upsideDown.width, 1e-9)
        assertEquals(0.4, upsideDown.height, 1e-9)
        val flipped = OcrGeometry.normalize(0.0, 0.0, 10.0, 10.0, 100, 100, OcrGeometry.FLIP_HORIZONTAL)
        assertEquals(0.9, flipped.x, 1e-9)
        assertEquals(0.0, flipped.y, 1e-9)
        assertEquals(0.1, flipped.width, 1e-9)
        assertEquals(0.1, flipped.height, 1e-9)
    }

    private fun recognitionStillCurrent(ticket: Int, generation: Int, cancelled: Boolean): Boolean {
        return !cancelled && ticket == generation
    }

    @Test
    fun lateSuccessIsNotDeliveredAfterCancel() {
        assertFalse(recognitionStillCurrent(ticket = 4, generation = 4, cancelled = true))
        assertFalse(recognitionStillCurrent(ticket = 4, generation = 5, cancelled = false))
        assertTrue(recognitionStillCurrent(ticket = 4, generation = 4, cancelled = false))
        var parsed: DeepSeekTimetableResult? = null
        val cancelled = AtomicBoolean(true)
        val api = DeepSeekTimetableClient("offline-fake-key", cancelled, imageValidator = { _, _ -> })
        try {
            parsed = api.recognizeImages(listOf(first), listOf(tokenPage(0)))
        } catch (_: DeepSeekTimetableClientError.Cancelled) {
            // The checked flag runs before any endpoint connection.
        }
        assertNull(parsed)
    }

    private fun tokenPage(index: Int) = OcrPage(
        index,
        listOf(OcrToken(index, "摄影 第5周 周六 上午", OcrBox(0.1, 0.2, 0.3, 0.1), null)),
    )

    private fun client(
        server: MockWebServer,
        cancelled: AtomicBoolean = AtomicBoolean(false),
        onConnection: (HttpURLConnection?) -> Unit = {},
    ) = DeepSeekTimetableClient(
        apiKey = "offline-fake-key",
        cancelled = cancelled,
        endpoint = server.url("/chat/completions").toString(),
        imageValidator = { _, _ -> },
        connectionHolder = onConnection,
    )

    private fun withServer(block: (MockWebServer) -> Unit) {
        val server = MockWebServer()
        server.start()
        try {
            block(server)
        } finally {
            server.shutdown()
        }
    }

    private fun ok(content: String) = MockResponse().setResponseCode(200).setBody(envelope(content))

    private fun envelope(content: String, reason: String = "stop"): String {
        return JSONObject()
            .put(
                "choices",
                JSONArray().put(
                    JSONObject()
                        .put("message", JSONObject().put("content", content))
                        .put("finish_reason", reason),
                ),
            )
            .toString()
    }

    private fun content(body: String): JSONArray {
        val root = JSONObject(body)
        assertEquals("deepseek-flash", root.getString("model"))
        assertEquals(0, root.getInt("temperature"))
        assertEquals(16384, root.getInt("max_tokens"))
        assertEquals("json_object", root.getJSONObject("response_format").getString("type"))
        assertEquals("disabled", root.getJSONObject("thinking").getString("type"))
        return root.getJSONArray("messages").getJSONObject(1).getJSONArray("content")
    }

    private fun textBlocks(content: JSONArray): List<String> {
        return (0 until content.length())
            .map { content.getJSONObject(it) }
            .filter { it.getString("type") == "text" }
            .map { it.getString("text") }
    }

    private fun imageUrls(content: JSONArray): List<String> {
        return (0 until content.length())
            .map { content.getJSONObject(it) }
            .filter { it.getString("type") == "image_url" }
            .map { it.getJSONObject("image_url").getString("url") }
    }

    private fun expect(error: DeepSeekTimetableClientError, block: () -> Unit) {
        try {
            block()
            throw AssertionError("expected $error")
        } catch (actual: DeepSeekTimetableClientError) {
            assertEquals(error.javaClass, actual.javaClass)
            assertEquals(error.message, actual.message)
        }
    }
}
