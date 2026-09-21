import Foundation

/// Normalized top-left origin coordinates emitted by Vision.
/// Vision itself uses a bottom-left origin; the recognizer converts it before
/// returning a token so parsers can use the same coordinate system as UIKit.
public struct AIImportBoundingBox: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct VisionTimetableToken: Codable, Equatable {
    public let imageIndex: Int
    public let text: String
    public let boundingBox: AIImportBoundingBox
    public let confidence: Double

    public init(imageIndex: Int, text: String, boundingBox: AIImportBoundingBox, confidence: Double) {
        self.imageIndex = imageIndex
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

public struct VisionTimetablePage: Codable, Equatable {
    public let imageIndex: Int
    public let tokens: [VisionTimetableToken]

    public init(imageIndex: Int, tokens: [VisionTimetableToken]) {
        self.imageIndex = imageIndex
        self.tokens = tokens
    }
}

/// An image as it will be placed in a DeepSeek data URL. Keeping the MIME
/// type beside the bytes avoids guessing a format after the caller selected it.
public struct AIImportImage: Equatable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String = "image/jpeg") {
        self.data = data
        self.mimeType = mimeType
    }
}

public struct DeepSeekTimetableResult: Equatable {
    /// Validated, normalized courses JSON for the shared draft parser.
    /// This layer deliberately does not write the schedule.
    public let jsonText: String
    public let finishReason: String?

    public init(jsonText: String, finishReason: String?) {
        self.jsonText = jsonText
        self.finishReason = finishReason
    }
}

public enum DeepSeekTimetableClientError: Error, Equatable {
    case missingAPIKey
    case invalidEndpoint
    case invalidImage(index: Int)
    case imageTooLarge(index: Int, encodedBytes: Int, limit: Int)
    case requestTooLarge(encodedBytes: Int, limit: Int)
    case cancelled
    case unauthorized
    case paymentRequired
    case rateLimited
    case serverUnavailable(statusCode: Int)
    case transport
    case invalidResponse
    case invalidJSON
    case emptyCourses
    case invalidCourseField(String)
    case invalidTimetableText
    case truncatedResponse
    case apiError(statusCode: Int)
}

extension DeepSeekTimetableClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "未配置 DeepSeek API key"
        case .invalidEndpoint: return "DeepSeek 请求地址无效"
        case .invalidImage(let index): return "第 \(index + 1) 张图片无法读取"
        case .imageTooLarge(let index, _, let limit):
            return "第 \(index + 1) 张图片超过 \(limit / (1024 * 1024)) MiB 限制"
        case .requestTooLarge(_, let limit):
            return "识图请求超过 \(limit / (1024 * 1024)) MiB 限制"
        case .cancelled: return "识图请求已取消"
        case .unauthorized: return "DeepSeek API key 无效"
        case .paymentRequired: return "DeepSeek 账户余额不足或需要付费"
        case .rateLimited: return "DeepSeek 请求过于频繁，请稍后重试"
        case .serverUnavailable: return "DeepSeek 服务暂时不可用"
        case .transport: return "无法连接 DeepSeek 服务"
        case .invalidResponse: return "DeepSeek 返回格式无法解析"
        case .invalidTimetableText: return "请仅提供已提取的课表文字，勿包含登录页、链接或凭据"
        case .invalidJSON: return "AI 返回的内容不是完整的结构化课表，请重试；本次未保存课程"
        case .emptyCourses: return "AI 未识别到课程，请检查图片或网页是否包含完整课表"
        case .invalidCourseField(let path): return "AI 返回的课表字段格式不正确（\(path)），本次未保存课程；请重试"
        case .truncatedResponse: return "AI 结果过长被截断，请减少每批图片数量或分页面识别；本次未保存课程"
        case .apiError: return "DeepSeek 请求失败"
        }
    }
}
