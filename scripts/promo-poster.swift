// README poster for the promo film: one frame of the film with a play button.
//   swift scripts/promo-poster.swift <film.mp4> <seconds> <poster.jpg>
import AppKit
import AVFoundation

let arguments = CommandLine.arguments
let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: arguments[1])))
generator.maximumSize = CGSize(width: 1280, height: 720)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
guard let seconds = Double(arguments[2]),
      let frame = try? generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil) else {
    fatalError("Cannot read a frame from \(arguments[1])")
}
let size = NSSize(width: frame.width, height: frame.height)
let poster = NSImage(size: size)
poster.lockFocus()
NSImage(cgImage: frame, size: size).draw(in: NSRect(origin: .zero, size: size))
// Play button: dark disc with a white triangle, low in the frame so the headline stays readable.
let diameter = size.height * 0.16
let disc = NSRect(x: (size.width - diameter) / 2, y: size.height * 0.16, width: diameter, height: diameter)
NSColor(red: 0.055, green: 0.067, blue: 0.086, alpha: 0.82).setFill()
NSBezierPath(ovalIn: disc).fill()
let triangle = NSBezierPath()
let side = diameter * 0.36
triangle.move(to: NSPoint(x: disc.midX - side * 0.38, y: disc.midY + side / 2))
triangle.line(to: NSPoint(x: disc.midX - side * 0.38, y: disc.midY - side / 2))
triangle.line(to: NSPoint(x: disc.midX + side * 0.55, y: disc.midY))
triangle.close()
NSColor.white.setFill()
triangle.fill()
poster.unlockFocus()
guard let tiff = poster.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { fatalError("Cannot encode poster") }
try jpeg.write(to: URL(fileURLWithPath: arguments[3]))
