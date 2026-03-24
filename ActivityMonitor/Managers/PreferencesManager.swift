// PreferencesManager.swift
// ActivityMonitor
//
// Thin wrapper around UserDefaults that persists the user's menu bar
// management choices across launches.
//
// Keys stored under the standard UserDefaults suite:
//   hiddenBundleIDs  – [String]  apps whose status-item overlay is active
//   proxyBundleIDs   – [String]  apps for which a proxy NSStatusItem exists

import Foundation

final class PreferencesManager {

    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let hiddenBundleIDs = "hiddenBundleIDs"
        static let proxyBundleIDs  = "proxyBundleIDs"
    }

    // MARK: - Hidden items

    var hiddenBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.hiddenBundleIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.hiddenBundleIDs) }
    }

    func isHidden(bundleID: String) -> Bool {
        hiddenBundleIDs.contains(bundleID)
    }

    func setHidden(_ hidden: Bool, bundleID: String) {
        guard !bundleID.isEmpty else { return }
        var ids = hiddenBundleIDs
        if hidden { ids.insert(bundleID) } else { ids.remove(bundleID) }
        hiddenBundleIDs = ids
    }

    // MARK: - Proxy items (ordered — insertion order is preserved)

    var proxyBundleIDs: [String] {
        get { defaults.stringArray(forKey: Key.proxyBundleIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.proxyBundleIDs) }
    }

    func hasProxy(bundleID: String) -> Bool {
        proxyBundleIDs.contains(bundleID)
    }

    func setProxy(_ enabled: Bool, bundleID: String) {
        guard !bundleID.isEmpty else { return }
        var ids = proxyBundleIDs
        if enabled {
            if !ids.contains(bundleID) { ids.append(bundleID) }
        } else {
            ids.removeAll { $0 == bundleID }
        }
        proxyBundleIDs = ids
    }
}
