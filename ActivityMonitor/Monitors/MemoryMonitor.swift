// MemoryMonitor.swift
// ActivityMonitor
//
// Reads physical memory statistics from the Darwin kernel using the
// host_statistics64 API.
//
// HOW IT WORKS
// ─────────────
// The kernel tracks physical page usage in several categories:
//
//   internal_page_count   – anonymous pages owned by processes (active + inactive
//                           non-file-backed). This is what Activity Monitor calls
//                           "App Memory". Includes inactive pages that haven't
//                           been freed yet — they still occupy physical RAM.
//   wire_count            – pages that cannot be paged out (kernel / locked)
//   compressor_page_count – physical RAM used by macOS's memory compressor.
//                           When RAM pressure rises, macOS compresses pages
//                           instead of swapping to disk. This field counts
//                           the compressed pages still sitting in RAM.
//   external_page_count   – file-backed pages ("Cached files" in Activity
//                           Monitor). These are reclaimable, so not counted
//                           as "used".
//   free_count            – truly free pages.
//
// Formula matching Activity Monitor's "Memoria usada":
//   used = internal_page_count + wire_count + compressor_page_count
//
// The old formula (active + wired) was too low because it missed:
//   • inactive anonymous pages (still occupying RAM, not yet reclaimed)
//   • memory held by the compressor
//
// Total RAM comes from ProcessInfo.physicalMemory which reads the hw.memsize
// sysctl — it is constant for the lifetime of the process and never changes.
//
// APPLE SILICON vs INTEL
// ──────────────────────
// On Apple Silicon the kernel page size is 16 KB; on Intel it is 4 KB.
// vm_kernel_page_size is the correct value to use here — it automatically
// reflects the hardware. Using a hard-coded 4096 would produce wrong results
// on Apple Silicon.

import Darwin
import Foundation

final class MemoryMonitor {

    /// Total physical RAM (bytes). Constant – read once at init.
    let totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory

    /// Returns bytes of memory currently "used", matching Activity Monitor's
    /// "Memoria usada" figure: app memory + wired + compressed.
    func usedMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let kr: kern_return_t = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard kr == KERN_SUCCESS else { return 0 }

        // vm_kernel_page_size: 16 384 bytes on Apple Silicon, 4 096 on Intel.
        let pageSize   = UInt64(vm_kernel_page_size)
        let appMemory  = UInt64(stats.internal_page_count)   * pageSize  // anonymous pages (active + inactive)
        let wired      = UInt64(stats.wire_count)             * pageSize  // kernel / non-pageable
        let compressed = UInt64(stats.compressor_page_count)  * pageSize  // RAM used by compressor

        return appMemory + wired + compressed
    }
}
