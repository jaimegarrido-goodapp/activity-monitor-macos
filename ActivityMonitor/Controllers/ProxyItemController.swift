// ProxyItemController.swift
// ActivityMonitor
//
// Manages proxy NSStatusItems for apps with no native menu bar icon.
//
// OVERFLOW SYSTEM
// ───────────────
// Only the first `maxDirectProxies` (8) proxies get their own NSStatusItem.
// Any additional proxies are collected in an overflow "•••" NSStatusItem whose
// menu lists them with a submenu: Activate / Quit / Remove Proxy.
//
// CLICK BEHAVIOR (direct proxies)
// ────────────────────────────────
// Left click:
//   • App not running          → launch it.
//   • 0 windows (AX available) → open/reopen (triggers applicationShouldHandleReopen).
//   • 1 window                 → show it directly (deminimize if needed).
//   • 2+ windows               → picker menu to choose which window to show.
// Right click / two-finger     → context menu: Activate / Quit / Remove Proxy.
//
// THREADING: all methods must be called on the main thread.

import AppKit
import ApplicationServices   // AXUIElement, AXIsProcessTrusted

final class ProxyItemController {

    // MARK: - Configuration

    /// Maximum number of proxies shown as individual NSStatusItems.
    /// Any beyond this limit go into the overflow "•••" item.
    private let maxDirectProxies = 8

    // MARK: - State

    /// Ordered list of all proxy bundle IDs (insertion order).
    private var proxyOrder: [String] = []

    /// Active direct NSStatusItems for the first `maxDirectProxies` entries.
    private var directItems: [String: NSStatusItem] = [:]

    /// The "•••" overflow status item; present only when needed.
    private var overflowStatusItem: NSStatusItem?

    /// Handler for the overflow button (retained via associated object).
    private let overflowHandler = OverflowHandler()

    // MARK: - Init

    init() {
        overflowHandler.controller = self
    }

    // MARK: - Public API

    func addProxy(for app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              !proxyOrder.contains(bundleID) else { return }
        proxyOrder.append(bundleID)
        PreferencesManager.shared.setProxy(true, bundleID: bundleID)
        syncItems()
    }

    func removeProxy(for bundleID: String) {
        guard proxyOrder.contains(bundleID) else { return }
        proxyOrder.removeAll { $0 == bundleID }
        PreferencesManager.shared.setProxy(false, bundleID: bundleID)
        syncItems()
    }

    func restoreSavedProxies() {
        for bundleID in PreferencesManager.shared.proxyBundleIDs
            where !proxyOrder.contains(bundleID) {
            proxyOrder.append(bundleID)
        }
        syncItems()
    }

    // MARK: - Sync

    private func syncItems() {
        let directIDs   = Array(proxyOrder.prefix(maxDirectProxies))
        let overflowIDs = Array(proxyOrder.dropFirst(maxDirectProxies))

        // Remove direct items that are no longer in the direct set.
        for bundleID in Array(directItems.keys) where !directIDs.contains(bundleID) {
            NSStatusBar.system.removeStatusItem(directItems.removeValue(forKey: bundleID)!)
        }

        // Create missing direct items.
        for bundleID in directIDs where directItems[bundleID] == nil {
            directItems[bundleID] = makeDirectStatusItem(bundleID: bundleID)
        }

        // Overflow item — created once and toggled with isVisible so macOS
        // retains its position in the menu bar across hide/show cycles.
        if overflowIDs.isEmpty {
            overflowStatusItem?.isVisible = false
        } else {
            if overflowStatusItem == nil {
                overflowStatusItem = makeOverflowStatusItem()
            }
            overflowStatusItem?.isVisible = true
            overflowHandler.bundleIDs = overflowIDs
        }
    }

    // MARK: - Direct item factory

    private func makeDirectStatusItem(bundleID: String) -> NSStatusItem {
        let item   = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let button = item.button!

        let app     = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
        let appName: String

        if let app = app {
            button.image   = scaledIcon(for: app)
            button.toolTip = app.localizedName
            appName        = app.localizedName ?? bundleID
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            img.size       = NSSize(width: 18, height: 18)
            button.image   = img
            button.toolTip = bundleID
            appName        = bundleID
        } else {
            button.image   = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            button.toolTip = bundleID
            appName        = bundleID
        }

        let handler    = ProxyButtonHandler(bundleID: bundleID, appName: appName, controller: self)
        handler.button = button
        button.target  = handler
        button.action  = #selector(ProxyButtonHandler.handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        objc_setAssociatedObject(item, &ProxyButtonHandler.key, handler, .OBJC_ASSOCIATION_RETAIN)

        return item
    }

