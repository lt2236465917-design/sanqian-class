import Foundation
import UIKit
import Vision
import ImageIO

/// On-device OCR; coordinates are normalized against the oriented image.
public final class VisionTimetableRecognizer {
    public var recognitionLanguages: [String]
    public var recognitionLevel: VNRequestTextRecognitionLevel
    public init(recognitionLanguages: [String] = ["zh-Hans", "zh-Hant", "en-US"], recognitionLevel: VNRequestTextRecognitionLevel = .accurate) {
        self.recognitionLanguages = recognitionLanguages
        self.recognitionLevel = recognitionLevel
    }

    public func recognize(images: [UIImage]) async throws -> [VisionTimetablePage] {
        var pages: [VisionTimetablePage] = []
        for (index, image) in images.enumerated() {
            let tokens = try await recognize(image: image, imageIndex: index)
            pages.append(VisionTimetablePage(imageIndex: index, tokens: tokens))
        }
        if Task.isCancelled { throw VisionTimetableRecognizerError.cancelled }
        return pages
    }

    public func recognize(image: UIImage, imageIndex: Int = 0) async throws -> [VisionTimetableToken] {
        let box = VisionImportCancellationBox()
        let languages = recognitionLanguages
        let level = recognitionLevel
        do {
            try Task.checkCancellation()
            let result: [VisionTimetableToken] = try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    // UIImage orientation must be preserved; Vision's synchronous
                    // perform never runs on the caller's UI executor.
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            guard !box.isCancelled else { throw CancellationError() }
                            guard let cgImage = image.cgImage else { throw VisionTimetableRecognizerError.invalidImage }
                            let request = VNRecognizeTextRequest()
                            request.recognitionLevel = level
                            request.usesLanguageCorrection = true
                            // Chinese recognition is unavailable on some iOS 13
                            // revisions. Use only languages supported on this OS.
                            let supported = try VNRecognizeTextRequest.supportedRecognitionLanguages(for: level, revision: request.revision)
                            request.recognitionLanguages = languages.filter { supported.contains($0) }
                            guard !request.recognitionLanguages.isEmpty else { throw VisionTimetableRecognizerError.unsupportedLanguages }
                            box.install(request)
                            guard !box.isCancelled else { throw CancellationError() }
                            try VNImageRequestHandler(cgImage: cgImage, orientation: Self.orientation(image.imageOrientation), options: [:]).perform([request])
                            guard !box.isCancelled else { throw CancellationError() }
                            let tokens = (request.results ?? []).compactMap { observation -> VisionTimetableToken? in
                                guard let candidate = observation.topCandidates(1).first else { return nil }
                                let rect = observation.boundingBox
                                guard let box = Self.clipToUnit(AIImportBoundingBox(
                                    x: Double(rect.minX),
                                    y: Double(1 - rect.maxY),
                                    width: Double(rect.width),
                                    height: Double(rect.height)
                                )) else { return nil }
                                return VisionTimetableToken(imageIndex: imageIndex, text: candidate.string,
                                    boundingBox: box,
                                    confidence: Double(candidate.confidence))
                            }
                            continuation.resume(returning: tokens)
                        } catch {
                            continuation.resume(throwing: box.isCancelled ? CancellationError() : error)
                        }
                    }
                }
            }, onCancel: { box.cancel() })
            try Task.checkCancellation()
            return result
        } catch is CancellationError { throw VisionTimetableRecognizerError.cancelled }
    }

    /// Retry only locally detected, occupied grid cells that whole-page OCR missed.
    /// The crop remains local and supplies text evidence; it never adds an API image.
    public func fillMissingGridText(images: [AIImportImage], cells: [[String: Any]]) async throws -> [[String: Any]] {
        try Task.checkCancellation()
        var result = cells
        var attempted = 0
        var cropPixels = 0
        for index in result.indices {
            try Task.checkCancellation()
            guard attempted < 8, let texts = result[index]["texts"] as? [String], texts.isEmpty,
                  let page = result[index]["imageIndex"] as? Int, images.indices.contains(page),
                  let box = result[index]["box"] as? [Double], box.count == 4,
                  box.allSatisfy(\.isFinite), box[0] >= 0, box[1] >= 0, box[2] > 0, box[3] > 0,
                  box[0] + box[2] <= 1.000001, box[1] + box[3] <= 1.000001 else { continue }
            attempted += 1
            let crop: UIImage? = autoreleasepool {
                guard let source = CGImageSourceCreateWithData(images[page].data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                      (3...8192).contains(width), (3...8192).contains(height), width * height <= 16_000_000 else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                let w = Double(oriented.width), h = Double(oriented.height)
                // Inward rounding keeps neighbouring cells out. No padding or resizing.
                let left = ceil(box[0] * w), top = ceil(box[1] * h)
                let right = floor(min(1, box[0] + box[2]) * w), bottom = floor(min(1, box[1] + box[3]) * h)
                guard right > left, bottom > top else { return nil }
                let pixels = Int(right - left) * Int(bottom - top)
                guard pixels <= 4_000_000 - cropPixels else { return nil }
                cropPixels += pixels
                guard let cgCrop = oriented.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top)) else { return nil }
                return UIImage(cgImage: cgCrop)
            }
            try Task.checkCancellation()
            guard let crop else { continue }
            do {
                let tokens = try await recognize(image: crop, imageIndex: page)
                try Task.checkCancellation()
                let text = tokens.sorted {
                    let a = $0.boundingBox, b = $1.boundingBox
                    let ay = a.y + a.height / 2, by = b.y + b.height / 2
                    return ay == by ? a.x < b.x : ay < by
                }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !text.isEmpty {
                    result[index]["texts"] = text
                    result[index]["textSource"] = "cellOCR"
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch VisionTimetableRecognizerError.cancelled {
                throw VisionTimetableRecognizerError.cancelled
            } catch {
                // Optional cell evidence must not discard readable pages or start a model retry.
            }
        }
        try Task.checkCancellation()
        return result
    }

    /// Vision boxes can sit a fraction outside the image. Keep a near-edge
    /// word and drop a box that misses the page, instead of failing the review.
    static func clipToUnit(_ box: AIImportBoundingBox) -> AIImportBoundingBox? {
        let values = [box.x, box.y, box.width, box.height]
        guard values.allSatisfy(\.isFinite), box.width > 0, box.height > 0 else { return nil }
        let slack = 0.01
        guard box.x >= -slack, box.y >= -slack, box.x <= 1 + slack, box.y <= 1 + slack,
              box.x + box.width <= 1 + slack, box.y + box.height <= 1 + slack else { return nil }
        let x = min(1, max(0, box.x))
        let y = min(1, max(0, box.y))
        let right = min(1, max(0, box.x + box.width))
        let bottom = min(1, max(0, box.y + box.height))
        guard right > x, bottom > y else { return nil }
        return AIImportBoundingBox(x: x, y: y, width: right - x, height: bottom - y)
    }

    static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

private final class VisionImportCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRequest?
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func install(_ request: VNRequest) {
        lock.lock()
        self.request = request
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { request.cancel() }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let current = request
        lock.unlock()
        current?.cancel()
    }
}

public enum VisionTimetableRecognizerError: Error, Equatable {
    case invalidImage
    case cancelled
    case unsupportedLanguages
}
extension VisionTimetableRecognizerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取课表图片"
        case .cancelled: return "本机识图已取消"
        case .unsupportedLanguages: return "当前系统不支持所选文字识别语言"
        }
    }
}
