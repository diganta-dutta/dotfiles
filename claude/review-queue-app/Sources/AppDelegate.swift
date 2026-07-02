// AppDelegate.swift — menu-bar presence (NSStatusItem) plus a real, resizable
// window hosting the SwiftUI ContentView. Built as an accessory (agent) app, the
// same LSUIElement style Claude Launcher uses, so there is no dock icon — the
// app lives in the menu bar and the window can stay open while you watch reviews.

import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var autoItem: NSMenuItem!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        makeWindow()
        showWindow()

        // Reflect completed-review count / run state / rate-limit pause in the menu-bar item.
        // objectWillChange fires *before* the mutation, so read on the next runloop.
        model.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.updateStatusItem() } }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist",
                                           accessibilityDescription: "Review Queue")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Review Queue", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        autoItem = NSMenuItem(title: "Auto-review", action: #selector(toggleAuto), keyEquivalent: "")
        menu.addItem(autoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Review Queue", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    /// Badge = completed reviews awaiting dismissal; glyph reflects paused / running / idle.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let count = model.completed.count
        let symbol: String
        if model.rateLimitedUntil != nil {
            symbol = "clock.badge.exclamationmark"
        } else if model.phase == .running || model.phase == .loading {
            symbol = "arrow.triangle.2.circlepath"
        } else {
            symbol = "checklist"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Review Queue")
        button.title = count > 0 ? " \(count)" : ""
        button.imagePosition = count > 0 ? .imageLeading : .imageOnly
        autoItem?.state = model.autoMode ? .on : .off
    }

    @objc private func toggleAuto() {
        model.autoMode.toggle()
        updateStatusItem()
    }

    private func makeWindow() {
        let host = NSHostingController(rootView: ContentView().environmentObject(model))
        window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "Review Queue"
        window.setContentSize(NSSize(width: 980, height: 660))
        window.isReleasedWhenClosed = false   // reopen from the menu after closing
        window.center()
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func refresh() {
        model.refresh()
        showWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
