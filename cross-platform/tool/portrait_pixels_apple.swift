// Read-only host probe for the exact retouch bitmap path. Never dumps photo pixels.
// Run: xcrun swift portrait_pixels_apple.swift known-gradient.png portrait-smile.jpg
// The first input must come from apple_gallery_fixture.py (256 x 192 RGBA).
import Foundation
import CoreGraphics
import ImageIO
import Vision

enum ProbeError: Error { case input(String) }

func decode(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280
          ] as CFDictionary) else { throw ProbeError.input("ImageIO decode failed") }
    return image
}

struct Bitmap {
    let image: CGImage
    let words: [UInt32]
    let ctm: [Double]
}

func bitmap(_ image: CGImage) throws -> Bitmap {
    let width = image.width, height = image.height
    guard let color = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw ProbeError.input("sRGB unavailable")
    }
    let info = CGBitmapInfo.byteOrder32Little.rawValue |
        CGImageAlphaInfo.premultipliedFirst.rawValue
    var words = [UInt32](repeating: 0, count: width * height)
    var ctm = [Double]()
    try words.withUnsafeMutableBytes { data in
        guard let context = CGContext(data: data.baseAddress, width: width,
            height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: color, bitmapInfo: info) else {
            throw ProbeError.input("Bitmap context unavailable")
        }
        let transform = context.ctm
        ctm = [transform.a, transform.b, transform.c, transform.d,
               transform.tx, transform.ty].map(Double.init)
        // Deliberately no CTM change: identical to HueviaMedia::decode.
        context.draw(image, in: CGRect(x: 0, y: 0,
            width: CGFloat(width), height: CGFloat(height)))
    }
    let data = words.withUnsafeBytes { Data($0) }
    guard let provider = CGDataProvider(data: data as CFData),
          let reconstructed = CGImage(width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: color, bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent) else {
        throw ProbeError.input("Raw-provider image unavailable")
    }
    return Bitmap(image: reconstructed, words: words, ctm: ctm)
}

func range(_ values: [Double]) -> [String: Any] {
    guard let first = values.min(), let last = values.max() else { return ["count": 0] }
    return ["count": values.count, "min": first, "max": last]
}

func vision(_ image: CGImage) throws -> [String: Any] {
    let request = VNDetectFaceLandmarksRequest()
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    let faces = request.results ?? []
    var rawAngles = [Double](), sortedAngles = [Double](), observationRoll = [Double]()
    var missingEyes = 0, swaps = 0
    var frames = [[String: Double]]()
    for face in faces {
        if let roll = face.roll { observationRoll.append(roll.doubleValue * 180 / .pi) }
        guard let left = face.landmarks?.leftEye, let right = face.landmarks?.rightEye,
              left.pointCount > 0, right.pointCount > 0 else { missingEyes += 1; continue }
        func center(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
            let points = region.normalizedPoints
            let x = points.reduce(0.0) { $0 + Double($1.x) } / Double(points.count)
            let y = points.reduce(0.0) { $0 + Double($1.y) } / Double(points.count)
            let box = face.boundingBox
            return CGPoint(x: (Double(box.origin.x) + x * Double(box.width)) * Double(image.width),
                y: (1 - Double(box.origin.y) - y * Double(box.height)) * Double(image.height))
        }
        var a = center(left), b = center(right)
        rawAngles.append(atan2(Double(b.y - a.y), Double(b.x - a.x)) * 180 / .pi)
        if a.x > b.x { swap(&a, &b); swaps += 1 }
        let roll = atan2(Double(b.y - a.y), Double(b.x - a.x))
        sortedAngles.append(roll * 180 / .pi)
        let distance = hypot(Double(b.x - a.x), Double(b.y - a.y))
        frames.append(["cx": ((Double(a.x) + Double(b.x)) / 2 - sin(roll) * distance * 0.55) / Double(image.width),
            "cy": ((Double(a.y) + Double(b.y)) / 2 + cos(roll) * distance * 0.55) / Double(image.height),
            "rx": min(0.5, 0.95 * distance / Double(image.width)),
            "ry": min(0.5, 1.35 * distance / Double(image.height)), "roll": roll * 180 / .pi])
    }
    return ["faceCount": faces.count, "missingEyes": missingEyes, "eyeSwapCount": swaps,
        "rawEyeAngleDegrees": range(rawAngles), "currentEyeAngleDegrees": range(sortedAngles),
        "observationRollDegrees": range(observationRoll), "proposalFrames": frames]
}

func means(_ words: [UInt32], width: Int, firstRow: Int, rows: Int) -> [Double] {
    var sums = [UInt64](repeating: 0, count: 4)
    for index in (firstRow * width)..<((firstRow + rows) * width) {
        for channel in 0..<4 { sums[channel] += UInt64((words[index] >> (24 - channel * 8)) & 255) }
    }
    return sums.map { Double($0) / Double(width * rows) }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw ProbeError.input("Pass the known gradient fixture and the fixed portrait asset")
    }
    let pattern = try decode(CommandLine.arguments[1])
    guard pattern.width == 256, pattern.height == 192 else {
        throw ProbeError.input("Expected apple_gallery_fixture.py gradient dimensions")
    }
    let synthetic = try bitmap(pattern)
    func hex(_ value: UInt32) -> String { String(format: "%08x", value) }
    let photo = try decode(CommandLine.arguments[2]), reconstructed = try bitmap(photo)
    let report: [String: Any] = ["schema": 1,
        "syntheticOnlyPixels": ["firstARGB": hex(synthetic.words[0]),
            "lastRowFirstARGB": hex(synthetic.words[191 * 256]),
            "sample17x37ARGB": hex(synthetic.words[37 * 256 + 17]),
            "expectedTopFirstARGB": "ff000000", "expectedBottomFirstARGB": "ff00bf5f",
            "expectedTopSampleARGB": "ff11251b", "expectedBottomSampleARGB": "ff119a55",
            "row0IsPNGTop": synthetic.words[0] == 0xff000000,
            "row0IsPNGBottom": synthetic.words[0] == 0xff00bf5f],
        "bitmapCTM": synthetic.ctm, "bitmapInfo": reconstructed.image.bitmapInfo.rawValue,
        "photoWidth": photo.width, "photoHeight": photo.height,
        "photoRasterMeanARGB": means(reconstructed.words, width: photo.width, firstRow: 0, rows: photo.height),
        "photoRasterFirstRowMeanARGB": means(reconstructed.words, width: photo.width, firstRow: 0, rows: 1),
        "photoRasterLastRowMeanARGB": means(reconstructed.words, width: photo.width, firstRow: photo.height - 1, rows: 1),
        "directImageVision": try vision(photo), "rawProviderVision": try vision(reconstructed.image)]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
    print(String(decoding: data, as: UTF8.self))
} catch {
    fputs("portrait bitmap probe failed: \(error)\n", stderr)
    exit(1)
}
