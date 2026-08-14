# Contributing to MacMonitor

Thanks for taking the time to contribute. MacMonitor is intentionally small, native, and dependency-free — contributions that keep it fast and close to the metal are most welcome.

---

## Table of Contents

- [Development Setup](#development-setup)
- [Architecture Overview](#architecture-overview)
- [Adding a New Mac Model](#adding-a-new-mac-model)
- [Code Style](#code-style)
- [Opening an Issue](#opening-an-issue)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Good First Issues](#good-first-issues)
- [What We Won't Merge](#what-we-wont-merge)
- [Release Process](#release-process)
- [Support the Project](#support-the-project)

---

## Development Setup

**Requirements:**

| Tool | Version | Notes |
|------|---------|-------|
| Xcode | 15.0+ | Mac App Store |
| macOS | 13 Ventura+ | Apple Silicon only |
| Git | any | Pre-installed |

**Optional but useful:**
- SwiftLint — `brew install swiftlint` (run before PRs)
- GitHub CLI — `brew install gh` (for releases)

**Steps:**

```bash
# 1. Fork the repo, then clone your fork
git clone https://github.com/ryyansafar/MacMonitor.git
cd MacMonitor

# 2. Open in Xcode
open Macmonitor.xcodeproj
```

In Xcode:
- Select the `Macmonitor` target → **Signing & Capabilities** → set **Team** to your Apple ID (free account is fine)
- Do the same for `MacMonitorWidget`
- Press `Cmd+R` — the app appears in your menu bar

**Build and install the privileged helper (needed for GPU/temps/power):**

```bash
SDK=$(xcrun --show-sdk-path)

clang -ObjC \
  -o /tmp/macmonitor-helper \
  helper/macmonitor-helper.m \
  Macmonitor/IOReportWrapper.m \
  Macmonitor/SMC.c \
  -I Macmonitor/ \
  -framework Foundation -framework IOKit -framework CoreFoundation \
  -isysroot "$SDK" -L "$SDK/usr/lib" -lIOReport

sudo install -d -o root -g wheel -m 755 /Users/Shared/MacMonitor
sudo install -o root -g wheel -m 755 \
  /tmp/macmonitor-helper /Users/Shared/MacMonitor/macmonitor-helper
```

The app will prompt for admin approval on first launch to configure sudoers access for the helper.

---

## Architecture Overview

```
SystemStatsModel  (ObservableObject — single source of truth for all views)
    │
    ├── CPU          host_processor_info()         [Mach kernel, no sudo]
    ├── Memory       vm_statistics64()              [Mach kernel, no sudo]
    ├── Network      getifaddrs() delta             [BSD, no sudo]
    ├── Disk I/O     IOKit disk stats delta         [IOKit, no sudo]
    ├── Battery      IOKit / ioreg                  [IOKit, no sudo]
    └── GPU / Power  macmonitor-helper              [IOReport + SMC + HID, needs root]
                         └── IOReportWrapper.m      [Energy Model, CPU/GPU Stats, AMC/PMP]
                         └── SMC.c                  [AppleSMC: temps, fan, PSTR]
                         └── IOHIDEventSystem       [PMU tdie sensors]
```

**Key files:**

| File | Purpose |
|------|---------|
| `Macmonitor/SystemStatsModel.swift` | All published state, timers, sampling logic |
| `Macmonitor/PopoverView.swift` | The full dashboard SwiftUI view |
| `Macmonitor/IOReportWrapper.m` | Native IOReport + HID sampling (Obj-C) |
| `Macmonitor/IOReportWrapper.h` | `IOReportData` struct — the data contract |
| `Macmonitor/SMC.c` / `SMC.h` | Apple SMC read interface |
| `helper/macmonitor-helper.m` | Privileged binary — collects metrics, prints JSON, exits |
| `MacMonitorWidget/` | Standalone WidgetKit extension |

**Key design decisions:**

- **No App Sandbox** — Required to access Mach kernel APIs and IOReport. MacMonitor cannot be on the Mac App Store, but freely distributable as a DMG.
- **No third-party packages** — Zero Swift Package Manager dependencies. Everything is macOS native.
- **Privileged helper pattern** — IOReport power sampling needs root. A minimal binary (`macmonitor-helper`) runs with elevated privileges, outputs JSON to stdout, and exits. With no arguments it is read-only. The only accepted write commands are `--fan-max` and `--fan-auto`; both operate on every detected fan and reject arbitrary RPM input.
- **Two-sample delta** — IOReport, CPU ticks, DRAM bandwidth, and network are all rate metrics (energy/time = watts, ticks/time = %, bytes/time = GB/s). MacMonitor takes two samples 100ms apart and divides by the measured interval.
- **Persistent IOReport subscription** — `IOReportWrapper` creates one subscription at `+initialize` and reuses it across calls. Creating a subscription per-call is slow (~50ms overhead).

---

## Adding a New Mac Model

MacMonitor's sensor keys are verified against real hardware. If you have an M3, M4, M3 Pro, M4 Max, or any other Mac not in the tested hardware table, you can help validate sensors in 20 minutes.

**Step 1 — Build the scanner tools:**

```bash
cd sensor-research

SDK=$(xcrun --show-sdk-path)

# SMC + IOReport scanner
clang -ObjC -o what_is_accurate what_is_accurate.m mactop_smc.c \
  -framework Foundation -framework IOKit \
  -isysroot "$SDK" -L "$SDK/usr/lib" -lIOReport

# HID thermal sensor scanner
clang -ObjC -o hid_scanner hid_scanner.m \
  -framework Foundation -framework IOKit
```

**Step 2 — Run them:**

```bash
sudo ./what_is_accurate > smc_keys_$(sw_vers -productVersion)_$(sysctl -n hw.model).txt
./hid_scanner > hid_sensors_$(sw_vers -productVersion)_$(sysctl -n hw.model).txt
```

**Step 3 — Cross-check with mactop (if available):**

```bash
sudo mactop --dump-temps >> smc_keys_$(sw_vers -productVersion)_$(sysctl -n hw.model).txt
```

**Step 4 — Open a PR** with:
- The two output files
- Your `hw.model` string (`sysctl -n hw.model`)
- Your chip string (`sysctl -n machdep.cpu.brand_string`)
- Whether your Mac has a fan and how many

We'll update `SENSORS.md`, `IOReportWrapper.m` if needed, and add you to the hardware table in `README.md`.

---

## Code Style

**Swift (SwiftUI views and SystemStatsModel):**
- 4-space indentation (Xcode default)
- `@Published` properties use camelCase and describe what they represent (`gpuUsage`, not `ioReportGPUPercentValue`)
- Views named after what they display: `CPUSection`, `FanSection`, `PowerTile`
- Private helpers grouped with `// MARK: - Section`
- All colors defined via `Color(hex:)` extension — never `Color(.systemBlue)` or literals
- Dark-mode only (`preferredColorScheme(.dark)` at the root)
- Color palette: `#0A84FF` blue · `#30D158` green · `#BF5AF2` purple · `#FF9F0A` orange · `#FF453A` red · `#FFD60A` yellow · `#0E0E12` background

**Objective-C (IOReportWrapper, SMC, helper):**
- Follow the existing style in `IOReportWrapper.m` — C strings in hot paths (no ObjC bridge allocations per channel)
- New SMC keys must be documented in `SENSORS.md` before merging
- All sensor reads must have a validity check (e.g. `value > 10.0 && value < 150.0` for temperatures)
- Prefer `static` file-scope globals for persistent state (subscription, client, key arrays)

**Data flow:**
- Heavy work on `samplerQueue` (background DispatchQueue), never on main thread
- Results published back via `DispatchQueue.main.async`
- Use `shellResult()` in SystemStatsModel for subprocess calls — don't add new `Process` instantiations

---

## Opening an Issue

Search existing issues before filing a new one.

**Bug report — include:**
- macOS version: `sw_vers -productVersion`
- Chip: `sysctl -n machdep.cpu.brand_string`
- Model: `sysctl -n hw.model`
- Console logs: open Console.app, filter by `Macmonitor`, reproduce the bug, paste the relevant lines
- What you expected vs what happened + steps to reproduce

**Feature request — include:**
- What metric or capability you want
- What data source it would use (public API, IOReport group, SMC key)
- Why it fits in MacMonitor's scope (menu bar / dashboard / widget)

---

## Submitting a Pull Request

1. **Open an issue first** for anything beyond a trivial fix — saves time if the approach needs discussion before implementation.

2. **Branch:**
   ```bash
   git checkout -b feat/your-feature-name
   # or
   git checkout -b fix/what-was-broken
   ```

3. **Keep PRs focused.** One feature or fix per PR. Unrelated cleanup in a separate PR.

4. **Test on a physical device.** The iOS/macOS Simulator does not support Mach kernel CPU sampling, IOReport, or SMC. All testing must happen on real Apple Silicon hardware.

5. **PR checklist:**
   - [ ] Builds with no warnings (`Macmonitor` and `MacMonitorWidget` targets)
   - [ ] Helper builds cleanly with the clang command in [Development Setup](#development-setup)
   - [ ] All sensor values look correct vs `mactop --dump-temps` / `mactop --headless`
   - [ ] Battery section values match `pmset -g batt`
   - [ ] Widget renders in both Small and Medium (Widget Simulator in Xcode)
   - [ ] First-launch welcome window shows after `defaults delete rybo.Macmonitor hasLaunched`
   - [ ] App memory stays below ~30 MB at idle (check with Activity Monitor)
   - [ ] New SMC keys documented in `SENSORS.md`

6. **PR description:**
   - What changed and why
   - Trade-offs or alternatives you considered
   - Screenshots if UI is affected

---

## Good First Issues

| Issue | Where to look |
|-------|--------------|
| Dual-fan support | `IOReportWrapper.m` — add `F1Ac` read; `PopoverView.swift` — add second fan row |
| Configurable refresh interval | `SystemStatsModel.swift` timer setup + `SettingsSheet` in `PopoverView.swift` |
| Memory pressure label | `SystemStatsModel.swift` — `HOST_VM_INFO64` has a `external_page_count`; surface it in `MemorySection` |
| Global keyboard shortcut | `AppDelegate.swift` — `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` |
| Disk space section | `PopoverView.swift` — `FileManager.default.volumeAvailableCapacityForImportantUsage` |
| Per-core temperature display | `IOReportWrapper.m` — expose individual `Tp*` key values; `PopoverView.swift` — add core temp grid |
| M3/M4 sensor validation | See [Adding a New Mac Model](#adding-a-new-mac-model) |

---

## What We Won't Merge

- Anything that requires a **paid Apple Developer account** to build from source
- **New third-party Swift Package dependencies** — zero-dependency is a feature
- **Mac App Store compatibility shims** — sandbox restrictions break core functionality
- **Intel Mac support** — IOReport cluster data, ANE power, and per-die temperatures are Apple Silicon-specific
- **UI changes that increase visual noise** — the dashboard is already information-dense; new metrics need to replace something or fit cleanly in a new section
- **Polling-based workarounds** for data that's available natively via IOReport or SMC

---

## Release Process

Fully automated — no manual DMG building or formula editing.

```bash
# 1. Bump version in Xcode (MARKETING_VERSION in project.pbxproj)
# 2. Update CHANGELOG.md
# 3. Commit and tag
git commit -am "chore: bump version to 2.x.0"
git tag v2.x.0
git push origin main --tags
```

GitHub Actions handles the rest:

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `release.yml` | `v*` tag pushed | Builds DMG on macOS runner, creates GitHub Release, attaches `.dmg` |
| `update-brew.yml` | Release published | Downloads DMG, computes SHA256, commits updated `Casks/macmonitor.rb` |

Users on `brew upgrade --cask macmonitor` get the new version within ~5 minutes.

---

## Support the Project

If MacMonitor is useful to you:

| Platform | Link |
|----------|------|
| Portfolio | [ryyansafar.site](https://ryyansafar.site) |
| GitHub | [github.com/ryyansafar](https://github.com/ryyansafar) |
| Buy Me a Coffee | [buymeacoffee.com/ryyansafar](https://buymeacoffee.com/ryyansafar) |
| PayPal | [paypal.me/ryyansafar](https://www.paypal.com/paypalme/ryyansafar) |
| Razorpay | [razorpay.me/@ryyansafar](https://razorpay.me/@ryyansafar) |

Starring the repo is free and helps MacMonitor get discovered.

---

## Questions?

Open a [GitHub Discussion](../../discussions) for anything that isn't a bug or feature request — architecture ideas, "would this be welcome?", or general questions about how it works.
