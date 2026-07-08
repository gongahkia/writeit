#!/usr/bin/env swift
import AppKit
import AVFoundation
import CoreVideo
import Foundation

struct DemoSlide {
    let title: String
    let subtitle: String
    let bullets: [String]
    let accent: NSColor
}

enum DemoRenderError: Error, LocalizedError {
    case cannotCreatePixelBuffer
    case cannotCreateContext
    case cannotCreateImage
    case cannotAddWriterInput
    case appendFailed
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreatePixelBuffer:
            "Could not create a video pixel buffer."
        case .cannotCreateContext:
            "Could not create a bitmap drawing context."
        case .cannotCreateImage:
            "Could not create a rendered demo frame."
        case .cannotAddWriterInput:
            "Could not add the video track to AVAssetWriter."
        case .appendFailed:
            "AVAssetWriter rejected a rendered demo frame."
        case let .writerFailed(message):
            "AVAssetWriter failed: \(message)"
        }
    }
}

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let defaultURL = rootURL.appendingPathComponent(".dist/demo/cerberus-demo.mov")
let requestedPath = CommandLine.arguments.dropFirst().first
if requestedPath == "-h" || requestedPath == "--help" {
    print("usage: Scripts/render_demo_video.swift [output.mov]")
    print("")
    print("env:")
    print("  DEMO_SECONDS=36")
    print("  DEMO_WIDTH=1280")
    print("  DEMO_HEIGHT=720")
    print("  DEMO_FPS=24")
    exit(0)
}
let outputURL = URL(fileURLWithPath: requestedPath ?? defaultURL.path)
let width = envInt("DEMO_WIDTH", defaultValue: 1280, minimum: 640)
let height = envInt("DEMO_HEIGHT", defaultValue: 720, minimum: 360)
let fps = envInt("DEMO_FPS", defaultValue: 24, minimum: 1)
let seconds = envInt("DEMO_SECONDS", defaultValue: 36, minimum: 8)

let slides = [
    DemoSlide(
        title: "cerberus",
        subtitle: "AirPods-driven local assistant for macOS",
        bullets: [
            "menu bar app with explicit wake triggers",
            "on-device speech and Foundation Models planning",
            "spoken replies routed to the active output or AirPods"
        ],
        accent: NSColor(calibratedRed: 0.18, green: 0.65, blue: 0.95, alpha: 1)
    ),
    DemoSlide(
        title: "hands-free flow",
        subtitle: "trigger, listen, reason, observe, speak",
        bullets: [
            "global hotkey, media key, head gesture, or wake phrase",
            "1.5 second silence timeout starts reasoning",
            "earcons and menu state show every transition"
        ],
        accent: NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.54, alpha: 1)
    ),
    DemoSlide(
        title: "screen-only tool surface",
        subtitle: "observer tools without computer operation",
        bullets: [
            "screen snapshots, OCR, barcodes, and UI geometry",
            "native read-only FoundationModels screen tools",
            "no shell, MCP, browser navigation, or app control"
        ],
        accent: NSColor(calibratedRed: 0.95, green: 0.66, blue: 0.25, alpha: 1)
    ),
    DemoSlide(
        title: "local safety trail",
        subtitle: "private screen context stays local",
        bullets: [
            "encrypted transcripts with Keychain keys",
            "HMAC-signed hash-chain audit log",
            "screen snapshots use local cache retention controls"
        ],
        accent: NSColor(calibratedRed: 0.88, green: 0.38, blue: 0.52, alpha: 1)
    ),
    DemoSlide(
        title: "release checks",
        subtitle: "build, demo, signing, notarization, open-source gates",
        bullets: [
            "swift test covers core state, tools, MCP, safety, wake config",
            "Scripts/build_app.sh assembles and signs the app bundle",
            "Scripts/release_check.sh verifies demo and release blockers"
        ],
        accent: NSColor(calibratedRed: 0.58, green: 0.50, blue: 0.92, alpha: 1)
    )
]

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: outputURL)

let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]
)
input.expectsMediaDataInRealTime = false

guard writer.canAdd(input) else {
    throw DemoRenderError.cannotAddWriterInput
}
writer.add(input)

let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]
)

writer.startWriting()
writer.startSession(atSourceTime: .zero)

guard let pixelBufferPool = adaptor.pixelBufferPool else {
    throw DemoRenderError.cannotCreatePixelBuffer
}

let totalFrames = seconds * fps
for frame in 0..<totalFrames {
    while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.01)
    }

    let slideProgress = Double(frame) / Double(totalFrames)
    let slideIndex = min(Int(slideProgress * Double(slides.count)), slides.count - 1)
    let localFrame = frame - slideIndex * (totalFrames / slides.count)
    let localProgress = Double(max(0, localFrame)) / Double(max(1, totalFrames / slides.count))
    let image = renderFrame(slide: slides[slideIndex], slideIndex: slideIndex, progress: localProgress, width: width, height: height)
    let pixelBuffer = try makePixelBuffer(from: image, pool: pixelBufferPool, width: width, height: height)
    let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
    guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
        throw DemoRenderError.appendFailed
    }
}

input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting {
    semaphore.signal()
}
semaphore.wait()

if writer.status != .completed {
    throw DemoRenderError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
}

print(outputURL.path)

func envInt(_ key: String, defaultValue: Int, minimum: Int) -> Int {
    guard let raw = ProcessInfo.processInfo.environment[key], let value = Int(raw) else {
        return defaultValue
    }
    return max(minimum, value)
}

