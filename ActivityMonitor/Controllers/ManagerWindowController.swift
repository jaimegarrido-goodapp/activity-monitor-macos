// ManagerWindowController.swift
// ActivityMonitor
//
// A floating, non-modal NSWindow that lists all detected third-party menu bar
// apps. Each row has a toggle to hide/show the icon and a button to add a
// proxy status item for apps that have none.
//
// The window is built entirely in code (no .xib), uses NSScrollView +
// NSStackView for the list, and is opened from StatusBarController via
// "Manage Menu Bar…". It can stay open while the user interacts with the
// menu bar; it is non-modal and moves to the active Space.
//
// THREADING: all methods must be called on the main thread.

import AppKit

// MARK: - ManagerWindowController

final class ManagerWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Dependencies (injected by AppDelegate)

    weak var scanner:         MenuBarScanner?
    weak var overlayController: OverlayController?
    weak var proxyController:   ProxyItemController?

    // MARK: - Private UI

    private let stackView   = NSStackView()
    private let scrollView  = NSScrollView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let refreshBtn  = NSButton(title: "Refresh", target: nil, action: nil)
    private let addProxyBtn = NSButton(title: "Add Proxy for App…", target: nil, action: nil)

    // Last scan results — kept so we can apply prefs on toggle.
    private var currentItems: [MenuBarItemInfo] = []

    // MARK: - Init

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask:   [.titled, .closable, .resizable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        win.title              = "Menu Bar Manager"
        win.minSize            = NSSize(width: 300, height: 300)
        win.collectionBehavior = [.moveToActiveSpace]
        win.center()

        super.init(window: win)
        win.delegate = self

        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - Public

    /// Reload the list from a fresh scan result.
    func reload(items: [MenuBarItemInfo]) {
        currentItems = items
        rebuildRows()
        updateBanner()
    }

    // MARK: - UI Construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        // --- Top toolbar ---
        refreshBtn.target = self
        refreshBtn.action = #selector(handleRefresh)
        refreshBtn.bezelStyle = .rounded

        addProxyBtn.target = self
        addProxyBtn.action = #selector(handleAddProxy)
        addProxyBtn.bezelStyle = .rounded

        let toolbar = NSStackView(views: [refreshBtn, NSView(), addProxyBtn])
        toolbar.orientation  = .horizontal
        toolbar.distribution = .fill
        toolbar.spacing      = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        // --- Permission banner ---
        bannerLabel.isHidden    = true
        bannerLabel.lineBreakMode = .byWordWrapping
        bannerLabel.maximumNumberOfLines = 0
        bannerLabel.textColor   = .secondaryLabelColor
        bannerLabel.font        = NSFont.systemFont(ofSize: 11)
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false

        // --- Scroll list ---
        stackView.orientation         = .vertical
        stackView.alignment           = .leading
        stackView.spacing             = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.documentView = stackView

        scrollView.contentView         = clipView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // --- Layout ---
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(toolbar)
        contentView.addSubview(bannerLabel)
        contentView.addSubview(separator)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            bannerLabel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            bannerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            bannerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            separator.topAnchor.constraint(equalTo: bannerLabel.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Let the stack view fill the scroll area width.
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func rebuildRows() {
        // Remove all existing rows.
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if currentItems.isEmpty {
            let empty = NSTextField(labelWithString: "No third-party menu bar icons detected.\nMake sure Screen Recording permission is granted.")
            empty.maximumNumberOfLines = 0
            empty.textColor = .secondaryLabelColor
            empty.font      = NSFont.systemFont(ofSize: 12)
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(empty)
            empty.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                empty.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 16),
                empty.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
                empty.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
                empty.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -16),
            ])
            stackView.addArrangedSubview(wrapper)
            return
        }

        for (index, item) in currentItems.enumerated() {
            let row = MenuBarItemRow(item: item, index: index)
            row.onToggleHide = { [weak self] hide in
                self?.toggleHide(hide, for: item)
            }
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }

    private func updateBanner() {
        if let msg = PermissionsManager.shared.statusDescription() {
            bannerLabel.stringValue = msg
            bannerLabel.isHidden    = false
        } else {
            bannerLabel.isHidden = true
        }
    }

    // MARK: - Toggle logic

    private func toggleHide(_ hide: Bool, for item: MenuBarItemInfo) {
        guard !item.ownerBundleID.isEmpty else { return }
        PreferencesManager.shared.setHidden(hide, bundleID: item.ownerBundleID)

        // Update our local copy so the row reflects the new state immediately.
        if let idx = currentItems.firstIndex(where: { $0.id == item.id }) {
            currentItems[idx].isHidden = hide
        }

        // Apply overlay change.
        if hide {
            var updated = item
            updated.isHidden = true
            overlayController?.hide(updated)
        } else {
            overlayController?.show(item)
        }
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        scanner?.scan()
    }

    @objc private func handleAddProxy(_ sender: NSButton) {
        // Build a list of running apps that have no detected status item.
        let detectedPIDs = Set(currentItems.map { $0.ownerPID })
        let candidates   = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
            !detectedPIDs.contains($0.processIdentifier) &&
            $0.bundleIdentifier != nil
        }

        guard !candidates.isEmpty else {
            let alert = NSAlert()
            alert.messageText     = "No apps available"
            alert.informativeText = "All running regular apps either already have a menu bar icon or a proxy."
            alert.alertStyle      = .informational
            alert.runModal()
            return
        }

        // Show a menu listing the candidates.
        let menu = NSMenu()
        for app in candidates.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
            let item = NSMenuItem(
                title:          app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                action:         #selector(handleProxySelection(_:)),
                keyEquivalent:  ""
            )
            item.target          = self
            item.representedObject = app
            if let icon = app.icon {
                let img = icon.copy() as! NSImage
                img.size = NSSize(width: 16, height: 16)
                item.image = img
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func handleProxySelection(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        proxyController?.addProxy(for: app)
        PreferencesManager.shared.setProxy(true, bundleID: bundleID)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Nothing to clean up; the window can be re-opened later.
    }
}

