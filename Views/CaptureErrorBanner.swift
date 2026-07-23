import SwiftUI

struct CaptureErrorBanner: View {
  let error: AppErrorPresentation
  let dismiss: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text(error.title).font(.subheadline.weight(.semibold))
        Text(error.message).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Button(action: dismiss) { Image(systemName: "xmark") }
        .buttonStyle(.borderless)
        .help("Dismiss error")
    }
    .padding(10)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
