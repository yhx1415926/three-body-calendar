import SwiftUI

enum ObservatoryPalette {
    static let mint = Color(red: 0.40, green: 0.86, blue: 0.77)
    static let amber = Color(red: 0.98, green: 0.71, blue: 0.39)
    static let blue = Color(red: 0.47, green: 0.64, blue: 1.0)
    static let coral = Color(red: 0.96, green: 0.48, blue: 0.41)
    static let bodyColors: [Color] = [amber, blue, coral, mint]
    static let rgb: [SIMD3<Float>] = [SIMD3(1, 0.69, 0.30), SIMD3(0.48, 0.65, 1), SIMD3(1, 0.40, 0.31), SIMD3(0.33, 0.91, 0.75)]
}

enum WorkspacePage: String, CaseIterable, Identifiable {
    case observatory = "轨道观测"
    case calendar = "万年历"
    case analysis = "科学分析"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .observatory: "sparkles"
        case .calendar: "calendar"
        case .analysis: "waveform.path.ecg"
        }
    }
    var english: String {
        switch self {
        case .observatory: "ORBITAL OBSERVATORY"
        case .calendar: "THE LONG CALENDAR"
        case .analysis: "SCIENTIFIC DIAGNOSTICS"
        }
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2).foregroundStyle(.secondary)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var tint: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Panel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let subtitle { Text(subtitle).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)))
    }
}

struct NumberControl: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            TextField(title, value: $value, format: .number.precision(.significantDigits(1...9)))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .font(.system(size: 11, design: .monospaced)).frame(width: 93)
            if !unit.isEmpty { Text(unit).font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 30, alignment: .leading) }
        }
    }
}

extension Double {
    func display(_ digits: Int = 2) -> String {
        guard isFinite else { return "—" }
        return formatted(.number.precision(.fractionLength(digits)))
    }
    var scientific: String { isFinite ? String(format: "%.2e", self) : "—" }
}
