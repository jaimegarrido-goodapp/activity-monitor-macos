// SystemMetrics.swift
// ActivityMonitor
//
// Plain value type holding a single performance snapshot.
// All formatting logic lives here to keep UI code clean.

import Foundation

struct SystemMetrics {
    /// System-wide CPU usage as a percentage (0.0 – 100.0).
    let cpuUsage: Double

    /// Bytes of RAM currently in active + wired use.
    let memoryUsed: UInt64

    /// Total physical RAM installed in the machine.
    let memoryTotal: UInt64

    // MARK: - Formatted strings for display

    /// Compact label shown in the menu bar, e.g. "CPU 18% | RAM 12GB"
    var statusBarTitle: String {
        String(
            format: "CPU %.0f%% | RAM %dGB",
            cpuUsage,
            Int(ceil(gigabytes(memoryUsed)))
        )
    }

    /// Detailed CPU line for the menu, e.g. "CPU: 18.3%"
    var cpuDetail: String {
        String(format: "CPU: %.1f%%", cpuUsage)
    }

    /// Detailed RAM line for the menu, e.g. "RAM: 12.4 GB / 32 GB"
    var memoryDetail: String {
        String(
            format: "RAM: %.1f GB / %.0f GB",
            gigabytes(memoryUsed),
            gigabytes(memoryTotal)
        )
    }

    // MARK: - Private helpers

    private func gigabytes(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_073_741_824   // 1024³
    }
}
