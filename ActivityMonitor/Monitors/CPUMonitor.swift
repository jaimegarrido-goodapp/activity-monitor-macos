// CPUMonitor.swift
// ActivityMonitor
//
// Calculates system-wide CPU usage using the Darwin kernel's
// host_processor_info API.
//
// HOW IT WORKS
// ─────────────
// The kernel maintains four monotonically-increasing tick counters per
// logical CPU core:
//
//   CPU_STATE_USER   – time spent running user-space code
//   CPU_STATE_SYSTEM – time spent in kernel code on behalf of a process
//   CPU_STATE_IDLE   – time the core was idle
//   CPU_STATE_NICE   – time running user-space code at reduced priority
//
// A single snapshot is meaningless; we need two consecutive snapshots and
// compute the delta. The ratio of (user + system + nice) ticks to the
// total gives the CPU load percentage:
//
//   used  = Σ cores  (Δuser + Δsystem + Δnice)
//   total = Σ cores  (Δuser + Δsystem + Δidle + Δnice)
//   cpu % = used / total * 100
//
// APPLE SILICON vs INTEL
// ──────────────────────
// The API is identical on both. Apple Silicon typically reports more
// logical cores (efficiency + performance clusters), but the calculation
// is unchanged because we sum across all cores uniformly.
//
// MEMORY MANAGEMENT
// ─────────────────
// host_processor_info allocates a Mach buffer. We MUST call vm_deallocate
// after every successful call or the process will leak kernel memory.

import Darwin
import Foundation

final class CPUMonitor {

    // Flat array of tick counts from the previous sample.
    // Layout: [core0_user, core0_sys, core0_idle, core0_nice, core1_user, ...]
    private var previousTicks: [UInt32] = []
    private var previousCoreCount: Int  = 0

    /// Returns system-wide CPU usage as a percentage in [0, 100].
    /// Returns `nil` on the very first call because there is no delta yet.
    func cpuUsage() -> Double? {
        var cpuInfoPtr: processor_info_array_t?
        var numCPUInfo:  mach_msg_type_number_t = 0
        var numCPUs:     natural_t              = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfoPtr,
            &numCPUInfo
        )

        guard kr == KERN_SUCCESS, let ptr = cpuInfoPtr else { return nil }

        let coreCount  = Int(numCPUs)
        let stateCount = Int(CPU_STATE_MAX)   // always 4

        // --- Copy tick values out of the Mach buffer ---
        // integer_t is Int32 on Darwin; we reinterpret as UInt32 so that
        // wrapping subtraction (&-) handles counter overflow correctly.
        var current = [UInt32](repeating: 0, count: coreCount * stateCount)
        for i in 0 ..< coreCount * stateCount {
            current[i] = UInt32(bitPattern: ptr[i])
        }

        // Release the kernel-allocated buffer (required, not optional).
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: ptr)),
            vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
        )

        // Save current as the next iteration's "previous" – always, even on
        // the first call where we return nil.
        defer {
            previousTicks     = current
            previousCoreCount = coreCount
        }

        // First sample – no delta available yet.
        guard !previousTicks.isEmpty, previousCoreCount == coreCount else {
            return nil
        }

        var usedDelta:  Double = 0
        var totalDelta: Double = 0

        for i in 0 ..< coreCount {
            let base = i * stateCount

            // &- is wrapping subtraction: handles the case where the 32-bit
            // counter has rolled over since the last sample.
            let user   = Double(current[base + Int(CPU_STATE_USER)]   &- previousTicks[base + Int(CPU_STATE_USER)])
            let system = Double(current[base + Int(CPU_STATE_SYSTEM)] &- previousTicks[base + Int(CPU_STATE_SYSTEM)])
            let idle   = Double(current[base + Int(CPU_STATE_IDLE)]   &- previousTicks[base + Int(CPU_STATE_IDLE)])
            let nice   = Double(current[base + Int(CPU_STATE_NICE)]   &- previousTicks[base + Int(CPU_STATE_NICE)])

            usedDelta  += user + system + nice
            totalDelta += user + system + idle + nice
        }

        guard totalDelta > 0 else { return 0 }
        return (usedDelta / totalDelta) * 100.0
    }
}
