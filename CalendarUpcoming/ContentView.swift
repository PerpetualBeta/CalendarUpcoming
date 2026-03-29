import SwiftUI
import EventKit

struct ContentView: View {
    @EnvironmentObject var monitor: EventMonitor

    var body: some View {
        VStack(spacing: 0) {
            if !monitor.accessGranted {
                accessDeniedView
            } else {
                if !monitor.upcomingEvents.isEmpty {
                    ActiveBanner(
                        count: monitor.upcomingEvents.count,
                        minutes: monitor.lookAheadMinutes
                    )
                }

                eventListOrEmpty

                footer
            }
        }
        .frame(width: 400)
        .frame(minHeight: 300)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Event list / empty state

    private var eventListOrEmpty: some View {
        Group {
            if monitor.upcomingEvents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.upcomingEvents, id: \.eventIdentifier) { event in
                            EventRowView(event: event)
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .frame(maxHeight: 480)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 44))
                .foregroundColor(Color(.tertiaryLabelColor))
            Text("No upcoming events")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Looking \(monitor.lookAheadMinutes) \(monitor.lookAheadMinutes == 60 ? "hour" : "minutes") ahead")
                .font(.caption)
                .foregroundColor(Color(.quaternaryLabelColor))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - Footer bar

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("Look ahead:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { monitor.lookAheadMinutes },
                    set: { monitor.lookAheadMinutes = $0 }
                )) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                }
                .pickerStyle(.menu)
                .frame(width: 95)
                .labelsHidden()

                Spacer()

                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Refresh now")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Access denied

    private var accessDeniedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Calendar access denied")
                .font(.headline)
            Text("Grant access in System Settings → Privacy & Security → Calendars")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
                )
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(44)
    }
}

// MARK: - Active banner with pulsing dot

struct ActiveBanner: View {
    let count: Int
    let minutes: Int
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(pulsing ? 0.28 : 0.0))
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
            }
            .onAppear { pulsing = true }
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: pulsing
            )

            Text(count == 1
                 ? "1 event in the next \(minuteLabel)"
                 : "\(count) events in the next \(minuteLabel)")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.blue)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.blue.opacity(0.08))
    }

    private var minuteLabel: String {
        minutes == 60 ? "hour" : "\(minutes) minutes"
    }
}
