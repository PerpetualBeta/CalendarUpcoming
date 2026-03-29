import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: EventMonitor

    private let options = [5, 10, 15, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Alert me when events start within:")
                    .font(.subheadline)

                Picker("Look-ahead", selection: Binding(
                    get: { monitor.lookAheadMinutes },
                    set: { monitor.lookAheadMinutes = $0 }
                )) {
                    ForEach(options, id: \.self) { minutes in
                        Text(label(for: minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            .padding(16)

            Divider()

            HStack {
                Spacer()
                Text("v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
    }

    private func label(for minutes: Int) -> String {
        switch minutes {
        case 5:  return "5 minutes"
        case 10: return "10 minutes"
        case 15: return "15 minutes"
        case 30: return "30 minutes"
        case 60: return "1 hour"
        default: return "\(minutes) minutes"
        }
    }
}
