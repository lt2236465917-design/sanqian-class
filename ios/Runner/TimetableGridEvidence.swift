import Foundation
import CoreGraphics
import ImageIO

/// Optional local layout evidence. It identifies visible grid positions and
/// summary clocks, never courses, weeks, rooms, or teachers.
enum TimetableGridEvidence {
    private static let maximumPixels = 16_000_000
    private static let maximumDimension = 8_192
    private static let maximumTokens = 20_000
    private static let clockPattern = try! NSRegularExpression(pattern: #"(?<!\d)([0-2]?\d)[:：]([0-5]\d)\s*[-–—~～至]+\s*([0-2]?\d)[:：]([0-5]\d)(?!\d)"#)
    private static let headerPattern = try! NSRegularExpression(pattern: #"^(?:周|星期|礼拜)([一二三四五六日天1-7])$"#)

    private struct Clock: Hashable { let start: Int; let end: Int }
    private struct Cell {
        let row: Int
        let column: Int
        let time: Clock
        let label: String
        let box: [Double]
        let texts: [String]
    }
    private struct Layout {
        let imageIndex: Int
        let columns: [Int]
        let boundaries: [Double]
        let headers: [Int: Int]
        let headerConflict: Bool
        let cells: [Cell]
        var isTemplate: Bool {
            !headerConflict && columns.count == 7 && headers.count >= 3 &&
                headers.allSatisfy { columns.firstIndex(of: $0.key).map { $0 + 1 } == $0.value }
        }
    }

    static func build(images: [AIImportImage], pages: [VisionTimetablePage]) throws -> [[String: Any]] {
        try Task.checkCancellation()
        guard images.count <= 20, images.count == pages.count, Set(pages.map(\.imageIndex)).count == pages.count else { return [] }
        var layouts: [Layout] = []
        var totalPixels = 0
        for page in pages {
            try Task.checkCancellation()
            guard images.indices.contains(page.imageIndex), page.tokens.count <= maximumTokens,
                  page.tokens.reduce(0, { $0 + $1.text.utf16.count }) <= 200_000 else { continue }
            // Each decoded image is released before moving to the next page.
            let layout: Layout? = try autoreleasepool {
                guard let pixels = try grayPixels(images[page.imageIndex].data, remainingPixels: 100_000_000 - totalPixels) else { return nil }
                totalPixels += pixels.width * pixels.height
                guard totalPixels <= 100_000_000 else { return nil }
                return try analyze(pixels.values, width: pixels.width, height: pixels.height, page: page)
            }
            if let layout = layout { layouts.append(layout) }
        }
        let templates = layouts.filter(\.isTemplate)
        var result: [[String: Any]] = []
        for layout in layouts {
            try Task.checkCancellation()
            guard !layout.headerConflict else { continue }
            var headers = layout.headers
            let compatible = layout.columns.count == 7 && layout.headers.allSatisfy {
                layout.columns.firstIndex(of: $0.key).map { $0 + 1 } == $0.value
            } && templates.contains { template in
                template.boundaries.count == layout.boundaries.count &&
                    zip(template.boundaries, layout.boundaries).allSatisfy { abs($0 - $1) <= 0.03 }
            }
            if compatible {
                for (index, column) in layout.columns.enumerated() where headers[column] == nil { headers[column] = index + 1 }
            }
            for cell in layout.cells {
                guard let weekday = headers[cell.column] else { continue }
                result.append([
                    "id": "p\(layout.imageIndex)r\(cell.row)c\(cell.column)",
                    "imageIndex": layout.imageIndex,
                    "weekday": weekday,
                    "startMinute": cell.time.start,
                    "endMinute": cell.time.end,
                    "headerSource": layout.headers[cell.column] != nil ? "visibleHeader" : "sharedSevenColumnHeader",
                    "rowLabel": cell.label,
                    "box": cell.box,
                    "texts": cell.texts
                ])
            }
        }
        return result
    }

    private static func grayPixels(_ data: Data, remainingPixels: Int) throws -> (values: [UInt8], width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              sourceWidth >= 3, sourceHeight >= 3,
              sourceWidth <= maximumDimension, sourceHeight <= maximumDimension,
              sourceWidth * sourceHeight <= min(maximumPixels, remainingPixels) else { return nil }
        try Task.checkCancellation()
        // Transform EXIF orientation before comparing with normalized Vision boxes.
        // The limit equals the source dimension: layout analysis never resizes it.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(sourceWidth, sourceHeight),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let width = image.width, height = image.height
        guard width * height <= maximumPixels else { return nil }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        var gray = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            if y % 64 == 0 { try Task.checkCancellation() }
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let red = 299 * Int(rgba[offset])
                let green = 587 * Int(rgba[offset + 1])
                let blue = 114 * Int(rgba[offset + 2])
                gray[y * width + x] = UInt8((red + green + blue + 500) / 1000)
            }
        }
        return (gray, width, height)
    }

