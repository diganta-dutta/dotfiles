// AppDelegate.swift — menu-bar presence (NSStatusItem) plus a real, resizable
// window hosting the SwiftUI ContentView. Built as an accessory (agent) app, the
// same LSUIElement style Claude Launcher uses, so there is no dock icon — the
// app lives in the menu bar and the window can stay open while you watch reviews.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        makeWindow()
        showWindow()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist",
                                           accessibilityDescription: "Review Queue")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Review Queue", action: #selector(showWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Review Queue", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
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
