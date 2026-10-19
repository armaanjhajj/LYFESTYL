//
//  UprightImage.swift
//  LYFESTYL
//
//  Library photos arrive as encoded data with an EXIF orientation. Redraw them
//  upright and at the same size cap as camera frames, entirely in memory.
//

import UIKit

enum UprightImage {
    static let maxDimension: CGFloat = 1280

    static func make(from data: Data) -> CGImage? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
            .cgImage
    }
}