    // MARK: - Overflow item factory

    private func makeOverflowStatusItem() -> NSStatusItem {
        let item   = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let button = item.button!

        let img = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More proxies")!
        img.size       = NSSize(width: 18, height: 18)
        button.image   = img
        button.toolTip = "More proxies"
        button.target  = overflowHandler
        button.action  = #selector(OverflowHandler.handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        objc_setAssociatedObject(item, &OverflowHandler.key, overflowHandler, .OBJC_ASSOCIATION_RETAIN)

        return item
    }

    // MARK: - Private helpers

    private func scaledIcon(for app: NSRunningApplication) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        guard let original = app.icon else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
        }
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        original.draw(in: NSRect(origin: .zero, size: size),
                      from: .zero, operation: .copy, fraction: 1.0)
        scaled.unlockFocus()
        scaled.isTemplate = false
        return scaled
    }
}

// MARK: - OverflowHandler

private final class OverflowHandler: NSObject {

    static var key: UInt8 = 0

    var bundleIDs: [String] = []
    weak var controller: ProxyItemController?

    @objc func handleClick(_ sender: NSStatusBarButton) {
        let menu = buildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Proxies", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for bundleID in bundleIDs {
            let app     = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
            let name    = app?.localizedName ?? bundleID
            let isAlive = app.map { !$0.isTerminated } ?? false

            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")

            if let icon = app?.icon {
                let img  = icon.copy() as! NSImage
                img.size = NSSize(width: 16, height: 16)
                item.image = img
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let img  = NSWorkspace.shared.icon(forFile: url.path)
                img.size = NSSize(width: 16, height: 16)
                item.image = img
            }

            // Submenu: Activate / Quit / Remove Proxy
            let sub = NSMenu()

            let activateItem = NSMenuItem(
                title:         isAlive ? "Activar \(name)" : "Lanzar \(name)",
                action:        #selector(activateProxy(_:)),
                keyEquivalent: ""
            )
            activateItem.target            = self
            activateItem.representedObject = bundleID
            sub.addItem(activateItem)

            if isAlive {
                let quitItem = NSMenuItem(
                    title:         "Cerrar \(name)",
                    action:        #selector(quitApp(_:)),
                    keyEquivalent: ""
                )
                quitItem.target            = self
                quitItem.representedObject = bundleID
                sub.addItem(quitItem)
            }

            sub.addItem(.separator())

            let removeItem = NSMenuItem(
                title:         "Eliminar proxy",
                action:        #selector(removeProxy(_:)),
                keyEquivalent: ""
            )
            removeItem.target            = self
            removeItem.representedObject = bundleID
            sub.addItem(removeItem)

            item.submenu = sub
            menu.addItem(item)
        }

        return menu
    }

    @objc private func activateProxy(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }

        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           !app.isTerminated {
            if bundleID == "com.apple.finder" {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
            } else if let url = app.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
            } else {
                app.activate(options: .activateIgnoringOtherApps)
            }
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
        }
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .terminate()
    }

    @objc private func removeProxy(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        controller?.removeProxy(for: bundleID)
    }
}

// MARK: - WindowRef

/// Wrapper to store an AXUIElement reference in NSMenuItem.representedObject.
private final class WindowRef {
    let element:     AXUIElement
    let app:         NSRunningApplication
    let isMinimized: Bool
    init(_ element: AXUIElement, app: NSRunningApplication, isMinimized: Bool) {
        self.element     = element
        self.app         = app
        self.isMinimized = isMinimized
    }
}

// MARK: - ProxyButtonHandler

private final class ProxyButtonHandler: NSObject {

    static var key: UInt8 = 0

    let bundleID: String
    let appName:  String
    weak var controller: ProxyItemController?
    weak var button: NSStatusBarButton?

    init(bundleID: String, appName: String, controller: ProxyItemController) {
        self.bundleID   = bundleID
        self.appName    = appName
        self.controller = controller
    }