func renderFrame(slide: DemoSlide, slideIndex: Int, progress: Double, width: Int, height: Int) -> NSImage {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.06, alpha: 1).setFill()
    canvas.fill()

    drawBand(rect: canvas, accent: slide.accent, progress: progress)
    drawHeader(slide: slide, width: width, height: height)
    drawFlow(slideIndex: slideIndex, accent: slide.accent, width: width, height: height, progress: progress)
    drawBullets(slide: slide, width: width, height: height)
    drawFooter(slideIndex: slideIndex, slideCount: slides.count, accent: slide.accent, width: width, height: height, progress: progress)

    return image
}

func drawBand(rect: NSRect, accent: NSColor, progress: Double) {
    accent.withAlphaComponent(0.22).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: rect.height - 94, width: rect.width, height: 94)).fill()
    accent.withAlphaComponent(0.12).setFill()
    let sweep = rect.width * CGFloat(0.25 + 0.75 * min(1, progress))
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: sweep, height: 8)).fill()
}

func drawHeader(slide: DemoSlide, width: Int, height: Int) {
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 68, weight: .semibold),
        .foregroundColor: NSColor.white
    ]
    NSString(string: slide.title).draw(with: NSRect(x: 72, y: CGFloat(height - 116), width: CGFloat(width - 144), height: 82), options: [.usesLineFragmentOrigin], attributes: titleAttrs)

    let subtitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 25, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.84, alpha: 1)
    ]
    NSString(string: slide.subtitle).draw(with: NSRect(x: 76, y: CGFloat(height - 156), width: CGFloat(width - 152), height: 42), options: [.usesLineFragmentOrigin], attributes: subtitleAttrs)
}

func drawFlow(slideIndex: Int, accent: NSColor, width: Int, height: Int, progress: Double) {
    let labels = ["trigger", "speech", "model", "tools", "voice"]
    let startX = CGFloat(86)
    let y = CGFloat(height - 318)
    let gap = CGFloat(width - 172) / CGFloat(labels.count - 1)

    for index in labels.indices {
        let center = NSPoint(x: startX + CGFloat(index) * gap, y: y)
        if index > 0 {
            NSColor(calibratedWhite: 0.30, alpha: 1).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 3
            path.move(to: NSPoint(x: center.x - gap + 56, y: center.y + 28))
            path.line(to: NSPoint(x: center.x - 56, y: center.y + 28))
            path.stroke()
        }

        let active = index == min(labels.count - 1, Int(progress * Double(labels.count)))
        (active ? accent : NSColor(calibratedWhite: 0.18, alpha: 1)).setFill()
        let pill = NSBezierPath(roundedRect: NSRect(x: center.x - 66, y: center.y, width: 132, height: 56), xRadius: 12, yRadius: 12)
        pill.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
            .foregroundColor: active ? NSColor.black : NSColor.white
        ]
        NSString(string: labels[index]).draw(with: NSRect(x: center.x - 58, y: center.y + 17, width: 116, height: 24), options: [.usesLineFragmentOrigin], attributes: attrs)
    }

    let badgeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1)
    ]
    NSString(string: "slide \(slideIndex + 1)").draw(with: NSRect(x: CGFloat(width - 180), y: CGFloat(height - 56), width: 110, height: 24), options: [.usesLineFragmentOrigin], attributes: badgeAttrs)
}

func drawBullets(slide: DemoSlide, width: Int, height: Int) {
    let left = CGFloat(110)
    let top = CGFloat(height - 430)
    let bulletAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.91, alpha: 1)
    ]
    let markAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 28, weight: .semibold),
        .foregroundColor: slide.accent
    ]

    for (index, bullet) in slide.bullets.enumerated() {
        let y = top - CGFloat(index * 64)
        NSString(string: "->").draw(with: NSRect(x: left, y: y, width: 48, height: 38), options: [.usesLineFragmentOrigin], attributes: markAttrs)
        NSString(string: bullet).draw(with: NSRect(x: left + 58, y: y, width: CGFloat(width) - left - 140, height: 44), options: [.usesLineFragmentOrigin], attributes: bulletAttrs)
    }
}

func drawFooter(slideIndex: Int, slideCount: Int, accent: NSColor, width: Int, height: Int, progress: Double) {
    let y = CGFloat(54)
    NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 72, y: y, width: CGFloat(width - 144), height: 12), xRadius: 6, yRadius: 6).fill()
    accent.setFill()
    let completed = (CGFloat(slideIndex) + CGFloat(progress)) / CGFloat(slideCount)
    NSBezierPath(roundedRect: NSRect(x: 72, y: y, width: CGFloat(width - 144) * completed, height: 12), xRadius: 6, yRadius: 6).fill()

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.58, alpha: 1)
    ]
    NSString(string: "generated local demo - no screen recording permission required").draw(with: NSRect(x: 72, y: 24, width: CGFloat(width - 144), height: 20), options: [.usesLineFragmentOrigin], attributes: attrs)
}

func makePixelBuffer(from image: NSImage, pool: CVPixelBufferPool, width: Int, height: Int) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess, let pixelBuffer else {
        throw DemoRenderError.cannotCreatePixelBuffer
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw DemoRenderError.cannotCreatePixelBuffer
    }
    guard let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
        throw DemoRenderError.cannotCreateContext
    }
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw DemoRenderError.cannotCreateImage
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixelBuffer
}
