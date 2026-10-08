import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case today = "Today", stats = "Stats", settings = "Settings"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "clock.arrow.circlepath"
        case .stats: "chart.bar.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct PopoverView: View {
    let model: AppModel
    @State private var tab: Tab = .today

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .today: TodayView(model: model)
                case .stats: StatsView(model: model)
                case .settings: SettingsView()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            HStack {
                ForEach(Tab.allCases) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.icon).font(.title3)
                            Text(t.rawValue).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(tab == t ? .primary : .tertiary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
        }
        .frame(width: 340, height: 500)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
