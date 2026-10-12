// Renders the LuxeBank promo film (1920×1080, 30 fps, H.264) from the demo recording and the app icon,
// with Apple's frameworks only. Run through scripts/make-promo.sh.
//
//   swift scripts/make-promo.swift <demo.mp4> <icon.png> <output.mp4>
//
// Footage times refer to docs/demo/luxebank-demo.mp4 as recorded by scripts/record-demo.sh; re-check them
// (scripts/make-promo.sh prints contact sheets) if the demo is recorded again.
import AppKit
import AVFoundation
import CoreText
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: make-promo <demo.mp4> <icon.png> <output.mp4>\n".utf8))
    exit(2)
}
let footage = AVURLAsset(url: URL(fileURLWithPath: arguments[1]))
guard let icon = NSImage(contentsOfFile: arguments[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot read icon \(arguments[2])")
}
let outputURL = URL(fileURLWithPath: arguments[3])

// MARK: Canvas and timing

let width = 1920, height = 1080, fps = 30.0
let canvas = CGSize(width: width, height: height)

func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 1) -> Double { min(max(value, low), high) }
func easeOut(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 3) }
func easeInOut(_ t: Double) -> Double {
    let t = clamp(t)
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}
func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// Opacity of something visible from `start` to `end`, fading in and out.
func presence(_ time: Double, _ start: Double, _ end: Double, fadeIn: Double = 0.6, fadeOut: Double = 0.4) -> Double {
    if time < start || time > end { return 0 }
    return easeOut((time - start) / fadeIn) * clamp((end - time) / fadeOut)
}

// MARK: Brand colours (Porcelain Titanium)

let ink = NSColor(red: 0.055, green: 0.067, blue: 0.086, alpha: 1)
let secondary = NSColor(red: 0.357, green: 0.384, blue: 0.439, alpha: 1)
let accent = NSColor(red: 0.184, green: 0.357, blue: 0.827, alpha: 1)

// MARK: Footage clips (seconds in the demo recording)

struct Clip {
    let from: Double
    let to: Double
    let speed: Double
    var length: Double { (to - from) / speed }
}

/// The phone's screen plays these clips back to back, starting at `phoneStart`.
let clips = [
    Clip(from: 36, to: 43.5, speed: 1.2), // PIN → home
    Clip(from: 43.5, to: 50, speed: 1.4), // home, scrolling
    Clip(from: 61.5, to: 79, speed: 2.6), // PromptPay number and amount
    Clip(from: 79, to: 91.5, speed: 2.2), // review and PIN, up to the slip
    Clip(from: 91.5, to: 95, speed: 1.0), // slip held
    Clip(from: 99.5, to: 103, speed: 1.0), // cards
    Clip(from: 103.5, to: 107, speed: 1.0), // profile
]
let phoneStart = 6.0
let clipStarts = clips.reduce(into: [phoneStart]) { $0.append($0.last! + $1.length) }
let phoneEnd = clipStarts.last!

func footageTime(at time: Double) -> Double? {
    guard time >= phoneStart, time < phoneEnd else { return nil }
    for (index, clip) in clips.enumerated() where time < clipStarts[index + 1] {
        return clip.from + (time - clipStarts[index]) * clip.speed
    }
    return nil
}

// MARK: Story (on-screen text beside the phone)

struct Caption {
    let start: Double
    let end: Double
    let title: String
    let subtitle: String
}

let captions = [
    // The first caption waits until the phone has moved to the right.
    Caption(start: phoneStart + 2.6, end: clipStarts[2] - 0.2, title: "Unlock in a glance.", subtitle: "PIN or Face ID, bound to your iPhone."),
    Caption(start: clipStarts[2] + 0.2, end: clipStarts[4] - 0.2, title: "Send money\nin seconds.", subtitle: "PromptPay, any Thai bank, your own accounts."),
    Caption(start: clipStarts[4], end: clipStarts[5] - 0.1, title: "Every transfer,\nverified.", subtitle: "A slip with a scannable reference."),
    Caption(start: clipStarts[5] + 0.1, end: clipStarts[6] - 0.1, title: "Your cards.\nYour rules.", subtitle: "Freeze, set limits, reveal with Face ID."),
    Caption(start: clipStarts[6] + 0.1, end: phoneEnd - 0.5, title: "A person,\nnot a call centre.", subtitle: "Your own relationship manager."),
]
let endCardStart = phoneEnd + 0.2
let duration = endCardStart + 4.2

// MARK: Footage frames

let generator = AVAssetImageGenerator(asset: footage)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 900, height: 1956)
generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
var lastFrame: CGImage?
func screen(at seconds: Double) -> CGImage? {
    if let image = try? generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil) {
        lastFrame = image
    }
    return lastFrame
}

