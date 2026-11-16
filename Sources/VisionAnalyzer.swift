import AppKit
import CoreGraphics
import CoreImage
import Foundation
import NaturalLanguage
import Vision

struct RecognizedTextBlock: Sendable {
    let text: String
    /// Normalized rect in top-left origin coordinates (0...1, where y=0 is top).
    let normalizedTopLeftRect: CGRect
}

struct VisionAnalysisResult: Sendable {
    let text: String
    let cleanPreviewText: String
    let blocks: [RecognizedTextBlock]
    let urls: [URL]
    let barcodes: [String]
    let emails: [String]
    let phoneNumbers: [String]
    let dates: [Date]
    let isSystemLanguage: Bool
    let tableTSV: String?
    let tableCSV: String?
    let dominantHexColor: String
    let dominantRGB: (r: CGFloat, g: CGFloat, b: CGFloat)
    let hasVibrantColorSwatch: Bool
    let isLowInformation: Bool
    let classificationLabels: [String]
    let mathSolution: (expression: String, result: String)?
    let averageConfidence: Double
    let isMostlyText: Bool

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && barcodes.isEmpty
    }
}

enum VisionAnalyzer {
    private static let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    private static let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let smartDataDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.date.rawValue
    )
    private static let mathExpressionRegex = try? NSRegularExpression(
        pattern: #"(?:^|\s)(\(?-?\d+(?:\.\d+)?\)?(?:\s*[\+\-\*\/]\s*\(?-?\d+(?:\.\d+)?\)?)+)"#
    )

    static func analyze(image: CGImage) async -> VisionAnalysisResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ocrImage = upscaleSmallCropIfNeeded(image)
                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = .accurate
                textRequest.usesLanguageCorrection = true
                textRequest.automaticallyDetectsLanguage = true
                textRequest.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

                let barcodeRequest = VNDetectBarcodesRequest()
                let classifyRequest = VNClassifyImageRequest()

                let ocrHandler = VNImageRequestHandler(cgImage: ocrImage, options: [:])
                let imageHandler = VNImageRequestHandler(cgImage: image, options: [:])
                let visionGroup = DispatchGroup()
                visionGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    try? ocrHandler.perform([textRequest])
                    visionGroup.leave()
                }
                visionGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    try? imageHandler.perform([barcodeRequest, classifyRequest])
                    visionGroup.leave()
                }
                visionGroup.wait()

                var rawBlocks: [RecognizedTextBlock] = []
                var confidences: [Float] = []
                for obs in textRequest.results ?? [] {
                    guard let top = obs.topCandidates(1).first, top.confidence >= 0.35 else { continue }
                    let str = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !str.isEmpty else { continue }
                    confidences.append(top.confidence)
                    let box = obs.boundingBox
                    let topLeftRect = CGRect(
                        x: box.origin.x,
                        y: 1.0 - box.origin.y - box.height,
                        width: box.width,
                        height: box.height
                    )
                    rawBlocks.append(RecognizedTextBlock(text: str, normalizedTopLeftRect: topLeftRect))
                }

                // Sort reading order: top-to-bottom rows (banded by ~2% height), then left-to-right
                let blocks = rawBlocks.sorted { a, b in
                    if abs(a.normalizedTopLeftRect.minY - b.normalizedTopLeftRect.minY) > 0.018 {
                        return a.normalizedTopLeftRect.minY < b.normalizedTopLeftRect.minY
                    }
                    return a.normalizedTopLeftRect.minX < b.normalizedTopLeftRect.minX
                }
                let lines = blocks.map(\.text)

                let avgConf = confidences.isEmpty ? 0.0 : Double(confidences.reduce(0, +)) / Double(confidences.count)
                let fullText = lines.joined(separator: "\n")
                let rawCleanPreview = makeCleanPreviewSnippet(from: lines)
                let cleanPreview = (avgConf < 0.52 || hasGarbledReplacementJunk(rawCleanPreview)) ? "" : rawCleanPreview

                let totalTextArea = blocks.reduce(0.0) { $0 + Double($1.normalizedTopLeftRect.width * $1.normalizedTopLeftRect.height) }
                let isMostlyText = (lines.count >= 3 && fullText.count >= 40) || totalTextArea >= 0.16

                let barcodes = (barcodeRequest.results ?? [])
                    .compactMap { $0.payloadStringValue }

                let labels: [String] = (classifyRequest.results ?? [])
                    .filter { $0.confidence >= 0.35 }
                    .prefix(3)
                    .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }

                var urls: [URL] = []
                var emails: [String] = []
                let combinedForURLs = ([fullText] + barcodes).joined(separator: "\n")
                if let detector = linkDetector {
                    let nsString = combinedForURLs as NSString
                    let matches = detector.matches(in: combinedForURLs, range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if let url = match.url {
                            if url.scheme?.lowercased() == "mailto" {
                                let addr = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                                if !addr.isEmpty && !emails.contains(addr) {
                                    emails.append(addr)
                                }
                            } else if !urls.contains(url) {
                                urls.append(url)
                            }
                        }
                    }
                }

                var phones: [String] = []
                var dates: [Date] = []
                if !fullText.isEmpty, let dataDetector = smartDataDetector {
                    let nsText = fullText as NSString
                    let matches = dataDetector.matches(in: fullText, range: NSRange(location: 0, length: nsText.length))
                    for match in matches {
                        if match.resultType == .phoneNumber, let p = match.phoneNumber, !phones.contains(p) {
                            phones.append(p)
                        } else if match.resultType == .date, let d = match.date {
                            let matchedSub = nsText.substring(with: match.range)
                            if isRealCalendarDateMatch(matchedSub) {
                                dates.append(d)
                            }
                        }
                    }
                }

                let isSystemLang = detectIsSystemLanguage(fullText)
                let (tsv, csv) = extractTableIfPresent(from: blocks)
                let colorInfo = sampleDominantColorAndDetail(from: image)
                let math = evaluateMathIfPresent(in: fullText)

                // A selection is low-information if there is no text, no barcode, and almost no edge/contrast detail (e.g. blank dark wallpaper/gradient)
                let hasNoTextOrBarcode = fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && barcodes.isEmpty
                let isLowInfo = hasNoTextOrBarcode && colorInfo.edgeEnergy < 0.026 && colorInfo.luminanceStdDev < 0.042

                continuation.resume(returning: VisionAnalysisResult(
                    text: fullText,
                    cleanPreviewText: cleanPreview,
                    blocks: blocks,
                    urls: urls,
                    barcodes: barcodes,
                    emails: emails,
                    phoneNumbers: phones,
                    dates: dates,
                    isSystemLanguage: isSystemLang,
                    tableTSV: tsv,
                    tableCSV: csv,
                    dominantHexColor: colorInfo.hex,
                    dominantRGB: colorInfo.rgb,
                    hasVibrantColorSwatch: colorInfo.isVibrantSwatch && !isLowInfo && fullText.count < 4,
                    isLowInformation: isLowInfo,
                    classificationLabels: labels,
                    mathSolution: math,
                    averageConfidence: avgConf,
                    isMostlyText: isMostlyText
                ))
            }
        }
    }

    /// Upscales tiny crops (< 420px) 2x before Vision OCR without bloating larger captures.
    private static func upscaleSmallCropIfNeeded(_ image: CGImage) -> CGImage {
        let minDim = min(image.width, image.height)
        guard minDim > 0, minDim < 420 else { return image }
        let factor = minDim < 160 ? 3 : 2
        let targetW = min(1600, image.width * factor)
        let targetH = min(1600, image.height * factor)
        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return ctx.makeImage() ?? image
    }

    private static func detectIsSystemLanguage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else { return true }
        let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
        return dominant.rawValue.lowercased().hasPrefix(systemLang.lowercased())
    }

    private static func hasGarbledReplacementJunk(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("\u{FFFD}") || trimmed.contains("###") {
            return true
        }
        let nonSpace = trimmed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard nonSpace.count >= 6 else { return false }
        let symbols = nonSpace.filter { CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0) }
        return Double(symbols.count) / Double(nonSpace.count) > 0.42
    }

    /// Accepts real calendar dates (month/day, slash/dash dates, or weekday/relative day words) and rejects bare times / mm:ss durations.
    private static func isRealCalendarDateMatch(_ substring: String) -> Bool {
        let lower = substring.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        // Reject bare HH:MM or MM:SS patterns without date words
        if lower.range(of: #"^\d{1,2}:\d{2}(?::\d{2})?(?:\s*(?:am|pm))?$"#, options: .regularExpression) != nil {
            return false
        }
        let monthOrWeekday = #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?|today|tomorrow|yesterday)\b"#
        if lower.range(of: monthOrWeekday, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b\d{1,4}[/-]\d{1,2}(?:[/-]\d{1,4})?\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func extractTableIfPresent(from blocks: [RecognizedTextBlock]) -> (tsv: String?, csv: String?) {
        guard blocks.count >= 6 else { return (nil, nil) }
        var rows: [[RecognizedTextBlock]] = []
        for b in blocks {
            if let lastRow = rows.last,
               let first = lastRow.first,
               abs(first.normalizedTopLeftRect.midY - b.normalizedTopLeftRect.midY) < 0.022 {
                rows[rows.count - 1].append(b)
            } else {
                rows.append([b])
            }
        }
        let multiColRows = rows.filter { $0.count >= 2 }
        guard multiColRows.count >= 3 else { return (nil, nil) }

        let sortedRows = rows.map { $0.sorted { $0.normalizedTopLeftRect.minX < $1.normalizedTopLeftRect.minX } }
        let tsv = sortedRows.map { row in row.map(\.text).joined(separator: "\t") }.joined(separator: "\n")
        let csv = sortedRows.map { row in
            row.map { cell in
                let escaped = cell.text.replacingOccurrences(of: "\"", with: "\"\"")
                return (escaped.contains(",") || escaped.contains("\"")) ? "\"\(escaped)\"" : escaped
            }.joined(separator: ",")
        }.joined(separator: "\n")
        return (tsv, csv)
    }

    /// Masks a cropped rectangular CGImage to the user's freehand lasso CGPath (in canvas coordinates).
    static func maskImage(
        _ image: CGImage,
        withCanvasPath canvasPath: CGPath,
        selectionRect: CGRect
    ) -> CGImage {
        let w = image.width
        let h = image.height
        guard w > 4, h > 4, selectionRect.width > 4, selectionRect.height > 4 else { return image }

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        // Map canvas coordinates (flipped or unflipped matching selectionRect) into pixel coordinates [0..w, 0..h]
        // Note: CGContext has bottom-left origin while our overlay canvas is flipped (top-left origin).
        let scaleX = CGFloat(w) / selectionRect.width
        let scaleY = CGFloat(h) / selectionRect.height
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: 0, y: CGFloat(h))
        transform = transform.scaledBy(x: scaleX, y: -scaleY)
        transform = transform.translatedBy(x: -selectionRect.minX, y: -selectionRect.minY)

        if let localPath = canvasPath.copy(using: &transform) {
            ctx.addPath(localPath)
            ctx.clip()
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Removes clipped single-character edge artifacts (e.g. "e HotkeyPreset...") and formats a clean 2-line preview.
    /// Suppresses multi-item UI sidebars/menus into a concise summary instead of concatenating junk labels.
    private static func makeCleanPreviewSnippet(from lines: [String]) -> String {
        let cleanedLines: [String] = lines.compactMap { line in
            var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                let first = String(parts[0])
                let second = String(parts[1])
                if first.count == 1,
                   first.lowercased() != "a",
                   first.lowercased() != "i",
                   first.rangeOfCharacter(from: .decimalDigits) == nil,
                   second.count >= 3 {
                    s = second
                }
            }
            return s
        }
        if cleanedLines.count >= 6 {
            let totalWords = cleanedLines.reduce(0) { $0 + $1.split(separator: " ").count }
            let avgWords = Double(totalWords) / Double(cleanedLines.count)
            let sentenceCount = cleanedLines.filter { line in
                guard let last = line.last else { return false }
                return last == "." || last == "?" || last == "!"
            }.count
            if avgWords <= 3.2 && sentenceCount < 2 {
                return "Sidebar / menu (\(cleanedLines.count) items)"
            }
        }
        return cleanedLines.joined(separator: "  ")
    }

    /// Extracts dominant color swatch AND computes visual variance / edge energy to detect empty/boring selections.
    static func sampleDominantColorAndDetail(
        from image: CGImage
    ) -> (
        hex: String,
        rgb: (r: CGFloat, g: CGFloat, b: CGFloat),
        isVibrantSwatch: Bool,
        luminanceStdDev: Double,
        edgeEnergy: Double
    ) {
        let w = 28
        let h = 28
        var pixelData = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixelData,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ("#3B82F6", (0.23, 0.51, 0.96), false, 0.2, 0.1)
        }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var bestWeight: CGFloat = -1
        var bestR: CGFloat = 0
        var bestG: CGFloat = 0
        var bestB: CGFloat = 0
        var avgR: CGFloat = 0
        var avgG: CGFloat = 0
        var avgB: CGFloat = 0
        var count: CGFloat = 0

        var lumValues: [Double] = []
        lumValues.reserveCapacity(w * h)
        var edgeAccum: Double = 0
        var edgePairs: Double = 0
        var colorBuckets: [Int: (count: Int, r: CGFloat, g: CGFloat, b: CGFloat, satSum: CGFloat)] = [:]

        for y in 2..<(h - 2) {
            for x in 2..<(w - 2) {
                let idx = (y * w + x) * 4
                let a = CGFloat(pixelData[idx + 3]) / 255.0
                guard a > 0.2 else { continue }
                let r = CGFloat(pixelData[idx]) / 255.0
                let g = CGFloat(pixelData[idx + 1]) / 255.0
                let b = CGFloat(pixelData[idx + 2]) / 255.0
                avgR += r
                avgG += g
                avgB += b
                count += 1

                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                lumValues.append(Double(lum))

                // Neighbor edge gradient
                let rightIdx = (y * w + (x + 1)) * 4
                let downIdx = ((y + 1) * w + x) * 4
                let rLum = 0.299 * Double(pixelData[rightIdx]) / 255.0
                    + 0.587 * Double(pixelData[rightIdx + 1]) / 255.0
                    + 0.114 * Double(pixelData[rightIdx + 2]) / 255.0
                let dLum = 0.299 * Double(pixelData[downIdx]) / 255.0
                    + 0.587 * Double(pixelData[downIdx + 1]) / 255.0
                    + 0.114 * Double(pixelData[downIdx + 2]) / 255.0
                edgeAccum += abs(Double(lum) - rLum) + abs(Double(lum) - dLum)
                edgePairs += 2

                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let sat = maxC > 0.05 ? (maxC - minC) / maxC : 0
                let rq = min(15, Int(r * 16))
                let gq = min(15, Int(g * 16))
                let bq = min(15, Int(b * 16))
                let bucketKey = (rq << 8) | (gq << 4) | bq
                let existing = colorBuckets[bucketKey] ?? (0, 0, 0, 0, 0)
                colorBuckets[bucketKey] = (existing.count + 1, existing.r + r, existing.g + g, existing.b + b, existing.satSum + sat)

                let cx = 1.0 - abs(CGFloat(x) / CGFloat(w) - 0.5)
                let cy = 1.0 - abs(CGFloat(y) / CGFloat(h) - 0.5)
                let weight = (sat * 2.2 + 0.25) * (lum > 0.08 && lum < 0.94 ? 1.0 : 0.3) * cx * cy
                if weight > bestWeight {
                    bestWeight = weight
                    bestR = r
                    bestG = g
                    bestB = b
                }
            }
        }

        let meanLum = lumValues.isEmpty ? 0 : lumValues.reduce(0, +) / Double(lumValues.count)
        let variance = lumValues.isEmpty ? 0 : lumValues.reduce(0) { $0 + ($1 - meanLum) * ($1 - meanLum) } / Double(lumValues.count)
        let stdDev = sqrt(variance)
        let meanEdge = edgePairs > 0 ? edgeAccum / edgePairs : 0

        let topBucket = colorBuckets.values.max(by: { $0.count < $1.count })
        let topRatio = (count > 0 && topBucket != nil) ? Double(topBucket!.count) / Double(count) : 0
        let topAvgSat = topBucket != nil ? Double(topBucket!.satSum) / Double(max(1, topBucket!.count)) : 0

        let finalR = topBucket != nil && topRatio >= 0.35 ? (topBucket!.r / CGFloat(topBucket!.count)) : (bestWeight > 0.35 ? bestR : (avgR / max(1, count)))
        let finalG = topBucket != nil && topRatio >= 0.35 ? (topBucket!.g / CGFloat(topBucket!.count)) : (bestWeight > 0.35 ? bestG : (avgG / max(1, count)))
        let finalB = topBucket != nil && topRatio >= 0.35 ? (topBucket!.b / CGFloat(topBucket!.count)) : (bestWeight > 0.35 ? bestB : (avgB / max(1, count)))

        let ri = max(0, min(255, Int((finalR * 255).rounded())))
        let gi = max(0, min(255, Int((finalG * 255).rounded())))
        let bi = max(0, min(255, Int((finalB * 255).rounded())))
        let hex = String(format: "#%02X%02X%02X", ri, gi, bi)
        // Show color chip ONLY when a single color genuinely dominates the selection (not noisy text/landscapes)
        let isDominantColor = (topRatio >= 0.52 && topAvgSat > 0.24) || (topRatio >= 0.72 && stdDev < 0.20)
        return (hex, (finalR, finalG, finalB), isDominantColor, stdDev, meanEdge)
    }

    /// Detects and evaluates arithmetic/math expressions inside recognized text.
    private static func evaluateMathIfPresent(in text: String) -> (expression: String, result: String)? {
        let normalized = text
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "=", with: "")

        guard let regex = mathExpressionRegex else { return nil }
        let nsText = normalized as NSString
        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let exprRaw = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard exprRaw.count >= 3, exprRaw.count <= 42 else { continue }
            guard let val = evaluateArithmetic(exprRaw), val.isFinite else { continue }

            let formatted: String
            if abs(val.rounded() - val) < 1e-6 {
                formatted = String(format: "%.0f", val.rounded())
            } else {
                formatted = String(format: "%.4f", val)
                    .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
            }
            return (exprRaw, formatted)
        }
        return nil
    }

    /// Safe recursive-descent arithmetic evaluator (replaces NSExpression to avoid ObjC exceptions on malformed OCR text).
    private static func evaluateArithmetic(_ input: String) -> Double? {
        let chars = Array(input)
        var index = 0

        func skipSpaces() {
            while index < chars.count && chars[index].isWhitespace {
                index += 1
            }
        }

        func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while true {
                skipSpaces()
                guard index < chars.count else { break }
                let op = chars[index]
                guard op == "+" || op == "-" else { break }
                index += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = (op == "+") ? (lhs + rhs) : (lhs - rhs)
            }
            return lhs
        }

        func parseTerm() -> Double? {
            guard var lhs = parseFactor() else { return nil }
            while true {
                skipSpaces()
                guard index < chars.count else { break }
                let op = chars[index]
                guard op == "*" || op == "/" else { break }
                index += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    lhs /= rhs
                } else {
                    lhs *= rhs
                }
            }
            return lhs
        }

        func parseFactor() -> Double? {
            skipSpaces()
            guard index < chars.count else { return nil }
            if chars[index] == "+" {
                index += 1
                return parseFactor()
            }
            if chars[index] == "-" {
                index += 1
                return parseFactor().map { -$0 }
            }
            if chars[index] == "(" {
                index += 1
                guard let inner = parseExpression() else { return nil }
                skipSpaces()
                guard index < chars.count && chars[index] == ")" else { return nil }
                index += 1
                return inner
            }
            let start = index
            var sawDigit = false
            var sawDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    sawDigit = true
                    index += 1
                } else if c == "." && !sawDot {
                    sawDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard sawDigit else { return nil }
            return Double(String(chars[start..<index]))
        }

        guard let result = parseExpression() else { return nil }
        skipSpaces()
        return index == chars.count ? result : nil
    }

    /// Lifts the foreground subject from the selection with a transparent background using Apple Vision.
    static func liftSubject(from image: CGImage) async -> CGImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    guard let observation = request.results?.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let allInstances = observation.allInstances
                    guard !allInstances.isEmpty else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let maskedBuffer = try observation.generateMaskedImage(
                        ofInstances: allInstances,
                        from: handler,
                        croppedToInstancesExtent: false
                    )
                    let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
                    let cgResult = ciContext.createCGImage(ciImage, from: ciImage.extent)
                    continuation.resume(returning: cgResult)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Smart Tap region detector: finds the salient object or text block under a single click.
    static func detectSmartTapRect(
        in screenshot: CGImage,
        at canvasPoint: CGPoint,
        canvasSize: CGSize
    ) -> CGRect {
        let scaleX = CGFloat(screenshot.width) / max(1, canvasSize.width)
        let scaleY = CGFloat(screenshot.height) / max(1, canvasSize.height)
        let roiW: CGFloat = min(canvasSize.width, 460)
        let roiH: CGFloat = min(canvasSize.height, 420)
        let roiCanvas = CGRect(
            x: max(0, min(canvasSize.width - roiW, canvasPoint.x - roiW / 2)),
            y: max(0, min(canvasSize.height - roiH, canvasPoint.y - roiH / 2)),
            width: roiW,
            height: roiH
        )
        let cropPixels = CGRect(
            x: roiCanvas.minX * scaleX,
            y: roiCanvas.minY * scaleY,
            width: roiCanvas.width * scaleX,
            height: roiCanvas.height * scaleY
        ).integral

        if let subImage = screenshot.cropping(to: cropPixels) {
            let saliencyReq = VNGenerateObjectnessBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: subImage, options: [:])
            try? handler.perform([saliencyReq])

            if let obs = saliencyReq.results?.first,
               let salientObjs = obs.salientObjects,
               !salientObjs.isEmpty {
                let localTapX = (canvasPoint.x - roiCanvas.minX) / roiCanvas.width
                let localTapY = 1.0 - (canvasPoint.y - roiCanvas.minY) / roiCanvas.height
                let tapNorm = CGPoint(x: localTapX, y: localTapY)

                let best = salientObjs.min { a, b in
                    let da = hypot(a.boundingBox.midX - tapNorm.x, a.boundingBox.midY - tapNorm.y)
                    let db = hypot(b.boundingBox.midX - tapNorm.x, b.boundingBox.midY - tapNorm.y)
                    return da < db
                }
                if let box = best?.boundingBox {
                    let topLeftY = 1.0 - box.origin.y - box.height
                    let mapped = CGRect(
                        x: roiCanvas.minX + box.origin.x * roiCanvas.width,
                        y: roiCanvas.minY + topLeftY * roiCanvas.height,
                        width: max(84, box.width * roiCanvas.width),
                        height: max(68, box.height * roiCanvas.height)
                    ).insetBy(dx: -10, dy: -10)
                    return mapped
                }
            }
        }

        let fallbackW: CGFloat = 220
        let fallbackH: CGFloat = 150
        return CGRect(
            x: max(12, min(canvasSize.width - fallbackW - 12, canvasPoint.x - fallbackW / 2)),
            y: max(12, min(canvasSize.height - fallbackH - 12, canvasPoint.y - fallbackH / 2)),
            width: fallbackW,
            height: fallbackH
        )
    }

    /// Translates recognized text blocks in-place using Google's lightweight translate endpoint.
    static func translateBlocks(
        _ blocks: [RecognizedTextBlock],
        targetLanguage: String = "en"
    ) async -> [(rect: CGRect, translated: String)] {
        guard !blocks.isEmpty else { return [] }
        let separator = " ||| "
        let joined = blocks.map(\.text).joined(separator: separator)
        guard let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(targetLanguage)&dt=t&q=\(encoded)") else {
            return blocks.map { ($0.normalizedTopLeftRect, $0.text) }
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let root = try JSONSerialization.jsonObject(with: data) as? [Any],
               let sentences = root.first as? [[Any]] {
                let translatedFull = sentences.compactMap { $0.first as? String }.joined()
                let parts = translatedFull
                    .components(separatedBy: "|||")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                var result: [(rect: CGRect, translated: String)] = []
                for (i, block) in blocks.enumerated() {
                    let tr = i < parts.count && !parts[i].isEmpty ? parts[i] : block.text
                    result.append((block.normalizedTopLeftRect, tr))
                }
                return result
            }
        } catch {
            // Fall back to original blocks if offline
        }
        return blocks.map { ($0.normalizedTopLeftRect, $0.text) }
    }
}