    private static func analyze(_ pixels: [UInt8], width: Int, height: Int, page: VisionTimetablePage) throws -> Layout? {
        let tokens = page.tokens.filter { token in
            let b = token.boundingBox
            return token.imageIndex == page.imageIndex && !token.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                [b.x, b.y, b.width, b.height].allSatisfy(\.isFinite) &&
                b.x >= 0 && b.y >= 0 && b.width > 0 && b.height > 0 && b.x + b.width <= 1.000001 && b.y + b.height <= 1.000001
        }
        var verticalCounts = [Int](repeating: 0, count: width)
        for y in 0..<height {
            if y % 64 == 0 { try Task.checkCancellation() }
            for x in 1..<(width - 1) where abs(Int(pixels[y * width + x + 1]) - Int(pixels[y * width + x - 1])) > 12 { verticalCounts[x] += 1 }
        }
        var xs = lines(verticalCounts, denominator: height)
        guard (5...128).contains(xs.count) else { return nil }
        if xs.first != 0 { xs.insert(0, at: 0) }
        if xs.last! < width - 1 { xs.append(width) }
        let clockTokens = tokens.filter { !clocks($0.text).isEmpty }
        var counts: [Int: Int] = [:]
        for token in clockTokens {
            if let column = cellIndex(centerX(token) * Double(width), edges: xs) { counts[column, default: 0] += 1 }
        }
        guard let maximum = counts.values.max(), maximum >= 2,
              counts.values.filter({ $0 == maximum }).count == 1,
              let labelColumn = counts.first(where: { $0.value == maximum })?.key else { return nil }
        let columns = ((labelColumn + 1)..<(xs.count - 1)).filter { Double(xs[$0 + 1] - xs[$0]) >= Double(width) * 0.04 }
        guard (2...7).contains(columns.count) else { return nil }
        let widths = columns.map { xs[$0 + 1] - xs[$0] }
        guard Double(widths.max()!) <= Double(widths.min()!) * 1.5 else { return nil }
        var horizontalCounts = [Int](repeating: 0, count: height)
        let left = xs[labelColumn], right = xs[columns.last! + 1]
        for y in 1..<(height - 1) {
            if y % 64 == 0 { try Task.checkCancellation() }
            for x in left..<right where abs(Int(pixels[(y + 1) * width + x]) - Int(pixels[(y - 1) * width + x])) > 12 { horizontalCounts[y] += 1 }
        }
        let detectedRows = lines(horizontalCounts, denominator: right - left)
        guard detectedRows.count <= 128 else { return nil }
        let ys = Array(Set([0, height] + detectedRows)).sorted()
        let firstClockY = clockTokens.filter { cellIndex(centerX($0) * Double(width), edges: xs) == labelColumn }.map { centerY($0) }.min() ?? 0
        guard let firstClockRow = cellIndex(firstClockY * Double(height), edges: ys) else { return nil }
        var headers: [Int: Int] = [:]
        var headerConflict = false
        for token in tokens {
            guard let tokenRow = cellIndex(centerY(token) * Double(height), edges: ys), tokenRow < firstClockRow else { continue }
            guard let day = weekday(token.text), let column = cellIndex(centerX(token) * Double(width), edges: xs), columns.contains(column) else { continue }
            if let prior = headers[column], prior != day { headerConflict = true }
            if headers.contains(where: { $0.key != column && $0.value == day }) { headerConflict = true }
            headers[column] = day
        }
        var cells: [Cell] = []
        for row in 0..<(ys.count - 1) {
            try Task.checkCancellation()
            let rowTokens = tokens.filter { cellIndex(centerY($0) * Double(height), edges: ys) == row }
            let labelTokens = rowTokens.filter { cellIndex(centerX($0) * Double(width), edges: xs) == labelColumn }
                .sorted { centerY($0) == centerY($1) ? centerX($0) < centerX($1) : centerY($0) < centerY($1) }
            let times = Set(labelTokens.flatMap { clocks($0.text) })
            guard times.count == 1, let time = times.first else { continue }
            let label = labelTokens.map(\.text).joined(separator: " ")
            guard ["上午", "下午", "晚上", "晚间", "早上", "中午", "全天"].contains(where: label.contains) ||
                    (label.contains("课") && !label.contains("第") && time.end - time.start >= 90) else { continue }
            for column in columns {
                let cellLeft = Double(xs[column]), cellRight = Double(xs[column + 1])
                let inside = rowTokens.filter { token in
                    let b = token.boundingBox
                    let tokenLeft = b.x * Double(width), tokenRight = (b.x + b.width) * Double(width)
                    return max(0, min(tokenRight, cellRight) - max(tokenLeft, cellLeft)) >= 0.5 * min(b.width * Double(width), cellRight - cellLeft)
                }.sorted { centerY($0) == centerY($1) ? centerX($0) < centerX($1) : centerY($0) < centerY($1) }
                if inside.isEmpty {
                    let ink = try hasInk(pixels, width: width, left: xs[column] + 4, top: ys[row] + 4, right: xs[column + 1] - 4, bottom: ys[row + 1] - 4)
                    if !ink { continue }
                }
                cells.append(Cell(row: row, column: column, time: time, label: label,
                    box: [Double(xs[column]) / Double(width), Double(ys[row]) / Double(height), Double(xs[column + 1] - xs[column]) / Double(width), Double(ys[row + 1] - ys[row]) / Double(height)],
                    texts: inside.map(\.text)))
            }
        }
        let first = xs[columns.first!], span = xs[columns.last! + 1] - first
        let boundaries = (columns.map { xs[$0] } + [xs[columns.last! + 1]]).map { Double($0 - first) / Double(span) }
        return Layout(imageIndex: page.imageIndex, columns: columns, boundaries: boundaries, headers: headers, headerConflict: headerConflict, cells: cells)
    }

