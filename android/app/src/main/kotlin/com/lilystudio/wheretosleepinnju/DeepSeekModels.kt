package com.lilystudio.wheretosleepinnju

data class AIImportImage(val data: ByteArray, val mimeType: String = "image/jpeg") {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AIImportImage) return false
        return mimeType == other.mimeType && data.contentEquals(other.data)
    }
    override fun hashCode(): Int = 31 * mimeType.hashCode() + data.contentHashCode()
}

data class DeepSeekTimetableResult(val jsonText: String, val finishReason: String?)

sealed class DeepSeekTimetableClientError(message: String) : Exception(message) {
    object MissingAPIKey : DeepSeekTimetableClientError("未配置 DeepSeek API key")
    object InvalidEndpoint : DeepSeekTimetableClientError("DeepSeek 请求地址无效")
    class InvalidImage(val index: Int) : DeepSeekTimetableClientError("第 ${index + 1} 张图片无法读取")
    class ImageTooLarge(val index: Int, encodedBytes: Int, limit: Int) :
        DeepSeekTimetableClientError("第 ${index + 1} 张图片超过 ${limit / (1024 * 1024)} MiB 限制")
    class RequestTooLarge(encodedBytes: Int, limit: Int) :
        DeepSeekTimetableClientError("识图请求超过 ${limit / (1024 * 1024)} MiB 限制")
    object Cancelled : DeepSeekTimetableClientError("识图请求已取消")
    object Unauthorized : DeepSeekTimetableClientError("DeepSeek API key 无效")
    object PaymentRequired : DeepSeekTimetableClientError("DeepSeek 账户余额不足或需要付费")
    object RateLimited : DeepSeekTimetableClientError("DeepSeek 请求过于频繁，请稍后重试")
    class ServerUnavailable(statusCode: Int) : DeepSeekTimetableClientError("DeepSeek 服务暂时不可用")
    object Transport : DeepSeekTimetableClientError("无法连接 DeepSeek 服务")
    object InvalidResponse : DeepSeekTimetableClientError("DeepSeek 返回格式无法解析")
    object InvalidJSON : DeepSeekTimetableClientError("AI 返回的内容不是完整的结构化课表，请重试；本次未保存课程")
    object EmptyCourses : DeepSeekTimetableClientError("AI 未识别到课程，请检查图片或网页是否包含完整课表")
    class InvalidCourseField(path: String) :
        DeepSeekTimetableClientError("AI 返回的课表字段格式不正确（$path），本次未保存课程；请重试")
    object InvalidTimetableText : DeepSeekTimetableClientError("请仅提供已提取的课表文字，勿包含登录页、链接或凭据")
    object TruncatedResponse : DeepSeekTimetableClientError("AI 结果过长被截断，请减少每批图片数量或分页面识别；本次未保存课程")
    class ApiError(statusCode: Int) : DeepSeekTimetableClientError("DeepSeek 请求失败")
}

class ImportBridgeError(message: String) : Exception(message) {
    companion object {
        val unavailable = ImportBridgeError("当前无法打开学校门户")
        val busy = ImportBridgeError("正在识别，请先取消或等待完成")
        val images = ImportBridgeError("请选择 1–20 张可读取的课表图片")
    }
}
