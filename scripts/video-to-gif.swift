// Converts a screen recording to an animated GIF with Apple's own frameworks (no ffmpeg needed).
// Leading and trailing stretches where nothing changes (test runner start-up, final hold) are trimmed.
//   swift scripts/video-to-gif.swift <input.mp4|mov> <output.gif> [width=320] [fps=8] [speed=1.5]
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: video-to-gif <input> <output.gif> [width] [fps] [speed]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let width = args.count > 3 ? Double(args[3]) ?? 320 : 320
let fps = args.count > 4 ? Double(args[4]) ?? 8 : 8
let speed = args.count > 5 ? Double(args[5]) ?? 1.5 : 1.5

let asset = AVURLAsset(url: input)
let semaphore = DispatchSemaphore(value: 0)
var duration = 0.0
var naturalSize = CGSize.zero
Task {
    duration = (try? await asset.load(.duration).seconds) ?? 0
    if let track = try? await asset.loadTracks(withMediaType: .video).first {
        naturalSize = (try? await track.load(.naturalSize)) ?? .zero
    }
    semaphore.signal()
}
semaphore.wait()
guard duration > 0, naturalSize.width > 0 else { fatalError("Could not read \(input.path)") }

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: width, height: width * naturalSize.height / naturalSize.width)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

/// Small grayscale thumbnail for change detection.
func signature(at seconds: Double) -> [UInt8]? {
    let probe = AVAssetImageGenerator(asset: asset)
    probe.appliesPreferredTrackTransform = true
    probe.maximumSize = CGSize(width: 24, height: 52)
    guard let image = try? probe.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil) else { return nil }
    var pixels = [UInt8](repeating: 0, count: image.width * image.height)
    let context = CGContext(
        data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )
    context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

func difference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
    zip(lhs, rhs).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(max(lhs.count, 1))
}

/// A blank launch screen: almost every pixel pure white (the status bar and Dynamic Island are the rest).
func isBlank(_ pixels: [UInt8]) -> Bool {
    Double(pixels.filter { $0 >= 250 }.count) / Double(max(pixels.count, 1)) > 0.9
}

/// First and last moments where the picture differs from the opening / closing frame.
var start = 0.0
var end = duration
if let first = signature(at: 0), let last = signature(at: max(0, duration - 0.1)) {
    var time = 0.0
    while time < duration, let frame = signature(at: time), difference(frame, first) < 4 { time += 0.5 }
    // Skip a blank launch screen at the start, then keep a moment of the first real screen.
    while time < duration, let frame = signature(at: time), isBlank(frame) { time += 0.5 }
    start = time
    time = duration - 0.1
    while time > start, let frame = signature(at: time), difference(frame, last) < 4 { time -= 0.5 }
    end = min(duration, time + 1.5)
}

let frameCount = Int((end - start) / speed * fps)
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
    fatalError("Cannot write \(output.path)")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary

for index in 0..<frameCount {
    let time = CMTime(seconds: start + Double(index) * speed / fps, preferredTimescale: 600)
    if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
        CGImageDestinationAddImage(destination, image, frameProperties)
    }
}
guard CGImageDestinationFinalize(destination) else { fatalError("Failed to write GIF") }
let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print(String(format: "%.1f–%.1f s of %.1f s, %d frames, %.1f MB → %@", start, end, duration, frameCount, Double(bytes) / 1_048_576, output.path))
