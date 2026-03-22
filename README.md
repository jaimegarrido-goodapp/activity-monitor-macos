# Activity Monitor macOS

A lightweight native macOS menu bar app that shows real-time CPU and RAM usage.

```
CPU 18% | RAM 12.4 GB
```

Click the menu bar item to see detailed stats, pause updates, or quit.

---

## Requirements

- macOS 12.0 (Monterey) or later
- Xcode 14 or later
- No third-party dependencies

---

## Project Structure

```
ActivityMonitor/
└── ActivityMonitor/
    ├── App/
    │   ├── main.swift                 Entry point (manual NSApplication setup)
    │   └── AppDelegate.swift          Bootstraps StatusBarController
    ├── Controllers/
    │   └── StatusBarController.swift  NSStatusItem + NSMenu + UI updates
    ├── Monitors/
    │   ├── CPUMonitor.swift           host_processor_info tick-delta algorithm
    │   └── MemoryMonitor.swift        host_statistics64 active+wired pages
    ├── Managers/
    │   └── MetricsManager.swift       1-second Timer, background sampling
    ├── Models/
    │   └── SystemMetrics.swift        Plain struct with formatted string helpers
    └── Resources/
        └── Info.plist                 LSUIElement=YES, minimum macOS 12.0
```

---

## Xcode Setup (step by step)

### 1. Create the Xcode project

1. Open Xcode → **File → New → Project**
2. Choose **macOS → App** → Next
3. Fill in:
   - Product Name: `ActivityMonitor`
   - Team: *(your team, or "None" for local testing)*
   - Organization Identifier: `com.yourname`
   - Interface: **Storyboard**  ← important, NOT SwiftUI
   - Language: **Swift**
   - Uncheck "Use Core Data" and "Include Tests"
4. Save into `~/Proyectos/` (Xcode will create the `ActivityMonitor/` folder)

### 2. Clean up the generated template

Delete these auto-generated files (Move to Trash):
- `ViewController.swift`
- `Main.storyboard`
- `AppDelegate.swift` *(we replace it with our own)*

### 3. Remove the storyboard reference from Info.plist

In **Info.plist** (the one Xcode generated inside the target), delete the key:
```
NSMainStoryboardFile (or "Main storyboard file base name")
```

> Alternatively, just replace the entire Info.plist with the one provided in `Resources/Info.plist`.

### 4. Add the source files

Drag-and-drop all folders from `ActivityMonitor/ActivityMonitor/` into the Xcode project navigator **onto the ActivityMonitor group**:

```
App/          → contains main.swift, AppDelegate.swift
Controllers/  → StatusBarController.swift
Monitors/     → CPUMonitor.swift, MemoryMonitor.swift
Managers/     → MetricsManager.swift
Models/       → SystemMetrics.swift
```

When prompted, choose:
- ☑ Copy items if needed
- ☑ Add to target: ActivityMonitor

### 5. Set Info.plist key: LSUIElement

Open the **Info.plist** in the project and add (if not already present):

| Key | Type | Value |
|-----|------|-------|
| Application is agent (UIElement) | Boolean | YES |

Or in the raw XML: `<key>LSUIElement</key><true/>`

### 6. Set the deployment target

In the project settings → General → Minimum Deployments → macOS **12.0**

### 7. Build and Run

Press **Cmd+R**. The app will NOT appear in the Dock.
Look for `CPU XX% | RAM XX.X GB` in the top-right of your menu bar.

---

## How the metrics work

### CPU

Uses `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` which returns four
monotonically-increasing tick counters per logical core:

```
user   – time in user-space
system – time in kernel
idle   – time idle
nice   – time in user-space at reduced priority
```

Two consecutive samples are compared (delta). The percentage is:

```
cpu% = (Δuser + Δsystem + Δnice) / (Δuser + Δsystem + Δidle + Δnice) × 100
```

The Mach-allocated buffer is freed with `vm_deallocate` after every call.

### RAM

Uses `host_statistics64(HOST_VM_INFO64)` → `vm_statistics64`.

```
used  = (active_count + wire_count) × vm_kernel_page_size
total = ProcessInfo.processInfo.physicalMemory
```

"Used" matches what macOS Activity Monitor labels as used memory
(active + wired, excluding inactive/reclaimable pages).

---

## Permissions & Entitlements

**No special entitlements are required.** The Darwin APIs used
(`host_processor_info`, `host_statistics64`) are public and available to
any unprivileged process.

> **App Store note:** App Sandbox (required for App Store distribution)
> blocks `host_processor_info`. To distribute via App Store you would need
> to switch to the `ActivityMonitor` framework API or use
> `IOKit` alternatives. For direct (notarized) distribution outside the
> App Store, no sandbox is needed.

---

## Known Limitations

| Limitation | Notes |
|---|---|
| CPU is a system-wide average | Per-core breakdown is a v2 feature |
| "Used" RAM excludes compressed/cached | Matches Activity Monitor's definition |
| No launch-at-login | Can be added with `SMAppService` (macOS 13+) |
| No persistent settings | Everything resets on relaunch |

---

## Possible Future Features

- Per-core CPU graph in the menu
- Compressed memory tracking
- Network in/out bandwidth
- Disk read/write activity
- Launch at login (SMAppService)
- Top processes list
- Configurable update interval
