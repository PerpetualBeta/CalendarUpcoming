import SwiftUI
import EventKit

struct EventsPopoverView: View {
    @ObservedObject var monitor: EventMonitor
    /// Optional dismissal hook, retained for any future in-popover close button.
    /// Escape-key dismissal is handled at the AppKit layer in AppDelegate via
    /// a local keyDown event monitor — see conventions-accessory-popover-focus
    /// for why SwiftUI's `.onExitCommand` isn't a reliable fit here.
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
    }

    private var eventList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(monitor.upcomingEvents, id: \.eventIdentifier) { event in
                    EventRowView(event: event, onDismiss: { monitor.dismiss(event) })
                    Divider().padding(.leading, 16)
                }
            }
        }
        .frame(maxHeight: 400)
    }

    /// Nothing coming up, so the space goes to the month instead of to a notice
    /// saying there is nothing to show.
    private var emptyView: some View {
        MonthCalendarView()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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

// MARK: - Month Calendar

/// The current month at a glance, with today marked — shown in place of the event
/// list when there is nothing upcoming.
///
/// Every part of the layout is read from `Calendar.current`: the week starts on
/// whichever day the user's locale starts on, and the weekday initials are theirs.
/// Nothing here assumes a Monday, or English.
struct MonthCalendarView: View {

    /// The day the grid is built around. A parameter rather than a `Date()` inside
    /// the body so the view can be rendered for any month without waiting for one.
    var referenceDate: Date = Date()

    private enum Metrics {
        /// Side of a day cell. Square, so the mark drawn behind today is a circle
        /// rather than an ellipse, and wide enough for two digits at `dayFont`.
        static let dayCell: CGFloat = 26
        static let dayFont: CGFloat = 12
        static let rowSpacing: CGFloat = 3
        static let titleSpacing: CGFloat = 10
    }

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? .current
        // Template rather than a literal pattern: the locale decides whether the
        // year leads or trails, and how the month is spelled.
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: referenceDate)
    }

    /// Weekday initials rotated so the first is the locale's first day of the week.
    /// `veryShortWeekdaySymbols` is always Sunday-first whatever the locale, so the
    /// rotation is what makes a Monday-start week come out right.
    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        guard symbols.indices.contains(offset) else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var firstOfMonth: Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate))
    }

    /// Blank cells before the 1st, so it falls under the right weekday.
    private var leadingBlanks: Int {
        guard let firstOfMonth else { return 0 }
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return (weekday - calendar.firstWeekday + weekdayInitials.count) % weekdayInitials.count
    }

    /// The month's days. Taken from the calendar's own range so February, leap
    /// years and every other irregularity are its problem rather than ours.
    private var days: [Int] {
        guard let range = calendar.range(of: .day, in: .month, for: referenceDate) else { return [] }
        return Array(range)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: weekdayInitials.count)
    }

    /// One cell of the grid.
    ///
    /// The grid is filled from a single sequence of these rather than from three
    /// `ForEach`es in a row, because three would each have counted from zero: the
    /// weekday initials 0...6, the leading blanks 0...4 and the days 1...31 all
    /// identified by plain integers in one container. SwiftUI resolves that by
    /// keeping the first view for a given identity and dropping the rest, so the
    /// 1st to the 6th of the month silently vanished behind the weekday headings
    /// while the 7th onward — whose numbers collided with nothing — drew fine.
    private enum Cell: Identifiable {
        case weekday(index: Int, symbol: String)
        case blank(index: Int)
        case day(Int)

        var id: String {
            switch self {
            case .weekday(let index, _): return "weekday-\(index)"
            case .blank(let index):      return "blank-\(index)"
            case .day(let day):          return "day-\(day)"
            }
        }
    }

    private var cells: [Cell] {
        weekdayInitials.enumerated().map { Cell.weekday(index: $0.offset, symbol: $0.element) }
            + (0..<leadingBlanks).map { Cell.blank(index: $0) }
            + days.map { Cell.day($0) }
    }

    var body: some View {
        VStack(spacing: Metrics.titleSpacing) {
            Text(monthTitle)
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: columns, spacing: Metrics.rowSpacing) {
                ForEach(cells) { cell in
                    switch cell {
                    case .weekday(_, let symbol):
                        Text(symbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    case .blank:
                        Color.clear.frame(height: Metrics.dayCell)
                    case .day(let day):
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let isToday = date(for: day).map(calendar.isDateInToday) ?? false
        return Text("\(day)")
            .font(.system(size: Metrics.dayFont))
            .monospacedDigit()
            .foregroundStyle(isToday ? Color.white : Color.primary)
            .frame(width: Metrics.dayCell, height: Metrics.dayCell)
            .background { if isToday { Circle().fill(Color.accentColor) } }
            .frame(maxWidth: .infinity)
    }

    private func date(for day: Int) -> Date? {
        guard let firstOfMonth else { return nil }
        return calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
    }
}

// MARK: - Event Row

struct EventRowView: View {
    let event: EKEvent
    var onDismiss: () -> Void

    @State private var hovering = false

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

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(hovering ? Color.secondary : Color.secondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help("Dismiss — hide this event until it ends")
            .padding(.top, 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
