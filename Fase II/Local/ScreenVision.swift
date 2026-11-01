import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

/// Resultado de procesar una captura en el equipo.
nonisolated struct ScreenAnalysis: @unchecked Sendable {
    let original: CGImage
    let redacted: CGImage
    /// Texto reconocido con los datos personales ya reemplazados.
    let maskedText: String
    /// Zonas tapadas en coordenadas normalizadas con origen arriba a la izquierda.
    let redactions: [CGRect]
    let piiCounts: [BlindFilter.Kind: Int]
    let lineCount: Int
    let ocrMilliseconds: Int

    var piiTotal: Int { piiCounts.values.reduce(0, +) }
}

nonisolated enum ScreenVisionError: LocalizedError {
    case permissionDenied
    case noDisplay
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Agente OS necesita permiso de Grabación de pantalla. Actívalo en Configuración del Sistema > Privacidad y seguridad y vuelve a intentar."
        case .noDisplay: "No se encontró una pantalla para capturar."
        case .unreadableImage: "No se pudo leer la imagen seleccionada."
        }
    }
}

/// Capa Local: captura, OCR con Vision y Filtro Ciego sobre la imagen.
nonisolated enum ScreenVision {

    /// Captura la pantalla principal sin incluir las ventanas de esta app.
    static func captureMainDisplay() async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenVisionError.permissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw ScreenVisionError.noDisplay
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func loadImage(from url: URL) throws -> CGImage {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenVisionError.unreadableImage
        }
        return image
    }

    /// Reconoce el texto, detecta datos personales y tapa sus zonas en la imagen.
    @concurrent
    static func analyze(_ image: CGImage) async throws -> ScreenAnalysis {
        let clock = ContinuousClock.now
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "es-MX"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: image, orientation: nil)

        var lines: [String] = []
        var boxes: [NormalizedRect] = []
        var counts: [BlindFilter.Kind: Int] = [:]

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let found = BlindFilter.findings(in: text)
            for finding in found {
                counts[finding.kind, default: 0] += 1
                if let box = candidate.boundingBox(for: finding.range) {
                    boxes.append(box.boundingBox)
                } else {
                    boxes.append(observation.boundingBox)
                }
            }
            lines.append(BlindFilter.mask(text).masked)
        }

        let size = CGSize(width: image.width, height: image.height)
        let pixelRects = boxes.map { $0.toImageCoordinates(size, origin: .lowerLeft).insetBy(dx: -4, dy: -3) }
        let redacted = drawRedactions(on: image, rects: pixelRects) ?? image
        let overlay = boxes.map { $0.toImageCoordinates(CGSize(width: 1, height: 1), origin: .upperLeft) }

        let elapsed = ContinuousClock.now - clock
        let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return ScreenAnalysis(
            original: image, redacted: redacted, maskedText: lines.joined(separator: "\n"),
            redactions: overlay, piiCounts: counts, lineCount: lines.count, ocrMilliseconds: ms
        )
    }

    private static func drawRedactions(on image: CGImage, rects: [CGRect]) -> CGImage? {
        guard !rects.isEmpty else { return image }
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(rects)
        return ctx.makeImage()
    }

    /// JPEG reducido para enviar a la Capa Nube. Solo se usa la versión ya tapada.
    @concurrent
    static func jpegBase64(_ image: CGImage, maxDimension: Int = 1600, quality: Double = 0.75) async -> String? {
        let longest = max(image.width, image.height)
        let scale = longest > maxDimension ? Double(maxDimension) / Double(longest) : 1
        let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (data as Data).base64EncodedString()
    }
}
