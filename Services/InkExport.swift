import AppKit
import Foundation

enum InkExportFormat: String, CaseIterable, Identifiable, Sendable {
  case png
  case svg
  case pdf

  var id: String { rawValue }
  var title: String { rawValue.uppercased() }
  var fileExtension: String { rawValue }
}

enum InkExportError: LocalizedError, Equatable {
  case invalidInk
  case encodingFailed
  case unwritableFile

  var errorDescription: String? {
    switch self {
    case .invalidInk: "Draw a stroke before exporting ink."
    case .encodingFailed: "WriteIt could not prepare the ink export."
    case .unwritableFile: "WriteIt could not save the ink export."
    }
  }
}

enum InkExportCodec {
  static func encode(
    strokes: [InkStroke],
    canvasSize: CGSize,
    style: InkStyle,
    format: InkExportFormat
  ) throws -> Data {
    let plan = try InkExportPlan(strokes: strokes, canvasSize: canvasSize, style: style)
    return switch format {
    case .png: try png(plan)
    case .svg: svg(plan)
    case .pdf: try pdf(plan)
    }
  }

  private static func png(_ plan: InkExportPlan) throws -> Data {
    let pixels = InkRasterLayout.pixelSize(for: plan.canvasSize)
    guard let image = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels.width,
      pixelsHigh: pixels.height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { throw InkExportError.encodingFailed }
    image.size = plan.outputSize
    guard let context = NSGraphicsContext(bitmapImageRep: image) else {
      throw InkExportError.encodingFailed
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.compositingOperation = .copy
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: plan.outputSize)).fill()
    context.compositingOperation = .sourceOver
    draw(plan, in: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = image.representation(using: .png, properties: [:]) else {
      throw InkExportError.encodingFailed
    }
    return data
  }

  private static func svg(_ plan: InkExportPlan) -> Data {
    var lines = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(number(plan.outputSize.width))\" height=\"\(number(plan.outputSize.height))\" viewBox=\"0 0 \(number(plan.outputSize.width)) \(number(plan.outputSize.height))\">",
    ]
    for (previous, point) in plan.segments {
      let start = plan.renderPoint(previous)
      let end = plan.renderPoint(point)
      let width = plan.lineWidth(for: previous, point)
      lines.append(
        "  <path d=\"M \(number(start.x)) \(number(start.y)) L \(number(end.x)) \(number(end.y))\" fill=\"none\" stroke=\"#000000\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"\(number(width))\"/>"
      )
    }
    lines.append("</svg>")
    return Data(lines.joined(separator: "\n").utf8)
  }

  private static func pdf(_ plan: InkExportPlan) throws -> Data {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data) else { throw InkExportError.encodingFailed }
    var mediaBox = CGRect(origin: .zero, size: plan.outputSize)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
      throw InkExportError.encodingFailed
    }
    context.beginPDFPage(nil)
    draw(plan, in: context)
    context.endPDFPage()
    context.closePDF()
    return data as Data
  }

  private static func draw(_ plan: InkExportPlan, in context: CGContext) {
    context.setStrokeColor(NSColor.black.cgColor)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for (previous, point) in plan.segments {
      context.setLineWidth(plan.lineWidth(for: previous, point))
      context.move(to: plan.renderPoint(previous))
      context.addLine(to: plan.renderPoint(point))
      context.strokePath()
    }
  }

  private static func number(_ value: CGFloat) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
  }
}

enum InkExportFileStore {
  static func write(_ data: Data, to url: URL) throws {
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw InkExportError.unwritableFile
    }
  }
}

private struct InkExportPlan {
  let canvasSize: CGSize
  let outputSize: CGSize
  let style: InkStyle
  let segments: [(InkPoint, InkPoint)]
  private let scale: CGFloat

  init(strokes: [InkStroke], canvasSize: CGSize, style: InkStyle) throws {
    guard canvasSize.width.isFinite, canvasSize.height.isFinite,
      canvasSize.width > 0, canvasSize.height > 0,
      strokes.flatMap(\.points).allSatisfy({ point in
        point.x.isFinite && point.y.isFinite && point.pressure.isFinite
      })
    else { throw InkExportError.invalidInk }
    let segments = strokes.flatMap { stroke in
      zip(stroke.points, stroke.points.dropFirst()).map { ($0, $1) }
    }
    guard segments.isEmpty == false else { throw InkExportError.invalidInk }
    let outputSize = InkRasterLayout.outputSize(for: canvasSize)
    guard outputSize.width.isFinite, outputSize.height.isFinite,
      outputSize.width > 0, outputSize.height > 0
    else { throw InkExportError.encodingFailed }
    self.canvasSize = canvasSize
    self.outputSize = outputSize
    self.style = style
    self.segments = segments
    scale = min(outputSize.width / canvasSize.width, outputSize.height / canvasSize.height)
  }

  func renderPoint(_ point: InkPoint) -> CGPoint {
    CanvasCoordinateTransformer.renderPoint(point, canvasSize: canvasSize, outputSize: outputSize)
  }

  func lineWidth(for previous: InkPoint, _ point: InkPoint) -> CGFloat {
    style.lineWidth(for: (previous.pressure + point.pressure) / 2, scale: scale)
  }
}
