// StatusBarController.swift
// ActivityMonitor
//
// Owns the NSStatusItem that lives in the system menu bar and the NSMenu
// that drops down when the user clicks it.
//
// Responsibilities:
//  • Create and configure the status item and its button.
//  • Build the dropdown menu with live detail rows.
//  • Subscribe to MetricsManager and refresh all UI on each tick.
//  • Handle Pause / Resume, Launch at Login, and Quit actions.

import AppKit
import ServiceManagement

final class StatusBarController: NSObject {

    // MARK: - Private state

    private let statusItem: NSStatusItem
    private let manager:    MetricsManager

    // Menu items that receive live metric text each tick.
    private let cpuItem       = NSMenuItem(title: "CPU: —",          action: nil,                    keyEquivalent: "")
    private let ramItem       = NSMenuItem(title: "RAM: — / —",      action: nil,                    keyEquivalent: "")
    private let pauseItem     = NSMenuItem(title: "Pause updates",    action: #selector(handlePause), keyEquivalent: "p")
    private let loginItem     = NSMenuItem(title: "Launch at Login",  action: #selector(handleLogin), keyEquivalent: "l")

    // MARK: - Init

    init(manager: MetricsManager) {
        self.manager = manager

        // Variable-length item so the text can be as wide as it needs to be.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        configureButton()
        buildMenu()
        subscribeToMetrics()
        refreshLoginItemState()

        manager.start()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // Monospaced digits prevent the bar item from jumping width on each
        // update when CPU % or RAM GB changes digit count.
        button.font  = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        button.title = "Loading…"
    }

    private func buildMenu() {
        let menu = NSMenu()

        // --- Live metric rows (read-only labels) ---
        cpuItem.isEnabled = false
        ramItem.isEnabled = false
        menu.addItem(cpuItem)
        menu.addItem(ramItem)
        menu.addItem(.separator())

        // --- Pause / Resume ---
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        // --- Launch at Login ---
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        // --- Quit ---
        let quitItem = NSMenuItem(
            title:          "Quit Activity Monitor",
            action:         #selector(NSApplication.terminate(_:)),
            keyEquivalent:  "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Metrics subscription

    private func subscribeToMetrics() {
        manager.onUpdate = { [weak self] metrics in
            // MetricsManager guarantees delivery on the main thread.
            self?.apply(metrics)
        }
    }

    private func apply(_ metrics: SystemMetrics) {
        statusItem.button?.title = metrics.statusBarTitle
        cpuItem.title            = metrics.cpuDetail
        ramItem.title            = metrics.memoryDetail
    }

    // MARK: - Actions

    @objc private func handlePause() {
        manager.togglePause()

        if manager.isPaused {
            pauseItem.title          = "Resume updates"
            statusItem.button?.title = "(paused)"
        } else {
            pauseItem.title = "Pause updates"
            // Title will be refreshed on the next metrics tick automatically.
        }
    }

    @objc private func handleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Show a brief alert if registration fails (e.g. user denied in
            // System Settings → General → Login Items).
            let alert = NSAlert()
            alert.messageText     = "Could not update Login Item"
            alert.informativeText = error.localizedDescription
            alert.alertStyle      = .warning
            alert.runModal()
        }
        refreshLoginItemState()
    }

    // MARK: - Login item state

    /// Syncs the menu item checkmark with the actual SMAppService status.
    private func refreshLoginItemState() {
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }
}