    // MARK: - Click dispatch

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            handleLeftClick(from: sender)
        }
    }

    // MARK: - Left click logic

    private func handleLeftClick(from button: NSStatusBarButton) {
        guard let app = runningApp(), !app.isTerminated else {
            launch(); return
        }

        // Accessibility permission is required to enumerate windows.
        // If not granted, fall back to plain activate.
        guard AXIsProcessTrusted() else {
            openOrActivate(app)
            return
        }

        let windows = allWindows(for: app)

        switch windows.count {
        case 0:
            // No windows — open/reopen the app.
            openOrActivate(app)
        case 1:
            // Exactly one window — show it directly without a picker.
            focusWindow(windows[0].element, isMinimized: windows[0].isMinimized, app: app)
        default:
            // Multiple windows — let the user choose.
            showWindowPicker(windows, app: app, from: button)
        }
    }

    // MARK: - Window enumeration (Accessibility API)

    private struct WindowInfo {
        let element:     AXUIElement
        let title:       String
        let isMinimized: Bool
    }

    /// Returns all windows for `app` (open and minimized), with titles.
    /// Requires Accessibility permission; returns [] if not granted.
    private func allWindows(for app: NSRunningApplication) -> [WindowInfo] {
        guard AXIsProcessTrusted() else { return [] }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }

        return windows.map { window in
            var minVal: CFTypeRef?
            let isMinimized = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minVal) == .success
                           && (minVal as? Bool) == true

            var titleVal: CFTypeRef?
            let title: String
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleVal) == .success,
               let t = titleVal as? String, !t.isEmpty {
                title = t
            } else {
                title = app.localizedName ?? appName
            }
            return WindowInfo(element: window, title: title, isMinimized: isMinimized)
        }
    }

    // MARK: - Single-window focus

    private func focusWindow(_ element: AXUIElement, isMinimized: Bool, app: NSRunningApplication) {
        if isMinimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        } else {
            AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, true as CFTypeRef)
        }
        app.activate(options: .activateIgnoringOtherApps)
    }

    // MARK: - Window picker

    private func showWindowPicker(
        _ windows: [WindowInfo],
        app: NSRunningApplication,
        from button: NSStatusBarButton
    ) {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for win in windows {
            let title = win.isMinimized ? "⬇ \(win.title)" : win.title
            let item  = NSMenuItem(
                title:         title,
                action:        #selector(handleWindowSelection(_:)),
                keyEquivalent: ""
            )
            item.target            = self
            item.representedObject = WindowRef(win.element, app: app, isMinimized: win.isMinimized)
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    @objc private func handleWindowSelection(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? WindowRef else { return }
        focusWindow(ref.element, isMinimized: ref.isMinimized, app: ref.app)
    }

    // MARK: - Open / reactivate

    private func openOrActivate(_ app: NSRunningApplication) {
        // Finder: opening the home directory guarantees a window appears.
        if app.bundleIdentifier == "com.apple.finder" {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
            return
        }

        if let url = app.bundleURL {
            NSWorkspace.shared.openApplication(
                at:            url,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    // MARK: - Launch (app not running)

    private func launch() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(
                at:            url,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
        }
    }

    // MARK: - Right-click context menu

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = buildContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    private func buildContextMenu() -> NSMenu {
        let menu    = NSMenu()
        let isAlive = runningApp().map { !$0.isTerminated } ?? false

        let header = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let activateItem = NSMenuItem(
            title:         isAlive ? "Activar \(appName)" : "Lanzar \(appName)",
            action:        #selector(menuActivate),
            keyEquivalent: ""
        )
        activateItem.target = self
        menu.addItem(activateItem)

        if isAlive {
            let quitItem = NSMenuItem(
                title:         "Cerrar \(appName)",
                action:        #selector(menuQuit),
                keyEquivalent: ""
            )
            quitItem.target = self
            menu.addItem(quitItem)
        }

        menu.addItem(.separator())

        let removeItem = NSMenuItem(
            title:         "Eliminar proxy",
            action:        #selector(menuRemove),
            keyEquivalent: ""
        )
        removeItem.target = self
        menu.addItem(removeItem)

        return menu
    }

    @objc private func menuActivate() {
        guard let button else { return }
        handleLeftClick(from: button)
    }
    @objc private func menuQuit()   { runningApp()?.terminate() }
    @objc private func menuRemove() { controller?.removeProxy(for: bundleID) }

    // MARK: - Helpers

    private func runningApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })
    }
}
