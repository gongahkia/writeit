import SwiftUI

struct InputTuningPanel: View {
  @ObservedObject var preferences: Preferences

  var body: some View {
    VStack(alignment: .leading, spacing: WriteItTheme.compactSpacing) {
      VStack(alignment: .leading, spacing: 3) {
        Label("Input tuning", systemImage: "pencil.and.scribble")
          .font(.headline)
        Text("Adjust the captured handwriting before recognition. Changes stay on this Mac.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Divider()
      VStack(alignment: .leading, spacing: 4) {
        LabeledContent("Stroke width") {
          Text(preferences.strokeWidth, format: .number.precision(.fractionLength(1)))
            .foregroundStyle(.secondary)
        }
        Slider(value: $preferences.strokeWidth, in: 1...12, step: 0.5) {
          Text("Stroke width")
        } minimumValueLabel: {
          Text("Fine")
        } maximumValueLabel: {
          Text("Bold")
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        LabeledContent("Pressure response") {
          Text(preferences.pressureSensitivity, format: .percent.precision(.fractionLength(0)))
            .foregroundStyle(.secondary)
        }
        Slider(value: $preferences.pressureSensitivity, in: 0...1, step: 0.05) {
          Text("Pressure response")
        } minimumValueLabel: {
          Text("Fixed")
        } maximumValueLabel: {
          Text("Strong")
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        LabeledContent("Stroke smoothing") {
          Text(preferences.strokeSmoothing, format: .percent.precision(.fractionLength(0)))
            .foregroundStyle(.secondary)
        }
        Slider(value: $preferences.strokeSmoothing, in: 0...1, step: 0.05) {
          Text("Stroke smoothing")
        } minimumValueLabel: {
          Text("Raw")
        } maximumValueLabel: {
          Text("Smooth")
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("Live preview").font(.subheadline)
        InkStylePreview(style: preferences.inkStyle)
      }
    }
    .padding(WriteItTheme.compactSpacing)
    .background(
      WriteItTheme.cardFill,
      in: RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius).stroke(WriteItTheme.cardStroke)
    )
  }
}
