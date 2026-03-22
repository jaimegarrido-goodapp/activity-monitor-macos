// MetricsManager.swift
// ActivityMonitor
//
// Central coordinator that owns the update timer and publishes SystemMetrics
// to whoever is listening.
//
// THREADING MODEL
// ───────────────
// • The Timer fires on the main RunLoop (required so it keeps ticking even
//   when the menu is open – we add it with .common run loop mode).
// • The actual kernel reads are dispatched to a background serial queue so
//   we never block the main thread.
// • The callback is always delivered on the main thread so callers can
//   safely update AppKit UI without an extra DispatchQueue.main.async.

import Foundation

final class MetricsManager {

    // MARK: - Public interface

    /// Called on the main thread every `updateInterval` seconds.
    var onUpdate: ((SystemMetrics) -> Void)?

    /// Whether updates are currently paused by the user.
    private(set) var isPaused: Bool = false

    // MARK: - Private

    private let cpuMonitor    = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()

    private var timer: Timer?

    /// Background serial queue – all kernel reads happen here.
    private let samplingQueue = DispatchQueue(
        label: "com.activitymonitor.sampling",
        qos: .utility
    )

    private let updateInterval: TimeInterval = 1.0

    // MARK: - Lifecycle

    init() {
        // Warm-up: take one silent sample so the first real reading
        // already has a previous delta to compare against.
        // CPUMonitor is only ever touched from samplingQueue, so this is safe.
        samplingQueue.async { [weak self] in
            _ = self?.cpuMonitor.cpuUsage()
        }
    }

    // MARK: - Control

    func start() {
        guard timer == nil else { return }
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Pauses metric collection and stops the timer.
    func pause() {
        isPaused = true
        stop()
    }

    /// Resumes metric collection and restarts the timer.
    func resume() {
        isPaused = false
        start()
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    // MARK: - Private helpers

    private func scheduleTimer() {
        let t = Timer(timeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.fetchAndPublish()
        }
        // .common ensures the timer fires even while a menu is open
        // (the run loop switches to tracking mode during menu interaction).
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fetchAndPublish() {
        samplingQueue.async { [weak self] in
            guard let self else { return }

            let cpu   = self.cpuMonitor.cpuUsage() ?? 0   // 0 on first-ever tick
            let used  = self.memoryMonitor.usedMemory()
            let total = self.memoryMonitor.totalMemory

            let metrics = SystemMetrics(
                cpuUsage:    cpu,
                memoryUsed:  used,
                memoryTotal: total
            )

            DispatchQueue.main.async {
                self.onUpdate?(metrics)
            }
        }
    }
}
