// MenuBarItemInfo.swift
// ActivityMonitor
//
// Value type representing one menu bar extra (NSStatusItem) detected in the
// system menu bar. Produced by MenuBarScanner and consumed by OverlayController,
// ManagerWindowController, and PreferencesManager.

import AppKit
import CoreGraphics

struct MenuBarItemInfo: Identifiable, Equatable {

    // MARK: - Identity

    /// Stable local identity for use in dictionaries/sets within this session.
    /// Not persisted — use ownerBundleID for cross-launch identity.
    let id: UUID

    /// Core Graphics window ID for this status-item window.
    let windowID: CGWindowID

    // MARK: - Ownership

    /// PID of the process that owns this status item.
    let ownerPID: pid_t

    /// Bundle identifier of the owning app (e.g. "com.dropbox.Dropbox").
    /// Empty string if Screen Recording permission was not granted.
    let ownerBundleID: String

    /// Human-readable process name (e.g. "Dropbox").
    /// Empty string if Screen Recording permission was not granted.
    let ownerName: String

    // MARK: - Geometry

    /// Position and size of the status-item window in screen coordinates.
    /// Origin is bottom-left on macOS (CoreGraphics convention).
    /// This frame becomes stale whenever any icon to the left/right
    /// appears or disappears — callers must refresh via MenuBarScanner.
    var frame: CGRect

    // MARK: - Display

    /// App icon fetched from NSRunningApplication. May be nil for system helpers
    /// or processes that have no bundle.
    let appIcon: NSImage?

    // MARK: - User state

    /// Whether the user has chosen to hide this item.
    /// Persisted via PreferencesManager keyed on ownerBundleID.
    var isHidden: Bool

    // MARK: - Equatable

    // Two items are considered the same if they represent the same CG window.
    static func == (lhs: MenuBarItemInfo, rhs: MenuBarItemInfo) -> Bool {
        lhs.windowID == rhs.windowID
    }
}
