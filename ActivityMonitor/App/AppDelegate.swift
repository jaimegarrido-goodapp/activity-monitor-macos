// AppDelegate.swift
// ActivityMonitor
//
// Application lifecycle. Creates and holds the StatusBarController
// (which in turn holds the MetricsManager).
//
// NOTE: This class must NOT be annotated with @NSApplicationMain or @main
// because we use a manual main.swift entry point.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Strong reference – keeping this alive keeps the status item alive.
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = MetricsManager()
        statusBarController = StatusBarController(manager: manager)
    }

    // Menu bar apps have no regular windows, so we must NOT quit when the
    // last (non-existent) window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
