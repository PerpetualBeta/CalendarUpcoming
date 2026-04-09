import SwiftUI
import EventKit

struct EventsPopoverView: View {
    @ObservedObject var monitor: EventMonitor
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Upcoming Events")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if monitor.needsFullAccess {
                writeOnlyView
            } else if !monitor.accessGranted {
                accessDeniedView
            } else if monitor.upcomingEvents.isEmpty {
                emptyView
            } else {
                eventList
            }
        }
        .frame(width: 320)
        .background(Color(.windowBackgroundColor))
        .onExitCommand { onDismiss?() }
    }

    private var eventList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(monitor.upcomingEvents, id: \.eventIdentifier) { event in
                    EventRowView(event: event)
                    Divider().padding(.leading, 16)
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No upcoming events")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var writeOnlyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.rotation")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text("Full calendar access needed")
                .font(.subheadline.weight(.medium))
            Text("CalendarUpcoming has write-only access and can't read your events. Change it to Full Access in System Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Button("Open System Settings → Calendars") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
                )
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var accessDeniedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Calendar access denied")
                .font(.subheadline)
            Text("Grant access in System Settings → Privacy & Security → Calendars")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Open System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
                )
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

// MARK: - Event Row

struct EventRowView: View {
    let event: EKEvent

    private var minutesUntil: Int {
        max(0, Int(event.startDate.timeIntervalSinceNow / 60))
    }

    private var timeUntilText: String {
        let m = minutesUntil
        if m == 0 { return "Now" }
        if m == 1 { return "in 1 min" }
        return "in \(m) min"
    }

    private var startTimeText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: event.startDate)
    }

    private var calendarColor: Color {
        Color(event.calendar.color)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(calendarColor)
                .frame(width: 4, height: 40)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(timeUntilText)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .fontWeight(.semibold)

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(startTimeText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(event.calendar.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