// MARK: - MenuBarItemRow

/// One row in the manager list: icon | name | hide toggle.
private final class MenuBarItemRow: NSView {

    var onToggleHide: ((Bool) -> Void)?

    private let toggle = NSButton(checkboxWithTitle: "Hide", target: nil, action: nil)
    private var isCurrentlyHidden: Bool

    init(item: MenuBarItemInfo, index: Int) {
        self.isCurrentlyHidden = item.isHidden
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // Alternating row background.
        if index % 2 == 0 {
            wantsLayer    = true
            layer?.backgroundColor = NSColor.alternatingContentBackgroundColors[1].cgColor
        }

        // Icon.
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let icon = item.appIcon {
            iconView.image = icon
        } else {
            iconView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        }

        // Name label.
        let nameLabel = NSTextField(labelWithString: item.ownerName.isEmpty ? item.ownerBundleID : item.ownerName)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font              = NSFont.systemFont(ofSize: 13)
        nameLabel.lineBreakMode     = .byTruncatingTail

        // Bundle ID sublabel.
        let bidLabel = NSTextField(labelWithString: item.ownerBundleID)
        bidLabel.translatesAutoresizingMaskIntoConstraints = false
        bidLabel.font      = NSFont.systemFont(ofSize: 10)
        bidLabel.textColor = .secondaryLabelColor
        bidLabel.lineBreakMode = .byTruncatingTail

        // Labels column.
        let labelStack = NSStackView(views: [nameLabel, bidLabel])
        labelStack.orientation  = .vertical
        labelStack.alignment    = .leading
        labelStack.spacing      = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        // Toggle.
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.state  = item.isHidden ? .on : .off
        toggle.target = self
        toggle.action = #selector(handleToggle)

        addSubview(iconView)
        addSubview(labelStack)
        addSubview(toggle)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            labelStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),

            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    @objc private func handleToggle() {
        isCurrentlyHidden = toggle.state == .on
        onToggleHide?(isCurrentlyHidden)
    }
}
