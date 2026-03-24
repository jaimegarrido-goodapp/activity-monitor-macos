// OverlayController.swift
// ActivityMonitor
//
// Places a borderless NSWindow on top of each status-item window that the
// user wants hidden. The overlay sits at window level 26 (one above the
// status-item layer at 25), uses NSVisualEffectView to blend with the menu
// bar background in both light and dark modes, and ignores mouse events so
// the underlying item continues to function (it just isn't visible).
//
// WHY OVERLAYS INSTEAD OF TRUE HIDING
// ─────────────────────────────────────
// There is no public API to hide another process's NSStatusItem. The overlay
// technique is the same approach used by Bartender and Ice. Caveats:
//   • The hidden item still occupies horizontal space in the menu bar.
//   • If any icon to the left/right appears or disappears, all frames shift.
//     Call updateFrame(for:) after each MenuBarScanner scan to reposition.
//
// THREADING: All methods must be called on the main thread (NSWindow).

import AppKit
import CoreGraphics

final class OverlayController {

    // MARK: - State

    // Key: the MenuBarItemInfo.id that this overlay covers.
    private var overlays: [UUID: NSWindow] = [:]

    // MARK: - Public API

    /// Creates an overlay covering `item.frame`. No-op if already hidden.
    func hide(_ item: MenuBarItemInfo) {
        guard overlays[item.id] == nil else { return }

        let overlay = makeOverlayWindow(frame: screenFrame(for: item))
        overlays[item.id] = overlay
        overlay.orderFrontRegardless()
    }

    /// Removes the overlay for `item`, making it visible again.
    func show(_ item: MenuBarItemInfo) {
        guard let overlay = overlays.removeValue(forKey: item.id) else { return }
        overlay.close()
    }

    /// Repositions an existing overlay when the item's frame has changed.
    /// Call this every time MenuBarScanner delivers a fresh scan result.
    func updateFrame(for item: MenuBarItemInfo) {
        guard let overlay = overlays[item.id] else { return }
        overlay.setFrame(screenFrame(for: item), display: true)
    }

    /// Applies a full scan result: hides items marked hidden, shows the rest,
    /// and repositions existing overlays. This is the main entry point called
    /// from AppDelegate after each MenuBarScanner.onScan delivery.
    func apply(items: [MenuBarItemInfo]) {
        for item in items {
            if item.isHidden {
                if overlays[item.id] != nil {
                    updateFrame(for: item)   // already hidden — just reposition
                } else {
                    hide(item)
                }
            } else {
                show(item)
            }
        }
    }

    /// Removes all overlays (e.g. when quitting or resetting prefs).
    func showAll() {
        for overlay in overlays.values { overlay.close() }
        overlays.removeAll()
    }

    // MARK: - Window factory

    private func makeOverlayWindow(frame: NSRect) -> NSWindow {
        let win = NSWindow(
            contentRect: frame,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )

        // NSWindow.Level.statusBar == 25 (the status-item layer).
        // Adding 1 puts us just above status items but below pull-down menus.
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        win.backgroundColor      = .clear
        win.isOpaque             = false
        win.hasShadow            = false
        win.ignoresMouseEvents   = true
        win.isReleasedWhenClosed = false   // we manage lifetime via the overlays dict
        win.collectionBehavior   = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // NSVisualEffectView with .menu material blends with the menu bar
        // background automatically in both Light and Dark appearances.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material      = .menu
        blur.blendingMode  = .behindWindow
        blur.state         = .active
        blur.autoresizingMask = [.width, .height]
        win.contentView = blur

        return win
    }

    // MARK: - Coordinate conversion

    // CGWindowListCopyWindowInfo returns frames in CoreGraphics coordinates
    // (origin at top-left of screen, y increases downward).
    // NSWindow.setFrame expects AppKit coordinates (origin at bottom-left, y up).
    private func screenFrame(for item: MenuBarItemInfo) -> NSRect {
        guard let screen = NSScreen.main else { return item.frame }
        let cgFrame = item.frame
        // Flip Y: AppKit Y = screenHeight - CG.origin.y - CG.height
        let appKitY = screen.frame.height - cgFrame.origin.y - cgFrame.height
        return NSRect(x: cgFrame.origin.x, y: appKitY,
                      width: cgFrame.width, height: cgFrame.height)
    }
}
