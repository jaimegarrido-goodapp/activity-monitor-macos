// AppDelegate.swift
// ActivityMonitor
//
// Application lifecycle. Bootstraps the full object graph:
//
//   MetricsManager → StatusBarController      (system monitor, unchanged)
//   MenuBarScanner
//   OverlayController
//   ProxyItemController
//   ManagerWindowController                   (new menu bar manager)
//
// All new controllers are held as strong properties here so they stay alive
// for the entire app lifetime.
//
// NOTE: This class must NOT be annotated with @NSApplicationMain or @main
// because we use a manual main.swift entry point.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - System monitor (original)

    private var statusBarController: StatusBarController?

    // MARK: - Menu bar manager (new)

    private let scanner             = MenuBarScanner()
    private let overlayController   = OverlayController()
    private let proxyController     = ProxyItemController()
    private var managerWindowController: ManagerWindowController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {

        // --- Original system monitor ---
        let manager = MetricsManager()
        let sbc = StatusBarController(manager: manager)
        statusBarController = sbc

        // --- Menu bar manager setup ---

        // 1. Build the manager window and inject dependencies.
        let mwc = ManagerWindowController()
        mwc.scanner           = scanner
        mwc.overlayController = overlayController
        mwc.proxyController   = proxyController
        managerWindowController = mwc

        // Give StatusBarController a reference so it can open the window.
        sbc.managerWindowController = mwc

        // 2. Request Screen Recording permission (non-blocking).
        PermissionsManager.shared.requestPermissionsIfNeeded()

        // 3. Wire scanner output to overlay + manager window.
        scanner.onScan = { [weak self] items in
            guard let self else { return }
            self.overlayController.apply(items: items)
            self.managerWindowController?.reload(items: items)
        }

        // 4. Restore saved proxies from previous sessions.
        proxyController.restoreSavedProxies()

        // 5. Initial scan + start periodic re-scanning.
        scanner.scan()
        scanner.startPeriodicScanning()

        // 6. Re-scan when display configuration changes (screen size, resolution…).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name:     NSApplication.didChangeScreenParametersNotification,
            object:   nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Screen change handler

    @objc private func handleScreenChange() {
        scanner.scan()
    }
}
