import SwiftUI

struct CompactInputPanel: View {
    let source: CaptureSource
    let status: CaptureStatus
    let level: AudioLevel
    let history: [Float]
    let toggleAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: source.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(statusColor, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                    Text(source.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            WaveformView(samples: history, tint: statusColor)
                .frame(height: 74)

            HStack(spacing: 10) {
                LevelMeter(title: "RMS", value: level.rms)
                LevelMeter(title: "Peak", value: level.peak)
            }

            HStack(spacing: 8) {
                Button(action: toggleAction) {
                    Image(systemName: isActive ? "stop.fill" : "play.fill")
                }
                .help(isActive ? "Stop" : "Start")

                Button(action: settingsAction) {
                    Image(systemName: "gear")
                }
                .help("Permission")

                Spacer()

                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
        }
        .panelStyle()
    }

    private var isActive: Bool {
        status == .starting || status == .running
    }

    private var statusColor: Color {
        switch status {
        case .idle:
            return .gray
        case .starting:
            return .orange
        case .running:
            return .green
        case .failed:
            return .red
        }
    }
}

struct WaveformView: View {
    let samples: [Float]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let midY = size.height / 2
                let count = max(samples.count, 1)
                let step = size.width / CGFloat(count)

                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: midY))
                baseline.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(baseline, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)

                var path = Path()
                for index in samples.indices {
                    let x = CGFloat(index) * step
                    let normalized = CGFloat(min(max(samples[index] * 5.0, 0), 1))
                    let height = max(2, normalized * size.height * 0.88)
                    let rect = CGRect(
                        x: x,
                        y: midY - height / 2,
                        width: max(2, step * 0.62),
                        height: height
                    )
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 2, height: 2))
                }

                context.fill(path, with: .color(tint.opacity(0.82)))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

struct LevelMeter: View {
    let title: String
    let value: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(min(max(value * 4.0, 0), 1)))
                .progressViewStyle(.linear)
        }
    }
}
