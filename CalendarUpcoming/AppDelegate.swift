import AppKit
import SwiftUI
import Combine
import QuartzCore
import EventKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    let monitor = EventMonitor()
    private var popover: NSPopover?
    private var clickOutsideMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var isPulsing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.wantsLayer = true

        setIdleIcon()

        monitor.$urgency
            .receive(on: DispatchQueue.main)
            .sink { [weak self] urgency in
                self?.updateState(urgency: urgency)
            }
            .store(in: &cancellables)
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
        if let img = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar") {
            let sized = img.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            ) ?? img
            sized.isTemplate = true
            button.image = sized
        }
        button.contentTintColor = nil
    }

    private func setActiveIcon(color: NSColor) {
        guard let button = statusItem.button else { return }
        let name = NSImage(systemSymbolName: "calendar.badge.exclamationmark",
                           accessibilityDescription: nil) != nil
            ? "calendar.badge.exclamationmark" : "calendar"
        if let img = NSImage(systemSymbolName: name,
                             accessibilityDescription: "Upcoming events") {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color, color]))
            let sized = img.withSymbolConfiguration(config) ?? img
            sized.isTemplate = false
            button.image = sized
        }
        button.contentTintColor = color
    }

    // MARK: - Pulse / glow animation

    private func startPulse(color: NSColor) {
        // If already pulsing with a different colour, stop first so the new colour applies.
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
        p.behavior = .applicationDefined
        p.animates = true
        let hc = NSHostingController(
            rootView: EventsPopoverView(monitor: monitor, onDismiss: { [weak self] in self?.closePopover() })
        )
        hc.view.wantsLayer = true
        hc.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        p.contentViewController = hc
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Context menu (right-click)

    private func showContextMenu() {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: "About CalendarUpcoming",
                                   action: #selector(openAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit CalendarUpcoming",
                                action: #selector(NSApp.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openAbout() {
        closePopover()
        guard let button = statusItem.button else { return }
        let p = NSPopover()
        p.behavior = .applicationDefined
        p.animates = true
        let hc = NSHostingController(
            rootView: AboutView(onDismiss: { [weak self] in self?.closePopover() })
        )
        hc.view.wantsLayer = true
        hc.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        p.contentViewController = hc
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    @objc private func openSettings() {
        closePopover()
        guard let button = statusItem.button else { return }
        let p = NSPopover()
        p.behavior = .applicationDefined
        p.animates = true
        let hc = NSHostingController(rootView: SettingsView(monitor: monitor))
        hc.view.wantsLayer = true
        hc.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        p.contentViewController = hc
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }
}
