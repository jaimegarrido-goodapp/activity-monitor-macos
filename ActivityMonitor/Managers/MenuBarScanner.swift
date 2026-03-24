// MenuBarScanner.swift
// ActivityMonitor
//
// Enumerates all third-party status-item windows currently visible in the
// system menu bar and publishes a [MenuBarItemInfo] list.
//
// HOW DETECTION WORKS
// ────────────────────
// macOS renders each NSStatusItem as its own CGWindow at layer 25
// (kCGWindowLayer == 25, also known as the "status bar" level).
// CGWindowListCopyWindowInfo gives us the full list of on-screen windows
// with their owner PID, owner name, and screen-space bounds.
//
// We filter for layer-25 windows, skip system-owned processes, then
// correlate each PID with NSRunningApplication to get the bundle ID and icon.
//
// THREADING
// ──────────
// All public methods MUST be called on the main thread:
//   • CGWindowListCopyWindowInfo is fast (~1 ms) and main-thread safe.
//   • AXUIElement calls are only safe on the main thread (AX framework rule).
//   • onScan is always invoked on the main thread.
//
// RE-SCAN TRIGGERS
// ────────────────
// • Manual: scan() called directly.
// • Automatic: NSWorkspace app-launched / terminated notifications.
// • Periodic: timer every scanInterval seconds (catches dynamic icon changes).

import AppKit
import CoreGraphics

final class MenuBarScanner {

    // MARK: - Configuration

    /// Seconds between automatic periodic scans.
    private let scanInterval: TimeInterval = 5

    // MARK: - Output

    /// Called on the main thread after every scan with the updated item list.
    var onScan: (([MenuBarItemInfo]) -> Void)?

    // MARK: - Private state

    private var periodicTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    // Bundle IDs that are always system-owned and must never be managed.
    private let systemBundleIDs: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.TextInputMenuAgent",
        "com.apple.coreservices.uiagent",
    ]

    // Window owner names for processes with no bundle ID (e.g. WindowServer).
    private let systemOwnerNames: Set<String> = [
        "Window Server",
        "WindowServer",
    ]

    // MARK: - Init / deinit

    init() {
        registerWorkspaceObservers()
    }

    deinit {
        stopPeriodicScanning()
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    // MARK: - Public API

    /// Performs a synchronous scan and delivers results via onScan.
    /// Must be called on the main thread.
    func scan() {
        let items = collectItems()
        onScan?(items)
    }

    /// Starts a repeating timer that calls scan() every scanInterval seconds.
    func startPeriodicScanning() {
        guard periodicTimer == nil else { return }
        periodicTimer = Timer.scheduledTimer(
            withTimeInterval: scanInterval,
            repeats:          true
        ) { [weak self] _ in
            self?.scan()
        }
        // Keep scanning even while a menu is open.
        RunLoop.main.add(periodicTimer!, forMode: .common)
    }

    func stopPeriodicScanning() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    // MARK: - Core enumeration

    private func collectItems() -> [MenuBarItemInfo] {
        // Fetch all on-screen windows excluding desktop elements.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[CFString: Any]] else {
            return []
        }

        var items: [MenuBarItemInfo] = []

        for dict in windowList {
            guard let item = buildItem(from: dict) else { continue }
            items.append(item)
        }

        // Sort left-to-right (descending x, because menu bar items are right-aligned).
        return items.sorted { $0.frame.minX > $1.frame.minX }
    }

    private func buildItem(from dict: [CFString: Any]) -> MenuBarItemInfo? {
        // Filter: must be at the status-item window layer (25).
        guard let layer = dict[kCGWindowLayer] as? Int, layer == 25 else { return nil }

        // Get window ID.
        guard let windowIDRaw = dict[kCGWindowNumber] as? UInt32 else { return nil }
        let windowID = CGWindowID(windowIDRaw)

        // Get owner info (may be empty if Screen Recording not granted).
        let ownerName = dict[kCGWindowOwnerName] as? String ?? ""
        let ownerPID  = dict[kCGWindowOwnerPID]  as? pid_t  ?? 0

        // Skip system-owned windows.
        guard !isSystemOwned(pid: ownerPID, ownerName: ownerName) else { return nil }

        // Get screen-space frame.
        // Cast via NSDictionary (toll-free bridged with CFDictionary) to avoid
        // the "conditional downcast always succeeds" warning on CFDictionary.
        guard let boundsDict = dict[kCGWindowBounds] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDict) else { return nil }

        // Skip windows with zero or tiny area (some helper items have 0-width).
        guard frame.width > 2 && frame.height > 2 else { return nil }

        // Skip windows that are not in the menu bar area.
        // CGWindowList uses CG coordinates (y=0 at top of screen), so genuine
        // menu bar status items always start at y ≈ 0. Floating toolbars or HUDs
        // from screenshot apps (e.g. iScrean Shoter) sit lower on the screen and
        // also appear at layer 25 — this filter excludes them.
        guard frame.origin.y < 50 else { return nil }

        // Correlate with NSRunningApplication.
        let runningApp     = NSRunningApplication(processIdentifier: ownerPID)
        let bundleID       = runningApp?.bundleIdentifier ?? ""
        let resolvedName   = ownerName.isEmpty ? (runningApp?.localizedName ?? "") : ownerName
        let appIcon        = runningApp?.icon

        // Skip if we can't identify the owner at all (no name, no bundle, unknown PID).
        guard !resolvedName.isEmpty || !bundleID.isEmpty else { return nil }

        // Skip our own process to avoid managing our own status item.
        if ownerPID == ProcessInfo.processInfo.processIdentifier { return nil }

        let isHidden = PreferencesManager.shared.isHidden(bundleID: bundleID)

        return MenuBarItemInfo(
            id:            UUID(),
            windowID:      windowID,
            ownerPID:      ownerPID,
            ownerBundleID: bundleID,
            ownerName:     resolvedName,
            frame:         frame,
            appIcon:       appIcon,
            isHidden:      isHidden
        )
    }

    // MARK: - System-owned check

    private func isSystemOwned(pid: pid_t, ownerName: String) -> Bool {
        if systemOwnerNames.contains(ownerName) { return true }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if let bid = app.bundleIdentifier, systemBundleIDs.contains(bid) { return true }
        return false
    }

    // MARK: - Workspace observers

    private func registerWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Brief delay so the status item has time to appear/disappear.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.scan()
                }
            }
            workspaceObservers.append(obs)
        }
    }
}
