// PermissionsManager.swift
// ActivityMonitor
//
// Checks and requests the two permissions the Menu Bar Manager needs:
//
//   Screen Recording  – required for CGWindowListCopyWindowInfo to return
//                       kCGWindowOwnerName / kCGWindowOwnerPID on macOS 12+.
//                       Without it, owner info is empty and we can only count
//                       windows, not identify the owning app.
//
//   Accessibility     – required for AXUIElement calls that give finer-grained
//                       status-item correlation. Optional: the app degrades
//                       gracefully to CGWindow-only mode if not granted.
//
// IMPORTANT: AXIsProcessTrustedWithOptions (which shows the system prompt)
// must only be called once, on explicit user intent. Subsequent launches
// just check AXIsProcessTrusted() silently.

import AppKit
import ApplicationServices   // AXIsProcessTrusted

final class PermissionsManager {

    static let shared = PermissionsManager()

    // MARK: - Status checks

    var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Request flows

    /// Call once at launch. Shows macOS system dialogs as needed.
    /// Non-blocking — the user can dismiss the dialogs without stalling the app.
    func requestPermissionsIfNeeded() {
        requestScreenRecordingIfNeeded()
        // Accessibility is requested only when the user explicitly opens the
        // Manager window (see ManagerWindowController), so we don't prompt here.
    }

    /// Triggers the Screen Recording system prompt (if not already granted).
    /// On macOS 15+ the dialog is one-time; after that the user must go to
    /// System Settings → Privacy → Screen Recording manually.
    func requestScreenRecordingIfNeeded() {
        guard !hasScreenRecording else { return }
        CGRequestScreenCaptureAccess()
    }

    /// Shows the Accessibility system prompt / opens System Settings.
    /// Call this only on explicit user action (e.g. a button click).
    func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Degraded-mode explanation

    /// Returns a short description of current permission state for display
    /// in the Manager window banner.
    func statusDescription() -> String? {
        switch (hasScreenRecording, hasAccessibility) {
        case (true, true):
            return nil   // full functionality, no banner needed
        case (false, _):
            return "Screen Recording permission is needed to identify apps. " +
                   "Grant it in System Settings → Privacy & Security → Screen Recording."
        case (true, false):
            return "Accessibility permission is optional but improves detection accuracy. " +
                   "Grant it in System Settings → Privacy & Security → Accessibility."
        }
    }
}
