import SwiftUI

@main
struct CalendarUpcomingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu-bar only app — no windows. Settings scene required for @main to compile.
        Settings { EmptyView() }
    }
}
