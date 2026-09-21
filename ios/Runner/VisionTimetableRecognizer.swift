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
                                return VisionTimetableToken(imageIndex: imageIndex, text: candidate.string,
                                    boundingBox: AIImportBoundingBox(x: Double(rect.minX), y: Double(1 - rect.maxY), width: Double(rect.width), height: Double(rect.height)),
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
