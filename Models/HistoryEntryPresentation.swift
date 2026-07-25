import Foundation

struct HistoryMetadataItem: Identifiable, Equatable {
  let title: String
  let value: String
  let symbol: String

  var id: String { title }
}

struct HistoryEntryPresentation {
  let entry: HistoryEntry

  var hasRetainedInk: Bool {
    entry.strokes?.contains(where: { $0.points.count > 1 }) == true
  }

  var privacyDetail: String {
    hasRetainedInk
      ? "Raw ink is retained locally for retry."
      : "Text-only entry; raw ink was not retained."
  }

  var retryUnavailableDetail: String? {
    hasRetainedInk ? nil : "Retry unavailable because this entry has no retained ink."
  }

  var metadata: [HistoryMetadataItem] {
    var items = [HistoryMetadataItem(title: "Source", value: entry.source, symbol: "text.viewfinder")]
    if let model = entry.model {
      items.append(HistoryMetadataItem(title: "Model", value: model, symbol: "cpu"))
    }
    if let language = entry.language {
      items.append(HistoryMetadataItem(title: "Language", value: language.displayName, symbol: "globe"))
    }
    if let delivery = entry.delivery {
      let verification = delivery.verification.map { " · \($0)" } ?? ""
      items.append(HistoryMetadataItem(
        title: "Delivery", value: delivery.method + verification, symbol: "arrow.up.right"))
    }
    if let confidence = entry.confidence {
      items.append(HistoryMetadataItem(
        title: "Confidence", value: "\(Int((confidence * 100).rounded()))%", symbol: "chart.bar"))
    }
    if let duration = entry.recognitionDuration {
      items.append(HistoryMetadataItem(
        title: "Recognition", value: String(format: "%.1fs", duration), symbol: "timer"))
    }
    return items
  }
}

struct HistoryPrivacyPresentation: Equatable {
  let mode: HistoryMode
  let autoDelete: Bool
  let retentionDays: Int

  var title: String {
    switch mode {
    case .off: "History is off"
    case .textOnly: "Text-only history"
    case .full: "Full history"
    }
  }

  var detail: String {
    let retained = switch mode {
    case .off: "New captures are not retained."
    case .textOnly: "New entries retain recognized text without raw ink."
    case .full: "New entries retain recognized text and raw ink locally."
    }
    guard autoDelete else { return retained }
    return retained + " Auto-delete runs after \(retentionDays) day\(retentionDays == 1 ? "" : "s")."
  }
}