    private static func centerX(_ token: VisionTimetableToken) -> Double { token.boundingBox.x + token.boundingBox.width / 2 }
    private static func centerY(_ token: VisionTimetableToken) -> Double { token.boundingBox.y + token.boundingBox.height / 2 }
    private static func cellIndex(_ position: Double, edges: [Int]) -> Int? {
        (0..<(edges.count - 1)).first { Double(edges[$0]) <= position && position < Double(edges[$0 + 1]) }
    }
    private static func lines(_ counts: [Int], denominator: Int) -> [Int] {
        guard denominator > 0 else { return [] }
        var result: [Int] = [], sum = 0, count = 0, last = -10
        for (index, value) in counts.enumerated() where Double(value) / Double(denominator) > 0.6 {
            if count > 0 && index - last > 3 { result.append(Int(Double(sum) / Double(count) + 0.5)); sum = 0; count = 0 }
            sum += index; count += 1; last = index
        }
        if count > 0 { result.append(Int(Double(sum) / Double(count) + 0.5)) }
        return result
    }
    private static func clocks(_ text: String) -> [Clock] {
        let range = NSRange(text.startIndex..., in: text)
        return clockPattern.matches(in: text, range: range).compactMap { match in
            let values = (1...4).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
            guard values.count == 4, values[0] < 24, values[2] < 24 else { return nil }
            let start = values[0] * 60 + values[1], end = values[2] * 60 + values[3]
            return start < end ? Clock(start: start, end: end) : nil
        }
    }
    private static func weekday(_ text: String) -> Int? {
        let text = text.filter { !$0.isWhitespace }
        guard let match = headerPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let day = String(text[range])
        if let value = Int(day) { return value }
        return ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7][day]
    }
    private static func hasInk(_ pixels: [UInt8], width: Int, left: Int, top: Int, right: Int, bottom: Int) throws -> Bool {
        guard left < right, top < bottom else { return false }
        var histogram = [Int](repeating: 0, count: 256)
        for y in top..<bottom {
            if y % 32 == 0 { try Task.checkCancellation() }
            for x in left..<right { histogram[Int(pixels[y * width + x])] += 1 }
        }
        let total = (right - left) * (bottom - top)
        var accumulated = 0, median = 0
        for value in 0..<256 { accumulated += histogram[value]; if accumulated > total / 2 { median = value; break } }
        let ink = (0..<256).reduce(0) { $0 + (abs($1 - median) > 40 ? histogram[$1] : 0) }
        return Double(ink) / Double(total) >= 0.003
    }
}
