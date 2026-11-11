import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum PageLayout: String, CaseIterable, Identifiable {
    case columns = "雜誌左右兩欄", single = "單欄／已裁切"
    var id: String { rawValue }
}
struct PreparedPage {
    let original: CGImage
    let cleaned: CGImage
}
enum ImagePreparation {
    static func prepare(_ image: UIImage) async throws -> PreparedPage {
        // Redrawing applies EXIF orientation and caps memory for multi-photo imports.
        let scale = min(1, 3600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = upright.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        return try await Task.detached(priority: .userInitiated) {
            let context = CIContext(options: [.cacheIntermediates: false])
            var page = CIImage(cgImage: cgImage)
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 1
            request.minimumConfidence = 0.8
            request.minimumSize = 0.65
            request.minimumAspectRatio = 0.4
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            if let rectangle = request.results?.first {
                let extent = page.extent
                func vector(_ point: CGPoint) -> CIVector {
                    CIVector(x: extent.minX + point.x * extent.width, y: extent.minY + point.y * extent.height)
                }
                page = page.applyingFilter("CIPerspectiveCorrection", parameters: [
                    "inputTopLeft": vector(rectangle.topLeft), "inputTopRight": vector(rectangle.topRight),
                    "inputBottomLeft": vector(rectangle.bottomLeft), "inputBottomRight": vector(rectangle.bottomRight)
                ])
            }
            let normalized = removeShadows(page)
            guard let original = context.createCGImage(page, from: page.extent),
                  let cleaned = context.createCGImage(normalized, from: normalized.extent) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return PreparedPage(original: original, cleaned: cleaned)
        }.value
    }
    static func removeShadows(_ page: CIImage) -> CIImage {
        let gray = page.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        // Estimate paper illumination, then divide the original luminance by it.
        let radius = max(28, min(gray.extent.width, gray.extent.height) / 32)
        let illumination = gray.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: gray.extent)
        // CIDivideBlendMode computes background / input, so illumination is input.
        return illumination.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: gray])
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.12])
            .cropped(to: gray.extent)
    }
}
