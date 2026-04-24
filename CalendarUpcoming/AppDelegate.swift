import AppKit
import SwiftUI
import Combine
import QuartzCore
import EventKit

// MARK: - Escape-aware hosting controller
//
// NSHostingController subclass that makes itself first responder when its view
// appears, then catches Escape via both `keyDown(with:)` and `cancelOperation(_:)`.
// Belt-and-suspenders: `keyDown` catches key events at the lowest level before
// SwiftUI's NSHostingView internals have a chance to intercept; `cancelOperation`
// is AppKit's canonical Escape/Cmd-. handler via the responder chain.
//
// Combined with `.transient` popover behaviour and `NSApp.activate()` on show,
// this gives reliable Escape dismissal for popovers hosted in an accessory-
// policy menu-bar app.
final class EscapeHostingController<Content: View>: NSHostingController<Content> {
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Defer a tick so the popover's window hierarchy is fully realised.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // Escape
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    let monitor = EventMonitor()
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    private var isPulsing = false
    let updateChecker = JorvikUpdateChecker(repoName: "CalendarUpcoming")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UserDefaults.standard.register(defaults: ["menuBarPillEnabled": true])

        if !UserDefaults.standard.bool(forKey: "didMigratePillColorV2") {
            UserDefaults.standard.removeObject(forKey: "menuBarPillColor")
            UserDefaults.standard.set(true, forKey: "didMigratePillColorV2")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.wantsLayer = true

        setIdleIcon()
        updateChecker.checkOnSchedule()

        monitor.$urgency
            .receive(on: DispatchQueue.main)
            .sink { [weak self] urgency in
                self?.updateState(urgency: urgency)
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func appearanceChanged() {
        updateState(urgency: monitor.urgency)
    }

    // MARK: - State update

    private func updateState(urgency: EventUrgency) {
        switch urgency {
        case .none:
            stopPulse()
            setIdleIcon()
        case .upcoming:
            setActiveIcon(color: .systemBlue)
            startPulse(color: .systemBlue)
        case .imminent:
            setActiveIcon(color: .systemOrange)
            startPulse(color: .systemOrange)
        case .now:
            setActiveIcon(color: .systemRed)
            startPulse(color: .systemRed)
        }
    }

    // MARK: - Icon

    private func setIdleIcon() {
        guard let button = statusItem.button else { return }
        button.image = JorvikMenuBarPill.icon(
            symbolName: "calendar",
            accessibilityDescription: "Calendar"
        )
        button.contentTintColor = nil
    }

    private func setActiveIcon(color: NSColor) {
        guard let button = statusItem.button else { return }
        let name = NSImage(systemSymbolName: "calendar.badge.exclamationmark",
                           accessibilityDescription: nil) != nil
            ? "calendar.badge.exclamationmark" : "calendar"
        button.image = JorvikMenuBarPill.icon(
            symbolName: name,
            tint: color,
            accessibilityDescription: "Upcoming events"
        )
        // When the pill is on, the image bakes in its own palette; template
        // tinting via contentTintColor would fight the composed draw.
        button.contentTintColor = JorvikMenuBarPill.isEnabled ? nil : color
    }

    // MARK: - Pulse / glow animation

    private func startPulse(color: NSColor) {
        if isPulsing { stopPulse() }
        guard let layer = statusItem.button?.layer else { return }
        isPulsing = true

        layer.shadowColor   = color.cgColor
        layer.shadowOpacity = 0.0
        layer.shadowRadius  = 8.0
        layer.shadowOffset  = .zero

        let opAnim = CABasicAnimation(keyPath: "opacity")
        opAnim.fromValue = 1.0; opAnim.toValue = 0.35
        opAnim.duration = 1.2; opAnim.autoreverses = true
        opAnim.repeatCount = .infinity
        opAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(opAnim, forKey: "calPulse")

        let glowAnim = CABasicAnimation(keyPath: "shadowOpacity")
        glowAnim.fromValue = 0.9; glowAnim.toValue = 0.1
        glowAnim.duration = 1.2; glowAnim.autoreverses = true
        glowAnim.repeatCount = .infinity
        glowAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(glowAnim, forKey: "calGlow")
    }

    private func stopPulse() {
        guard isPulsing, let layer = statusItem.button?.layer else { return }
        isPulsing = false
        layer.removeAnimation(forKey: "calPulse")
        layer.removeAnimation(forKey: "calGlow")
        layer.opacity = 1.0
        layer.shadowOpacity = 0.0
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        togglePopover(relativeTo: sender)
    }

    // MARK: - Popover

    private func togglePopover(relativeTo button: NSView) {
        if let existing = popover, existing.isShown {
            closePopover()
            return
        }

        let p = NSPopover()
        // `.transient` gives outside-click dismissal for free. Escape dismissal
        // is handled by `EscapeHostingController` via `cancelOperation(_:)` —
        // see comment on that class for why we don't rely on app-level
        // activation + .transient's native Escape handling.
        p.behavior = .transient
        p.animates = true
        let hc = EscapeHostingController(
            rootView: EventsPopoverView(monitor: monitor, onDismiss: { [weak self] in self?.closePopover() })
        )
        hc.onCancel = { [weak self] in self?.closePopover() }
        hc.view.wantsLayer = true
        hc.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        p.contentViewController = hc

        // Best-effort activation. On macOS 14+ use the cooperative form;
        // on older macOS fall back to the legacy (then-non-deprecated) API.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        p.contentViewController?.view.window?.makeKey()

        popover = p
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
    }

    // MARK: - Context menu (right-click)

    private func showContextMenu() {
        let menu = JorvikMenuBuilder.buildMenu(
            appName: "CalendarUpcoming",
            aboutAction: #selector(openAbout),
            settingsAction: #selector(openSettings),
            target: self
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openAbout() {
        closePopover()
        JorvikAboutView.showWindow(
            appName: "CalendarUpcoming",
            repoName: "CalendarUpcoming",
            productPage: "utilities/calendarupcoming"
        )
    }

    @objc private func openSettings() {
        closePopover()
        JorvikSettingsView.showWindow(
            appName: "CalendarUpcoming",
            updateChecker: updateChecker
        ) { [weak self] in
            if let monitor = self?.monitor {
                Section("Alerts") {
                    Picker("Alert when events start within", selection: Binding(
                        get: { monitor.lookAheadMinutes },
                        set: { monitor.lookAheadMinutes = $0 }
                    )) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                    }
                }

                Section("Permissions") {
                    HStack {
                        Text("Calendar Access")
                        Spacer()
                        let status = EKEventStore.authorizationStatus(for: .event)
                        // Granted on macOS 14+ means `.fullAccess`; on macOS 13
                        // means `.authorized` (deprecated in the 14 SDK — we
                        // compare by rawValue to avoid the deprecation warning).
                        // IIFE so the #available branching reads as a single
                        // `let` binding to SwiftUI's ViewBuilder.
                        let granted: Bool = {
                            if #available(macOS 14.0, *) {
                                return status == .fullAccess
                            }
                            return status.rawValue == 3   // .authorized
                        }()
                        if granted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Button("Grant Access") {
                                EKEventStore().requestFullAccessToEvents { _, _ in }
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            MenuBarPillSettings {
                guard let self else { return }
                self.updateState(urgency: self.monitor.urgency)
            }
        }
    }
}
