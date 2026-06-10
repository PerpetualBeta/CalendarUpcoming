import EventKit
import Combine
import Foundation

enum EventUrgency: Int, Comparable {
    case none     = 0   // no events
    case upcoming = 1   // events within look-ahead window
    case imminent = 2   // at least one event within 5 minutes
    case now      = 3   // at least one event that has already started

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

final class EventMonitor: ObservableObject {

    @Published private(set) var upcomingEvents: [EKEvent] = []
    @Published private(set) var urgency: EventUrgency = .none
    @Published private(set) var accessGranted: Bool = false
    @Published private(set) var needsFullAccess: Bool = false
    @Published private(set) var debugInfo: String = "Not started"

    private let store = EKEventStore()
    private var pollTimer: Timer?

    static let lookAheadKey = "lookAheadMinutes"
    static let lookAheadDefault = 15

    static let dismissedKey = "dismissedEventKeys"

    /// Events the user has manually dismissed, keyed by a per-occurrence
    /// identifier mapped to the event's *end* date. EventKit's predicate
    /// matches any event overlapping the look-ahead window, so a long meeting
    /// stays "Now" for its whole scheduled duration even after you've left —
    /// dismissing hides it (and clears the alert) until it ends. The end date
    /// lets us prune the entry once the event is genuinely over, so the set
    /// can't grow without bound.
    private var dismissed: [String: Date] = [:]

    var lookAheadMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Self.lookAheadKey)
            return v > 0 ? v : Self.lookAheadDefault
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.lookAheadKey)
            refresh()
        }
    }

    init() {
        loadDismissed()
        requestAccess()
    }

    // MARK: - Dismissal

    /// Hide a single event occurrence from the list and the alert. Persists so
    /// the dismissal survives a relaunch mid-meeting.
    func dismiss(_ event: EKEvent) {
        dismissed[dismissalKey(for: event)] = event.endDate
        persistDismissed()
        refresh()
    }

    /// Per-occurrence key. Recurring events share one `eventIdentifier` across
    /// all occurrences, so the start date is folded in to dismiss only the one
    /// instance the user is looking at.
    private func dismissalKey(for event: EKEvent) -> String {
        let id = event.eventIdentifier ?? event.calendarItemIdentifier
        return "\(id)|\(event.startDate.timeIntervalSinceReferenceDate)"
    }

    private func loadDismissed() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.dismissedKey) as? [String: Double] ?? [:]
        dismissed = raw.mapValues { Date(timeIntervalSinceReferenceDate: $0) }
    }

    private func persistDismissed() {
        UserDefaults.standard.set(dismissed.mapValues { $0.timeIntervalSinceReferenceDate }, forKey: Self.dismissedKey)
    }

    deinit {
        pollTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Access

    private func requestAccess() {
        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .fullAccess:
                DispatchQueue.main.async { self.accessGranted = true; self.startPolling() }
            case .writeOnly:
                // Has write-only — can't read. Must be upgraded manually in System Settings.
                DispatchQueue.main.async { self.needsFullAccess = true }
            case .notDetermined:
                store.requestFullAccessToEvents { [weak self] _, _ in
                    DispatchQueue.main.async { self?.checkStatusAfterRequest() }
                }
            default:
                break // denied / restricted — nothing we can do
            }
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            if status == .authorized {
                DispatchQueue.main.async { self.accessGranted = true; self.startPolling() }
                return
            }
            store.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.accessGranted = granted
                    if granted { self?.startPolling() }
                }
            }
        }
    }

    // Called after the requestFullAccessToEvents dialog is dismissed
    @available(macOS 14.0, *)
    private func checkStatusAfterRequest() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            accessGranted = true
            startPolling()
        case .writeOnly:
            needsFullAccess = true
        default:
            break
        }
    }

    private func authStatusString(_ status: EKAuthorizationStatus) -> String {
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess:    return "fullAccess"
            case .writeOnly:     return "writeOnly"
            case .denied:        return "denied"
            case .restricted:    return "restricted"
            case .notDetermined: return "notDetermined"
            @unknown default:    return "unknown(\(status.rawValue))"
            }
        }
        // macOS 13 branch: the SDK compiles against macOS 14 so `.fullAccess`
        // and `.writeOnly` are known enum cases and `@unknown default` won't
        // cover them. Switch on rawValue instead — avoids both the deprecation
        // warning on `.authorized` and the compile-time exhaustiveness warning.
        switch status.rawValue {
        case 0: return "notDetermined"
        case 1: return "restricted"
        case 2: return "denied"
        case 3: return "authorized"
        default: return "unknown(\(status.rawValue))"
        }
    }

    // MARK: - Polling

    private func startPolling() {
        refresh()
        scheduleNextMinuteTick()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: store
        )
    }

    private func scheduleNextMinuteTick() {
        let now = Date()
        let calendar = Calendar.current
        let seconds = calendar.component(.second, from: now)
        let delay = TimeInterval(60 - seconds)
        pollTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNextMinuteTick()
        }
    }

    @objc private func storeChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Fetch

    func refresh() {
        guard accessGranted else {
            debugInfo = "refresh() skipped — accessGranted=false"
            return
        }

        let calCount = store.calendars(for: .event).count
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(lookAheadMinutes * 60))

        // Forget dismissals whose event has ended — keeps the set bounded.
        let prunedCount = dismissed.count
        dismissed = dismissed.filter { $0.value > now }
        if dismissed.count != prunedCount { persistDismissed() }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let raw = store.events(matching: predicate)

        let allDayCount  = raw.filter { $0.isAllDay }.count
        let declinedCount = raw.filter { event in
            guard let attendees = event.attendees else { return false }
            return attendees.first { $0.isCurrentUser }?.participantStatus == .declined
        }.count

        let filtered = raw.filter { event in
            guard !event.isAllDay else { return false }
            if let attendees = event.attendees {
                let selfAttendee = attendees.first { $0.isCurrentUser }
                if selfAttendee?.participantStatus == .declined { return false }
            }
            if dismissed[dismissalKey(for: event)] != nil { return false }
            return true
        }
        .sorted { $0.startDate < $1.startDate }

        debugInfo = "cals=\(calCount) raw=\(raw.count) allDay=\(allDayCount) declined=\(declinedCount) dismissed=\(dismissed.count) shown=\(filtered.count)"

        upcomingEvents = filtered

        let fiveMinsFromNow = now.addingTimeInterval(5 * 60)
        var highest = EventUrgency.none
        for event in filtered {
            let u: EventUrgency = event.startDate <= now      ? .now
                                : event.startDate <= fiveMinsFromNow ? .imminent
                                : .upcoming
            if u > highest { highest = u }
            if highest == .now { break }
        }
        urgency = highest
    }
}
