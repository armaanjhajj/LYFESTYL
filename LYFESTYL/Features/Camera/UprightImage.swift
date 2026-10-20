//
//  UprightImage.swift
//  LYFESTYL
//
//  Library photos arrive as encoded data with an EXIF orientation. ImageIO
//  decodes them upright and already shrunk to the camera frames' size cap, so
//  a 48 MP HEIC never sits in memory at full size. All in memory, off the
//  main thread.
//

import Foundation
import ImageIO

nonisolated enum UprightImage {
    static let maxDimension: CGFloat = 2560

    @concurrent
    static func make(from data: Data) async -> CGImage? {
        downsample(data, maxPixelSize: maxDimension)
    }

    /// Upright, with the longest side at most `maxPixelSize`.
    static func downsample(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
