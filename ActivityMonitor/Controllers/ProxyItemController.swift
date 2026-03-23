// ProxyItemController.swift
// ActivityMonitor
//
// Creates NSStatusItem "proxies" — clickable menu bar icons that represent
// apps that have no native menu bar presence. Clicking a proxy activates
// (or launches) the target app, making it easy to reach from the menu bar.
//
// Each proxy:
//   • Shows the target app's icon at 18×18pt (standard menu bar icon size).
//   • Opens a small NSMenu with: Activate / Quit / Remove Proxy.
//   • Survives app restarts when the bundle ID is stored in PreferencesManager.
//
// THREADING: all methods must be called on the main thread.

import AppKit

final class ProxyItemController {

    // MARK: - State

    // Key: bundle ID of the target app.
    private var proxies: [String: NSStatusItem] = [:]

    // MARK: - Public API

    /// Creates a proxy status item for `app` if one doesn't already exist.
    func addProxy(for app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, proxies[bundleID] == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image     = scaledIcon(for: app)
        item.button?.toolTip   = app.localizedName
        item.menu              = buildMenu(for: app)

        proxies[bundleID] = item
    }

    /// Removes the proxy for `bundleID`, if any.
    func removeProxy(for bundleID: String) {
        guard let item = proxies.removeValue(forKey: bundleID) else { return }
        NSStatusBar.system.removeStatusItem(item)
        PreferencesManager.shared.setProxy(false, bundleID: bundleID)
    }

    /// Restores proxies saved in PreferencesManager (called at launch).
    func restoreSavedProxies() {
        for bundleID in PreferencesManager.shared.proxyBundleIDs {
            // Try to match a currently running app.
            if let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == bundleID }) {
                addProxy(for: app)
            } else {
                // App isn't running — create a placeholder with the bundle URL.
                addPlaceholderProxy(bundleID: bundleID)
            }
        }
    }

    // MARK: - Private helpers

    private func scaledIcon(for app: NSRunningApplication) -> NSImage {
        let size  = NSSize(width: 18, height: 18)
        guard let original = app.icon else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
        }
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        original.draw(in: NSRect(origin: .zero, size: size),
                      from:      .zero,
                      operation: .copy,
                      fraction:  1.0)
        scaled.unlockFocus()
        scaled.isTemplate = false
        return scaled
    }

    private func buildMenu(for app: NSRunningApplication) -> NSMenu {
        let menu = NSMenu()

        let appName = app.localizedName ?? app.bundleIdentifier ?? "App"

        // Header (disabled, shows app name).
        let headerItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // Activate / Launch.
        let activateTitle = app.isTerminated ? "Launch \(appName)" : "Activate \(appName)"
        let activateItem  = NSMenuItem(
            title:         activateTitle,
            action:        #selector(ProxyMenuTarget.handleActivate),
            keyEquivalent: ""
        )
        activateItem.representedObject = app.bundleIdentifier
        menu.addItem(activateItem)

        // Quit (only if running).
        if !app.isTerminated {
            let quitItem = NSMenuItem(
                title:         "Quit \(appName)",
                action:        #selector(ProxyMenuTarget.handleQuit),
                keyEquivalent: ""
            )
            quitItem.representedObject = app.bundleIdentifier
            menu.addItem(quitItem)
        }

        menu.addItem(.separator())

        // Remove proxy.
        let removeItem = NSMenuItem(
            title:         "Remove Proxy",
            action:        #selector(ProxyMenuTarget.handleRemove),
            keyEquivalent: ""
        )
        removeItem.representedObject = app.bundleIdentifier
        menu.addItem(removeItem)

        // Attach a target object that holds a weak ref to self.
        let target = ProxyMenuTarget(controller: self)
        menu.items.forEach { $0.target = target }
        // Retain the target via associatedObject so it lives as long as the menu.
        objc_setAssociatedObject(menu, &ProxyMenuTarget.key, target, .OBJC_ASSOCIATION_RETAIN)

        return menu
    }

    /// Adds a stub proxy for an app that isn't currently running.
    private func addPlaceholderProxy(bundleID: String) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Try to load the icon from the bundle on disk.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            item.button?.image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            item.button?.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        }
        item.button?.toolTip = bundleID

        let menu = NSMenu()
        let launchItem = NSMenuItem(title: "Launch \(bundleID)", action: nil, keyEquivalent: "")
        launchItem.representedObject = bundleID
        menu.addItem(launchItem)
        menu.addItem(.separator())
        let removeItem = NSMenuItem(title: "Remove Proxy", action: nil, keyEquivalent: "")
        removeItem.representedObject = bundleID
        menu.addItem(removeItem)
        item.menu = menu

        proxies[bundleID] = item
    }
}

// MARK: - ProxyMenuTarget

/// Trampoline object that receives menu-item actions for a proxy item.
/// Held strongly by the NSMenu via an associated object.
private final class ProxyMenuTarget: NSObject {

    static var key: UInt8 = 0

    private weak var controller: ProxyItemController?

    init(controller: ProxyItemController) {
        self.controller = controller
    }

    @objc func handleActivate(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        if let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID }), !app.isTerminated {
            app.activate(options: .activateIgnoringOtherApps)
        } else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(
                    at:            url,
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, _ in }
            }
        }
    }

    @objc func handleQuit(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?.terminate()
    }

    @objc func handleRemove(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        controller?.removeProxy(for: bundleID)
    }
}