// MARK: Drawing helpers (top-left origin)

func drawText(
    _ text: String, in context: CGContext, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor,
    alpha: Double, align: NSTextAlignment = .left, maxWidth: CGFloat = 900, tracking: CGFloat = 0, lineHeight: CGFloat = 1.0
) {
    guard alpha > 0.001 else { return }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    paragraph.lineHeightMultiple = lineHeight
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color.withAlphaComponent(alpha),
        .paragraphStyle: paragraph,
        .kern: tracking,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.boundingRect(with: CGSize(width: maxWidth, height: 2000), options: [.usesLineFragmentOrigin])
    var origin = point
    if align == .center { origin.x -= maxWidth / 2 }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    string.draw(with: CGRect(x: origin.x, y: origin.y, width: maxWidth, height: bounds.height + 20), options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
}

func drawImage(_ image: CGImage, in context: CGContext, rect: CGRect, alpha: Double = 1) {
    context.saveGState()
    context.setAlpha(alpha)
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
}

func drawBackground(in context: CGContext, glowAt glow: CGPoint, glowStrength: Double) {
    let colors = [NSColor(red: 0.965, green: 0.969, blue: 0.980, alpha: 1).cgColor, NSColor(red: 0.906, green: 0.918, blue: 0.945, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
    let glowColors = [
        NSColor(red: 0.55, green: 0.69, blue: 1, alpha: 0.38 * glowStrength).cgColor,
        NSColor(red: 0.55, green: 0.69, blue: 1, alpha: 0).cgColor,
    ]
    let glowGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glowGradient, startCenter: glow, startRadius: 0, endCenter: glow, endRadius: 620, options: [])
}

/// A generic phone: black body, screen, Dynamic Island, soft shadow.
func drawPhone(in context: CGContext, center: CGPoint, height phoneHeight: CGFloat, screenImage: CGImage?, alpha: Double) {
    guard alpha > 0.001 else { return }
    let screenAspect: CGFloat = 1206.0 / 2622.0
    let bezel = phoneHeight * 0.018
    let screenHeight = phoneHeight - bezel * 2
    let screenWidth = screenHeight * screenAspect
    let body = CGRect(x: center.x - screenWidth / 2 - bezel, y: center.y - phoneHeight / 2, width: screenWidth + bezel * 2, height: phoneHeight)
    let radius = body.width * 0.17
    context.saveGState()
    context.setAlpha(alpha)
    context.setShadow(offset: CGSize(width: 0, height: 40), blur: 90, color: NSColor(red: 0.16, green: 0.24, blue: 0.43, alpha: 0.28).cgColor)
    context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0)
    // Titanium edge highlight.
    context.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setStrokeColor(NSColor(white: 0.55, alpha: 0.9).cgColor)
    context.setLineWidth(3)
    context.strokePath()
    let screenRect = body.insetBy(dx: bezel, dy: bezel)
    let screenRadius = radius - bezel
    context.addPath(CGPath(roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil))
    context.clip()
    if let screenImage {
        context.translateBy(x: screenRect.minX, y: screenRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(screenImage, in: CGRect(origin: .zero, size: screenRect.size))
    } else {
        context.setFillColor(NSColor.white.cgColor)
        context.fill(screenRect)
    }
    context.restoreGState()
    // Dynamic Island.
    context.saveGState()
    context.setAlpha(alpha)
    let island = CGRect(x: center.x - screenWidth * 0.155, y: body.minY + bezel + screenHeight * 0.014, width: screenWidth * 0.31, height: screenHeight * 0.04)
    context.addPath(CGPath(roundedRect: island, cornerWidth: island.height / 2, cornerHeight: island.height / 2, transform: nil))
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()
}

// MARK: Frame

func render(_ time: Double, into context: CGContext) {
    // Phone layout: rises in at 6 s centred, then sits right of centre while captions play on the left.
    let rise = easeOut((time - phoneStart + 0.6) / 1.2)
    let settle = easeInOut((time - (phoneStart + 2.2)) / 1.0)
    let leave = easeInOut((time - (phoneEnd - 0.4)) / 0.8)
    let phoneX = mix(mix(960, 1290, settle), 960, leave)
    let phoneY = mix(1080 + 520, 540, rise) - 40 * leave
    let phoneHeight: CGFloat = mix(900, 940, settle)
    let phoneAlpha = clamp((time - (phoneStart - 0.6)) / 0.3) * (1 - leave)

    drawBackground(in: context, glowAt: CGPoint(x: phoneX, y: 470), glowStrength: max(phoneAlpha, presence(time, 0, 6.2, fadeIn: 1.5)))

    // 0–3 s: wordmark.
    let mark = presence(time, 0.3, 3.0, fadeIn: 0.9, fadeOut: 0.5)
    if mark > 0 {
        let lift = 18 * (1 - easeOut((time - 0.3) / 1.2))
        drawImage(icon, in: context, rect: CGRect(x: 960 - 70, y: 330 + lift, width: 140, height: 140), alpha: mark)
        drawText("LuxeBank", in: context, at: CGPoint(x: 960, y: 500 + lift), size: 120, weight: .bold, color: ink, alpha: mark,
                 align: .center, maxWidth: 1400, tracking: -3)
    }

    // 3–6 s: promise.
    let line1 = presence(time, 3.1, 6.0, fadeIn: 0.7, fadeOut: 0.45)
    let line2 = presence(time, 3.7, 6.0, fadeIn: 0.7, fadeOut: 0.45)
    drawText("Your money.", in: context, at: CGPoint(x: 960, y: 380 + 14 * (1 - easeOut((time - 3.1) / 0.8))), size: 104, weight: .bold,
             color: ink, alpha: line1, align: .center, maxWidth: 1600, tracking: -2.5)
    drawText("Beautifully in control.", in: context, at: CGPoint(x: 960, y: 500 + 14 * (1 - easeOut((time - 3.7) / 0.8))), size: 104,
             weight: .bold, color: accent, alpha: line2, align: .center, maxWidth: 1600, tracking: -2.5)

    // 6 s on: the phone with footage.
    if phoneAlpha > 0 {
        // Before the first clip show its first frame; after the last, hold its last frame while the phone leaves.
        let seconds = footageTime(at: min(max(time, phoneStart), phoneEnd - 0.01)) ?? clips[0].from
        drawPhone(in: context, center: CGPoint(x: phoneX, y: phoneY), height: phoneHeight, screenImage: screen(at: seconds), alpha: phoneAlpha)
    }

    // Captions on the left.
    for caption in captions {
        let alpha = presence(time, caption.start, caption.end, fadeIn: 0.55, fadeOut: 0.35)
        guard alpha > 0 else { continue }
        let lift = 16 * (1 - easeOut((time - caption.start) / 0.7))
        let lines = CGFloat(caption.title.split(separator: "\n").count)
        let top = 540 - (lines * 92 + 60) / 2 + lift
        drawText(caption.title, in: context, at: CGPoint(x: 170, y: top), size: 84, weight: .bold, color: ink, alpha: alpha,
                 maxWidth: 820, tracking: -2, lineHeight: 0.98)
        drawText(caption.subtitle, in: context, at: CGPoint(x: 172, y: top + lines * 92 + 22), size: 34, weight: .medium,
                 color: secondary, alpha: alpha * clamp((time - caption.start - 0.2) / 0.5), maxWidth: 820)
    }

    // End card.
    let end = presence(time, endCardStart, duration + 1, fadeIn: 0.9)
    if end > 0 {
        let lift = 18 * (1 - easeOut((time - endCardStart) / 1.2))
        drawImage(icon, in: context, rect: CGRect(x: 960 - 90, y: 285 + lift, width: 180, height: 180), alpha: end)
        drawText("LuxeBank", in: context, at: CGPoint(x: 960, y: 495 + lift), size: 110, weight: .bold, color: ink, alpha: end,
                 align: .center, maxWidth: 1400, tracking: -3)
        drawText("Private banking, reimagined.", in: context, at: CGPoint(x: 960, y: 640 + lift), size: 42, weight: .medium,
                 color: secondary, alpha: end * clamp((time - endCardStart - 0.4) / 0.7), align: .center, maxWidth: 1400)
        drawText("Demo with simulated data", in: context, at: CGPoint(x: 960, y: 960), size: 20, weight: .regular,
                 color: secondary, alpha: end * 0.8 * clamp((time - endCardStart - 0.8) / 0.7), align: .center, maxWidth: 1400)
    }
}

// MARK: Writer

try? FileManager.default.removeItem(at: outputURL)
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let frameCount = Int(duration * fps)
for index in 0..<frameCount {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    guard let pool = adaptor.pixelBufferPool else { fatalError("No pixel buffer pool") }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let pixelBuffer = buffer else { fatalError("No pixel buffer") }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )!
    // Top-left origin for all drawing.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    render(Double(index) / fps, into: context)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
    if index % 150 == 0 { print("frame \(index)/\(frameCount)") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("Writing failed: \(String(describing: writer.error))") }
let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
print(String(format: "%.1f s, %d frames, %.1f MB → %@", duration, frameCount, Double(bytes) / 1_048_576, outputURL.path))
