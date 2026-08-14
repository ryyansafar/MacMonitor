<div align="center">

<img src="Macmonitor/Assets.xcassets/logo.svg" alt="MacMonitor Logo" width="100" />

# MacMonitor

**The most complete Apple Silicon system monitor that fits in your menu bar.**

Real-time CPU, GPU, memory, battery, power rails, fan, network, and disk —  
all from native kernel sensors. No third-party tools. No dependencies.

<br/>

[![macOS 13+](https://img.shields.io/badge/macOS-13%20Ventura%20%2B-black?logo=apple&logoColor=white&labelColor=000)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%20–%20M5%2B-ff6b35?logo=apple&logoColor=white)](https://www.apple.com/mac/)
[![Version](https://img.shields.io/badge/version-2.0.0-30D158)](../../releases/latest)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/License-MIT-888899.svg)](LICENSE)

<br/>

<table>
  <tr>
    <td><img src="assets/screenshots/dashboard.png" alt="Full dashboard" width="300"/></td>
    <td><img src="assets/screenshots/menubar.png" alt="Menu bar indicator" width="300"/></td>
    <td><img src="assets/screenshots/battery.png" alt="Battery section" width="300"/></td>
  </tr>
  <tr>
    <td align="center"><sub>Full dashboard</sub></td>
    <td align="center"><sub>Menu bar indicator</sub></td>
    <td align="center"><sub>Battery &amp; power</sub></td>
  </tr>
</table>

</div>

---

## Table of Contents

- [What's New in v2.0](#whats-new-in-v20)
- [Features](#features)
- [What is Apple SMC?](#what-is-apple-smc)
- [Data Sources](#data-sources)
- [Installation](#installation)
- [Building from Source](#building-from-source)
- [How It Works](#how-it-works)
- [Sensor Reference](#sensor-reference)
- [Contributing](#contributing)
- [Hardware Tested](#hardware-tested)
- [Roadmap](#roadmap)
- [Support](#support)
- [Acknowledgements](#acknowledgements)
- [License](#license)

---

## What's New in v2.0

> **Full changelog:** [CHANGELOG.md](CHANGELOG.md)

### Native sensors — zero dependencies

MacMonitor 2.0 reads **all hardware data directly from Apple's kernel interfaces**. No mactop, no Homebrew tools, no external binaries — just the same SMC and IOReport APIs that Activity Monitor and TG Pro use under the hood.

| v1.x | v2.0 |
|------|------|
| GPU, temps, and power required `mactop` (separate install) | All sensors read natively via `IOReport` + `SMC` |
| First launch showed "install mactop" banner | Ships fully featured out of the box |
| Chip displayed as "Apple M2" | Displays clean variant: **M2**, **M2 Pro**, **M2 Max**, **M2 Ultra** |
| No CPU die hotspot | Shows both avg temp and **die hotspot (TCMz)** |
| No fan support | Fan RPM shown automatically (hidden on fanless models) |

### New sensor data in this release

- **CPU Die Hotspot** — the absolute peak temperature on the CPU die (SMC key `TCMz`), not just an average. This is the same reading TG Pro labels "CPU Die (Hotspot)".
- **Fan RPM and safe control** — live fan speed plus explicit Automatic and Max Cooling actions. Max Cooling only uses each detected fan's hardware-reported maximum; arbitrary low RPM values are not accepted. The section is hidden automatically on fanless models (MacBook Air).
- **Chip variant** — accurately identified from `machdep.cpu.brand_string` and displayed as "M2 Pro", "M2 Max", etc.
- **Sensor research toolkit** — `sensor-research/` directory includes standalone SMC/HID/IOReport scanners used to discover and verify every sensor key.

---

## Features

### Menu bar indicator

Updates every 2 seconds. One glance tells you if everything is fine.

Settings can also reduce the indicator to a compact CPU-only percentage such as `12%`.

```
● CPU 12%  MEM 47%    →  green dot  — all clear
● CPU 62%  MEM 71%    →  yellow dot — moderate load
● CPU 91%  MEM 87%    →  red dot    — heavy load, open dashboard
```

### Appearance

Choose **Automatic**, **Light**, or **Dark** in Settings. Automatic follows the current
macOS appearance, including system appearance changes while MacMonitor is running.

### Full dashboard (click to open)

| Section | What you see |
|---------|-------------|
| **Header** | Chip variant · thermal state · total system power |
| **CPU** | Overall · E-cluster · P-cluster · S-cluster (M5+) · per-core bars · avg temp · die hotspot · CPU power |
| **GPU** | Usage bar · frequency · temperature · GPU power |
| **Fan** | Live RPM — hidden automatically on fanless models |
| **Memory** | Used / total · DRAM bandwidth (read + write GB/s) · swap |
| **Battery** | Charge % · status · charge rate · adapter watts · cycles · health · mAh · cell temp |
| **Network** | Download / upload (auto-scaled B / KB / MB per second) |
| **Disk I/O** | Read / write throughput (auto-scaled) |
| **Power rails** | CPU · GPU · ANE · DRAM · System (PSTR) · Total |
| **Processes** | Top 8 CPU consumers — name, CPU %, memory |
| **Optimize** | Purge disk cache + quit heavy apps |

### Desktop widget

Runs completely standalone — no background process required.

- **Small** — CPU, GPU, Memory bars + temperatures
- **Medium** — All bars + network speed + power draw

Works on macOS Sonoma and Sequoia desktop, Notification Centre, and Stage Manager.

---

## What is Apple SMC?

The **System Management Controller (SMC)** is a dedicated co-processor embedded in every Apple Mac. It runs independently of the main CPU and is responsible for managing the hardware at a low level — things the operating system itself doesn't directly control.

On Apple Silicon Macs, the SMC handles:

- **Thermal management** — monitoring hundreds of temperature sensors across the CPU, GPU, battery, VRM, SSD, and chassis, and throttling performance to stay within safe limits
- **Power delivery** — managing voltage rails, measuring current draw, and controlling how much power each component receives
- **Fan control** — on Macs with fans, the SMC decides fan speed based on thermal sensor readings
- **Battery management** — tracking cycle count, health, charge rate, and cell temperature
- **Sleep and wake** — handling lid close, power button presses, and low-battery shutdown

MacMonitor reads the SMC directly through Apple's private `IOKit` interface (`IOServiceOpen("AppleSMC")`). Each sensor has a 4-character key (e.g. `TCMz` for CPU die hotspot, `PSTR` for total board power, `F0Ac` for fan speed) and returns a floating-point value in the relevant unit (°C, Watts, RPM, Amps, Volts).

This is the same data that TG Pro, iStatMenus, and macOS's own thermal management subsystem read. MacMonitor exposes it directly in your menu bar.

> For the complete list of SMC keys MacMonitor uses, see [SENSORS.md](SENSORS.md).

---

## Data Sources

MacMonitor pulls from four native macOS kernel interfaces — no third-party tools required:

| Source | Data | Requires privileged helper? |
|--------|------|-----------------------------|
| **Mach kernel** — `host_processor_info` | CPU per-core usage, E/P cluster split | No |
| **Mach kernel** — `vm_statistics64` | Memory used/free/compressed, swap | No |
| **IOReport + SMC + IOHIDEventSystem** | GPU%, freq, CPU/GPU temps, die hotspot, fan RPM, ANE/DRAM/GPU power, DRAM bandwidth | Yes (one-time setup) |
| **IOKit** — `pmset` / `ioreg` | Battery %, cycles, health, charge rate, adapter watts, cell temp | No |

The **privileged helper** (`macmonitor-helper`) is a small compiled binary installed to `/Users/Shared/MacMonitor/`. It runs as root to access IOReport, which requires elevated privileges to sample power data. MacMonitor asks for admin approval once on first launch and never again.

---

## Installation

### Option A — Homebrew (recommended)

```bash
brew tap ryyansafar/macmonitor https://github.com/ryyansafar/MacMonitor
brew install --cask macmonitor
```

MacMonitor appears in your menu bar immediately.

**Auto-update:**
```bash
brew upgrade --cask macmonitor
```

### Option B — One-line installer

```bash
curl -fsSL https://raw.githubusercontent.com/ryyansafar/MacMonitor/main/install.sh | bash
```

Downloads the latest DMG, removes the quarantine flag, installs the privileged helper, and launches MacMonitor.

### Option C — Manual DMG

1. Download **MacMonitor.dmg** from [**Releases**](../../releases/latest)
2. Open the DMG and drag **MacMonitor** to **Applications**
3. Double-click **`Install.command`** inside the DMG to clear the quarantine flag (or run `xattr -dr com.apple.quarantine /Applications/Macmonitor.app` in Terminal)
4. Launch MacMonitor from Applications or Spotlight

> macOS may block the first launch because MacMonitor isn't notarised (no paid Apple Developer account needed to build or distribute it). The `Install.command` script handles this automatically. After the first approved launch, macOS never asks again.

### First launch on macOS Sequoia or later — "Move to Trash / Cancel"

On macOS 15 Sequoia and later, the first-launch Gatekeeper dialog only shows **Move to Trash** and **Cancel** — no "Open Anyway" button in the popup itself. This is expected for any app not notarised through a paid Apple Developer account, MacMonitor included.

To allow MacMonitor:

1. Click **Cancel** on the popup (do **not** click Move to Trash).
2. Open **System Settings → Privacy & Security**.
3. Scroll **all the way down** in the right-hand pane — past every privacy section, past *Allow applications downloaded from*, to the very bottom.
4. You'll see *"Macmonitor" was blocked to protect your Mac.* with an **Open Anyway** button next to it. Click it.
5. Authenticate with Touch ID or your Mac password.
6. A second dialog appears — click **Open**. MacMonitor launches and the menu bar icon appears.

You only do this once per machine. macOS remembers the decision.

For a full walkthrough with troubleshooting, see **[INSTALL.md](./INSTALL.md)**.

---

## Building from Source

**Requirements:**
- Xcode 15+
- Apple Silicon Mac
- macOS 13 Ventura+

```bash
# Clone
git clone https://github.com/ryyansafar/MacMonitor.git
cd MacMonitor

# Open in Xcode
open Macmonitor.xcodeproj
```

In Xcode: select the `Macmonitor` target → **Signing & Capabilities** → set your **Team** to your Apple ID (free account works). Do the same for `MacMonitorWidget`. Press `Cmd+R`.

**Build the privileged helper from the command line:**

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

# Install with root ownership. The app will not grant sudo access to a helper
# or parent directory that can be replaced by an unprivileged user.
sudo install -d -o root -g wheel -m 755 /Users/Shared/MacMonitor
sudo install -o root -g wheel -m 755 \
  /tmp/macmonitor-helper /Users/Shared/MacMonitor/macmonitor-helper
```

---

## How It Works

```
┌──────────────────────────────────────────────────────────────────────┐
│                           MacMonitor.app                              │
│                                                                        │
│  ┌─────────────┐     ┌────────────────────────────────────────────┐   │
│  │ AppDelegate │     │            SystemStatsModel                 │   │
│  │             │     │                                              │   │
│  │ NSStatusItem│◄────│  CPU    ← host_processor_info() [Mach]      │   │
│  │   (2s tick) │     │  MEM    ← vm_statistics64() [Mach]          │   │
│  │             │     │  NET    ← getifaddrs() delta                 │   │
│  │ NSPopover   │     │  DISK   ← IOKit disk stats delta             │   │
│  │  (SwiftUI)  │     │  GPU/⚡ ← macmonitor-helper (IOReport+SMC)  │   │
│  │             │     │  BAT    ← IOKit / ioreg                      │   │
│  └─────────────┘     └────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘

          macmonitor-helper (privileged, runs as root)
          ┌────────────────────────────────────────────┐
          │  IOReport  → CPU/GPU power, DRAM bandwidth │
          │  SMC       → temps, fan RPM, total power   │
          │  IOHIDEventSystem → PMU die temperatures   │
          └────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                    MacMonitorWidget extension                          │
│                                                                        │
│  StatsProvider (TimelineProvider)                                      │
│  CPU  ← host_processor_info() [0.8s two-sample delta]                 │
│  MEM  ← vm_statistics64()                                              │
│  Refreshes every 5 seconds — no background process required           │
└──────────────────────────────────────────────────────────────────────┘
```

**Key design decisions:**

- **No App Sandbox** — required to access Mach kernel APIs and IOReport. This means MacMonitor cannot be submitted to the Mac App Store, but can be freely distributed as a DMG.
- **No third-party dependencies** — everything is read from macOS's own kernel interfaces.
- **Privileged helper pattern** — IOReport power sampling requires root. A minimal helper binary runs with elevated privileges and communicates through stdout JSON. With no arguments it only samples sensors and exits. Its only write commands are `--fan-max` and `--fan-auto`; arbitrary SMC keys and arbitrary RPM values are not exposed.
- **Two-sample delta** — CPU usage, DRAM bandwidth, and power are all rate metrics. MacMonitor takes two samples 100ms apart and computes the delta, giving accurate per-second rates.

---

## Sensor Reference

See **[SENSORS.md](SENSORS.md)** for the complete map of every hardware sensor used:

- All SMC temperature keys (`TCMz`, `TRDX`, `TPMP`, `T5SP`, `TB0T`, …)
- IOReport channels (Energy Model, CPU Stats, GPU Stats, AMC Stats)
- HID PMU die temperature sensors
- Fan speed keys (`F0Ac`, `F1Ac`)
- Battery and power rail keys
- Accuracy cross-validation table vs mactop

---

## Contributing

Contributions are welcome. MacMonitor is intentionally small and dependency-light — the goal is to stay close to the metal.

**Quick start:**

```bash
git clone https://github.com/ryyansafar/MacMonitor.git
cd MacMonitor
open Macmonitor.xcodeproj
```

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for:
- Full development setup
- Architecture overview
- Code style guide
- Sensor contribution guide (adding support for new Mac models)
- PR checklist and review process

**Good first issues:**
- Add a second fan row for dual-fan Macs (Mac Pro, MacBook Pro 16")
- Configurable refresh interval in Settings
- Display memory pressure level from `HOST_VM_INFO64`
- Add global keyboard shortcut to open/close the popover
- Validate sensor keys on M3 / M4 / M3 Pro / M4 Max hardware

---

## Hardware Tested

| Model | Chip | Fan | Status |
|-------|------|-----|--------|
| MacBook Air (M2, 2022) | M2 | No (passive) | ✅ Fully verified |

**Help expand this table.** Run the scanners in `sensor-research/` on your Mac and open a PR — see [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-new-mac-model).

---

## Roadmap

- [ ] M3 / M4 / M5 sensor key validation
- [ ] Dual-fan support (Mac Pro, MacBook Pro 16")
- [ ] Per-core temperature display
- [ ] Configurable refresh rate
- [ ] Global keyboard shortcut
- [ ] Disk space section
- [ ] iCloud / Time Machine integration
- [ ] Sparkle auto-updater (signed binary)

---

## Support

If MacMonitor is useful to you:

| Platform | Link |
|----------|------|
| Portfolio | [ryyansafar.site](https://ryyansafar.site) |
| GitHub | [github.com/ryyansafar](https://github.com/ryyansafar) |
| Buy Me a Coffee | [buymeacoffee.com/ryyansafar](https://buymeacoffee.com/ryyansafar) |
| PayPal | [paypal.me/ryyansafar](https://www.paypal.com/paypalme/ryyansafar) |
| Razorpay | [razorpay.me/@ryyansafar](https://razorpay.me/@ryyansafar) |

Starring the repo also helps a lot — it makes MacMonitor easier to find.

---

## Acknowledgements

- Apple's IOReport, SMC (`AppleSMC`), and IOHIDEventSystem — the native kernel interfaces that power all sensor data in this app
- Apple's Mach kernel (`host_processor_info`, `vm_statistics64`) — for dependency-free CPU and memory sampling
- [mactop](https://github.com/metaspartan/mactop) by [@metaspartan](https://github.com/metaspartan) — used as an independent cross-validation reference during sensor research for v2.0

---

## License

[MIT](LICENSE) — Copyright © 2025–2026 MacMonitor Contributors.

Free to use, modify, fork, and distribute. Attribution appreciated but not required.

---

<div align="center">

Built for Apple Silicon. Reads from the metal.

</div>
