import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct LensUploadResult: Sendable {
    let resultsURL: URL
    let cookies: [HTTPCookie]
}

enum GoogleLensError: LocalizedError {
    case imageEncodingFailed
    case noRedirectURL
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Could not encode the selected region."
        case .noRedirectURL:
            return "Google Lens did not return a results URL."
        case .uploadFailed(let msg):
            return "Google Lens upload failed: \(msg)"
        }
    }
}

enum GoogleLensService {
    // Standard desktop Safari UA so Google Lens serves the clean desktop multi-column results layout
    static let desktopSafariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func uploadImage(_ image: CGImage, existingCookies: [HTTPCookie] = []) async throws -> LensUploadResult {
        guard let imageData = encodeOptimizedJPEG(image) else {
            throw GoogleLensError.imageEncodingFailed
        }

        let boundary = "----CircleToSearch\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"encoded_image\"; filename=\"search.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        guard let uploadURL = URL(string: "https://lens.google.com/v3/upload") else {
            throw GoogleLensError.noRedirectURL
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(desktopSafariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://lens.google.com", forHTTPHeaderField: "Origin")
        request.setValue("https://lens.google.com/", forHTTPHeaderField: "Referer")

        let config = URLSessionConfiguration.default
        if !existingCookies.isEmpty {
            let cookieStorage = HTTPCookieStorage.shared
            for cookie in existingCookies {
                cookieStorage.setCookie(cookie)
            }
            config.httpCookieStorage = cookieStorage
        }

        let delegate = RedirectCatchingDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (_, response) = try await session.data(for: request)

        var capturedCookies = delegate.cookies
        if capturedCookies.isEmpty,
           let httpResponse = response as? HTTPURLResponse,
           let headerFields = httpResponse.allHeaderFields as? [String: String],
           let respURL = httpResponse.url {
            capturedCookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: respURL)
        }

        if let location = delegate.redirectURL {
            return LensUploadResult(resultsURL: location, cookies: capturedCookies)
        }

        if let httpResponse = response as? HTTPURLResponse,
           let locStr = httpResponse.value(forHTTPHeaderField: "Location"),
           let locURL = URL(string: locStr) {
            return LensUploadResult(resultsURL: locURL, cookies: capturedCookies)
        }

        throw GoogleLensError.noRedirectURL
    }

    static func multisearchURL(from baseURL: URL, query: String) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "q" }
        items.append(URLQueryItem(name: "q", value: trimmed))
        components.queryItems = items
        return components.url ?? baseURL
    }

    private static let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

    private static func encodeOptimizedJPEG(_ image: CGImage) -> Data? {
        let maxDim: CGFloat = 1200
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1.0, maxDim / max(width, height))
        let targetW = max(1, Int((width * scale).rounded()))
        let targetH = max(1, Int((height * scale).rounded()))

        let finalImage: CGImage
        if scale < 1.0,
           let ctx = CGContext(
               data: nil,
               width: targetW,
               height: targetH,
               bitsPerComponent: 8,
               bytesPerRow: 0,
               space: rgbColorSpace,
               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
           ) {
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
            finalImage = ctx.makeImage() ?? image
        } else {
            finalImage = image
        }

        let mutableData = CFDataCreateMutable(nil, 0)!
        if let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) {
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.86
            ]
            CGImageDestinationAddImage(destination, finalImage, options as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                return mutableData as Data
            }
        }

        let rep = NSBitmapImageRep(cgImage: finalImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
            ?? rep.representation(using: .png, properties: [:])
    }
}

private final class RedirectCatchingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var redirectURL: URL?
    var cookies: [HTTPCookie] = []

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let headerFields = response.allHeaderFields as? [String: String],
           let respURL = response.url {
            cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: respURL)
        }
        if let location = response.value(forHTTPHeaderField: "Location"),
           let url = URL(string: location) {
            redirectURL = url
        } else {
            redirectURL = request.url
        }
        completionHandler(nil)
    }
}
