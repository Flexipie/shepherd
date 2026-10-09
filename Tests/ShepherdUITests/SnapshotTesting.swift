import AppKit
import Foundation
import SwiftUI
import Testing

/// Renders views with `ImageRenderer` and compares them with reference PNGs in `__Snapshots__`.
///
/// Anti-aliasing differs between OS builds, so references are compared strictly only on the build
/// they were recorded on (`__Snapshots__/RECORDED_ON`). Elsewhere, such as CI, views are rendered
/// without comparing and written to `.build/snapshot-renders/` to upload, which still proves they
/// render. `SHEPHERD_RECORD_SNAPSHOTS=1` rewrites the references.
@MainActor
enum Snapshot {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "__Snapshots__")
    static let buildDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build")
    static let recording = ProcessInfo.processInfo.environment["SHEPHERD_RECORD_SNAPSHOTS"] == "1"

    /// A channel differing by more than this is a different pixel.
    static let channelTolerance = 8
    /// The share of different pixels that fails the comparison.
    static let pixelTolerance = 0.005

    static var osBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static var recordedOn: String? {
        (try? String(contentsOf: directory.appending(path: "RECORDED_ON"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Renders `view` in light and dark at `width` and checks both.
    static func check(_ name: String, width: CGFloat, sourceLocation: SourceLocation = #_sourceLocation,
                      @ViewBuilder _ view: () -> some View) throws {
        for scheme in [ColorScheme.light, .dark] {
            let file = "\(name).\(scheme == .light ? "light" : "dark").png"
            let png = try #require(render(view(), width: width, scheme: scheme), "\(file) did not render", sourceLocation: sourceLocation)
            if recording {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try png.write(to: directory.appending(path: file))
                try Data((osBuild + "\n").utf8).write(to: directory.appending(path: "RECORDED_ON"))
                continue
            }
            guard recordedOn == osBuild else {
                let renders = buildDirectory.appending(path: "snapshot-renders")
                try FileManager.default.createDirectory(at: renders, withIntermediateDirectories: true)
                try png.write(to: renders.appending(path: file))
                continue
            }
            let reference = try #require(try? Data(contentsOf: directory.appending(path: file)),
                                         "no reference \(file); record with SHEPHERD_RECORD_SNAPSHOTS=1", sourceLocation: sourceLocation)
            if let failure = compare(png, reference) {
                let failures = buildDirectory.appending(path: "snapshot-failures")
                try FileManager.default.createDirectory(at: failures, withIntermediateDirectories: true)
                try png.write(to: failures.appending(path: file))
                if let diff = failure.diff { try diff.write(to: failures.appending(path: file.replacingOccurrences(of: ".png", with: ".diff.png"))) }
                Issue.record("\(file): \(failure.message); see .build/snapshot-failures/", sourceLocation: sourceLocation)
            }
        }
    }

    static func render(_ view: some View, width: CGFloat, scheme: ColorScheme) -> Data? {
        let framed = view
            .frame(width: width)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.95))
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en_US"))
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return pngData(image)
    }

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    struct Failure {
        let message: String
        let diff: Data?
    }

    /// Compares in RGBA8 sRGB. Returns nil when the images match within tolerance.
    static func compare(_ actual: Data, _ reference: Data) -> Failure? {
        if actual == reference { return nil }
        guard let a = pixels(actual), let b = pixels(reference) else { return Failure(message: "unreadable PNG", diff: nil) }
        guard a.width == b.width, a.height == b.height else {
            return Failure(message: "size \(a.width)x\(a.height), expected \(b.width)x\(b.height)", diff: nil)
        }
        var different = 0
        var diff = [UInt8](repeating: 0, count: a.bytes.count)
        // Raw buffers: array subscripts are slow enough in debug builds to matter here.
        a.bytes.withUnsafeBufferPointer { a in
            b.bytes.withUnsafeBufferPointer { b in
                diff.withUnsafeMutableBufferPointer { diff in
                    for pixel in stride(from: 0, to: a.count, by: 4) {
                        var off = false
                        for channel in pixel..<pixel + 4 where abs(Int(a[channel]) - Int(b[channel])) > channelTolerance {
                            off = true
                        }
                        if off { different += 1 }
                        diff[pixel] = off ? 255 : a[pixel] / 4
                        diff[pixel + 1] = off ? 0 : a[pixel + 1] / 4
                        diff[pixel + 2] = off ? 0 : a[pixel + 2] / 4
                        diff[pixel + 3] = 255
                    }
                }
            }
        }
        let share = Double(different) / Double(a.width * a.height)
        guard share > pixelTolerance else { return nil }
        let image = makeImage(diff, width: a.width, height: a.height)
        return Failure(message: String(format: "%.2f%% of pixels differ", share * 100), diff: image.flatMap(pngData))
    }

    struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    static func pixels(_ png: Data) -> Pixels? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Pixels(bytes: bytes, width: width, height: height) : nil
    }

    static func makeImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        var bytes = bytes
        return bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .makeImage()
        }
    }
}
