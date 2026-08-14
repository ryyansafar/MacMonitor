# Changelog

All notable changes to MacMonitor are documented here.

Format: [Semantic Versioning](https://semver.org) — `MAJOR.MINOR.PATCH`  
Dates: ISO 8601 (YYYY-MM-DD)

---

## Unreleased

### Added

- **Per-process I/O rankings** — the main dashboard's Top Processes section can now
  switch between CPU/memory, disk read/write rates, and network download/upload rates.
  Sampling runs on a dedicated serial queue and does not add process sampling to the widget.

## [2.0.5] — 2026-08-06

### The "Widget Actually Exists" Release

Ships the desktop widget, which had been dead code in the repo since 2.0.0, adds the
first real customization options, and fixes code signing — every release before this
one shipped unsigned.

### Added

- **Compact CPU-only menu bar mode** — optionally show just the live CPU percentage
  (for example, `12%`) instead of the full CPU, temperature, and memory label. Opt-in,
  so the existing detailed indicator stays the default.
  ([#14](https://github.com/ryyansafar/MacMonitor/pull/14), thanks @Fletcher-Alderton)
- **Light appearance** — the dashboard, settings, and welcome window now use adaptive
  system colours and remain legible in both light and dark appearances.
  ([#14](https://github.com/ryyansafar/MacMonitor/pull/14), thanks @Fletcher-Alderton)
- **Automatic appearance switching** — Settings offers Automatic, Light, and Dark.
  Automatic follows the current macOS appearance as it changes.
  ([#14](https://github.com/ryyansafar/MacMonitor/pull/14), thanks @Fletcher-Alderton)
- **Desktop widget** — `MacMonitorWidget.swift` shipped in the repo since 2.0.0 but was
  in no build target, so it never compiled and the "Desktop Widget" toggle in Settings
  pointed at nothing. It is now a real app-extension target embedded in the app bundle.
  Add it via right-click the desktop → Edit Widgets → MacMonitor. Small and medium sizes,
  showing CPU, memory and thermal state. Works on macOS 14+ on the desktop and in
  Notification Center on macOS 13.

- **Widget refreshes about every 2 seconds** while MacMonitor is running, with rolling
  digit animation on the readings. Widgets are snapshot-based, so this is as close to
  live as WidgetKit allows — the dashboard remains the real-time view.

### Changed

- **Settings controls all do something now.** "Desktop Widget" was a switch writing a
  preference nothing read; macOS owns whether a widget is placed, so it is now a
  "Refresh Now" button plus accurate placement instructions. "Menu Bar App" was also
  dead and was removed rather than left as a switch that lies — MacMonitor is a menu bar
  app, so hiding the icon would remove the only way to reach it, including Settings.

### Fixed

- **Clicking outside the dashboard collapses it**, the same as clicking the menu bar icon
  again. `NSPopover.behavior = .transient` is meant to handle this, but the app runs as
  an accessory: a click in another application is delivered to that application and never
  reaches MacMonitor, so the dashboard just stayed open.
- **Done button in Settings now closes the window** — Settings opened from the menu bar
  passed the view a read-only `.constant(true)` binding, so Done wrote to nothing and the
  red close button was the only way out. Opening Settings repeatedly also stacked a new
  window each time; it now reuses one.
- **Widget spacing** — the medium layout left a large dead gap down the left column, and
  the small layout had the same problem between the bars and the memory line. Both now
  distribute space between rows instead of pushing all slack into one spacer.
- **Releases are signed again** — `build-dmg.sh` embedded the privileged helper *after*
  `-exportArchive`, invalidating the bundle seal, so shipped builds reported "code object
  is not signed at all". Harmless while the app was a single executable, but it blocked
  the new widget entirely, since macOS refuses to load an app extension inside an
  invalidly signed host. The bundle is now re-signed inside-out and verified with
  `codesign --verify --deep --strict`. **This is the first signed MacMonitor release.**
- **Dashboard crash during window animation** — dismissing the popover synchronously from
  a window-geometry notification ran inside a CoreAnimation transaction and could
  over-release the window transform animation, seen as an `EXC_BAD_ACCESS` in
  `objc_release`. Dismissal now defers to the next main-queue pass.

---

## [2.0.4] — 2026-08-05

### Fixed

- **Dashboard no longer closes itself every time a value updates** — a regression
  introduced by the 2.0.3 popover positioning fix made the dashboard effectively
  impossible to use. The menu bar item is variable-width and its title is rewritten on
  every metrics tick, so the label changes width whenever a reading gains or loses a
  digit. Because menu bar items are laid out from the right, that width change shifts
  the item's window horizontally — and the 2.0.3 code treated *any* movement of the
  anchor as "the menu bar retracted" and dismissed the popover. It now only dismisses on
  a vertical move, which is what actually happens when the menu bar hides. The
  full-screen fix from 2.0.3 (#11) still applies.

  Anyone on 2.0.3 should update.

---

## [2.0.3] — 2026-08-05

### Fixed

- **Popover no longer jumps off-screen in full-screen mode** — with the menu bar
  auto-hidden, scrolling inside the dashboard could make it flash and jump to the
  top-right corner with its top edge clipped. The popover is anchored to the menu bar
  item, and when the menu bar retracted the anchor slid off-screen and took the popover
  with it. It now dismisses when its anchor moves or leaves the screen. (#11)
- **CPU temperature no longer includes SSD sensors** — the CPU average collected every
  `T[pes]*` SMC key, which swept in `Ts1P` and `TsOP`. Those are SSD proximity sensors
  sitting around 31–33 °C that barely move under load, pulling the reported CPU
  temperature roughly 0.7 °C low at idle and further under load.

### Documentation

- **Added the `sensor-research/` toolkit** — referenced from the README, `SENSORS.md`,
  `CONTRIBUTING.md` and this changelog since 2.0.0, but never actually committed, so no
  one could run the scanners to validate sensor keys on their own hardware. (#13)
- **Clarified VRM vs memory sensors in `SENSORS.md`** — the VRM table had no description
  column, so keys like `TVMr` appeared unexplained, and `TVm0` was documented twice with
  conflicting meanings. SMC keys are case-sensitive: `TVm0` is the memory die, `TVM0` and
  `TVMr` are voltage regulators. Also notes the expected VRM temperature range, which
  runs well above die temperature by design. (#12)
- **Corrected the `Ts0K`–`Ts0Y` range** — previously listed as an "SSD thermal array"
  while the same keys were simultaneously documented as CPU/SoC complex sensors. They
  are CPU/SoC sensors.

---

## [2.0.2] — 2026-05-30

### The "Brew Install Actually Works" Release

A point release that fixes the Homebrew Cask installation failure reported in
[#4](https://github.com/ryyansafar/MacMonitor/issues/4), plus three contributor
fixes for Apple Silicon hardware detection on newer chips.

### Fixed

- **Homebrew install no longer fails with `macmonitor-helper: No such file or directory`** —
  the privileged helper sources existed at `helper/macmonitor-helper.m` but were never
  compiled or bundled. The Cask `postflight` tried to `cp` a binary that the released DMG
  did not contain. `scripts/build-dmg.sh` now compiles `macmonitor-helper` from source and
  embeds it in `Macmonitor.app/Contents/MacOS/` before the DMG is sealed, so `brew install
  --cask macmonitor` completes cleanly. Fixes [#4](https://github.com/ryyansafar/MacMonitor/issues/4).
- **Per-core CPU labels (`C10`–`C17`) no longer wrap to two lines** — widened the label
  column from 16 to 22 pt with `.lineLimit(1)` + `.fixedSize(...)` so two-digit core indices
  stay on one row. ([#5](https://github.com/ryyansafar/MacMonitor/pull/5), thanks @daricliu)
- **GPU core count detection on M5+ Macs** — `ioreg -rc AGXAcceleratorG14` was hardcoded,
  so newer chips reported 0 GPU cores. Now iterates `AGXAccelerator{G17X,G17,…,G14}` and
  falls back to `system_profiler SPDisplaysDataType`. Verified on M5 Max (40 GPU cores via
  `AGXAcceleratorG17X`). ([#6](https://github.com/ryyansafar/MacMonitor/pull/6), thanks @daricliu)
- **Disk I/O showing 0 KB/s when first IOBlockStorageDriver had zero counters** —
  `diskCumulative()` used `firstIntegerMatch` which grabbed only the first `"Bytes (Read)"`
  occurrence. Now sums all `IOBlockStorageDriver` statistics lines and explicitly excludes
  child `IOMedia`/APFS entries so traffic isn't double-counted.
  ([#8](https://github.com/ryyansafar/MacMonitor/pull/8), thanks @daricliu)

---

## [2.0.1] — 2026-05-13

### The "Temperatures Actually Work" Release

A point release that fixes the showstopper bug where every CPU and GPU temperature read
returned zero on Apple Silicon. If you installed 2.0.0 and saw `--°` in the menu bar or
empty thermal panels in the dashboard, upgrade to 2.0.1.

### Fixed

- **Apple Silicon temperatures now read correctly** — `SMCGetFloatValue` only understood
  the `flt` (IEEE 754 float) data type. Every modern Apple Silicon temperature sensor
  (`Tp*`, `Te*`, `Tg*`, `TCMz`) is encoded as `sp78` — signed fixed-point 7.8 — and was
  silently returning 0. Added an `sp78` decoder (two-byte big-endian → divide by 256) and
  taught `isTemperatureSMCKey` to accept both formats. CPU temp, GPU temp, CPU die hotspot,
  and battery temp now display on M1 through M5 Macs. Fixes [#2](https://github.com/ryyansafar/MacMonitor/issues/2).
- **Long shell output no longer deadlocks the sampler** — `shellResult` and `shellStatic`
  waited on `waitUntilExit()` before draining `stdout`/`stderr` pipes. On a busy Mac, `ps
  -axo … -r` and `ioreg -l` exceed the ~16-64 KB pipe buffer; the child blocks on write
  while we block on wait → permanent hang. Both helpers now read each pipe on a background
  queue *before* the wait, eliminating the deadlock that caused `fetchNativeMetrics` to
  appear stuck after the first tick.
- **Homebrew install no longer fails on a placeholder checksum** — the in-repo
  `Casks/macmonitor.rb` shipped with `PLACEHOLDER_SHA256_UPDATED_AUTOMATICALLY_BY_CI`
  because the release workflow only updated a separate tap repo, not the cask in this
  repo that the README's `brew tap` command points to. Replaced with the real SHA-256 and
  fixed the release workflow to commit cask updates back to this repo going forward.
  Fixes [#3](https://github.com/ryyansafar/MacMonitor/issues/3).

### Added

- **Open at Login toggle** — Settings now exposes a switch that registers MacMonitor with
  `SMAppService` so it launches automatically at login. State is persisted in
  `UserDefaults` and restored on every launch. No login items configuration required.
- **Temperature in the menu bar** — when the active CPU temperature is available it now
  appears next to the CPU percentage (e.g. `🟡 CPU 41% 48°  MEM 76%`). Hidden when the
  reading is unavailable so unsupported machines aren't penalised with `--°`.

### Changed

- **Release workflow no longer installs `mactop`** — leftover step from the pre-2.0 era.
  v2.0 reads sensors natively; the runner doesn't need `mactop` to build the DMG.
- **Release workflow now updates the in-repo `Casks/macmonitor.rb`** in addition to the
  separate `homebrew-macmonitor` tap, so both `brew tap ryyansafar/macmonitor
  https://github.com/ryyansafar/MacMonitor` (per the README) and `brew tap
  ryyansafar/homebrew-macmonitor` work after every release.
- **Cask postflight `cp` path corrected** — `MacMonitor.app/Contents/MacOS/macmonitor-helper`
  → `Macmonitor.app/...` to match the actual product name; previously relied on the
  case-insensitive HFS+ default and would silently fail on case-sensitive volumes.

---

## [2.0.0] — 2026-04-06

### The Native Sensors Release

MacMonitor 2.0 removes the dependency on `mactop` entirely. Every sensor value — GPU, temperatures, power rails, DRAM bandwidth — is now read directly from Apple's own kernel interfaces. The result is faster startup, fewer moving parts, and sensor data that's available out of the box on a clean macOS install.

### Added

- **CPU Die Hotspot** — new temperature reading via SMC key `TCMz`. This is the absolute hottest point on the CPU die, the same value TG Pro labels "CPU Die (Hotspot)". Displayed alongside the existing average temperature in the CPU section.
- **Fan RPM** — live fan speed via SMC key `F0Ac`. The fan section appears automatically when a fan is present and is hidden on fanless models (e.g. MacBook Air). Dual-fan Macs (`F1Ac`) are on the roadmap.
- **Chip variant display** — the header now shows the exact chip variant: **M2**, **M2 Pro**, **M2 Max**, **M2 Ultra** (stripped from `machdep.cpu.brand_string`). Previously showed the raw "Apple M2" string.
- **SENSORS.md** — complete sensor reference documenting every SMC key, IOReport channel, and HID PMU sensor used, with live values and mactop cross-validation table.
- **sensor-research/** directory — standalone scanner tools (`what_is_accurate`, `hid_scanner`, `global_scanner`, `final_logger`) used to discover and verify sensor keys. Contributed hardware data goes here.

### Changed

- **Native sensor stack replaces mactop** — `IOReportWrapper` now reads all Energy Model channels (`CPU Energy`, `GPU Energy`, `ANE Energy`, `DRAM Energy`) via a persistent IOReport subscription, using proper delta sampling and unit-aware watt conversion. CPU Stats and GPU Stats channels provide frequency and residency data the same way.
- **CPU temperature uses SMC key scan** — `IOReportWrapper` enumerates all `Tp*` and `Te*` SMC keys at init time and averages them for the CPU temperature. Falls back to HID PMU tdie sensors if SMC keys are unavailable.
- **GPU temperature uses `TRDX`** — the primary GPU die hotspot key, with `Tg0f` and `Tg0n` as fallbacks.
- **System power reads `PSTR`** — SMC key `PSTR` (Total Board Power) provides the most accurate "wall" power reading, matching what TG Pro reports.
- **`mactopReady`/`mactopMissing` renamed** to `nativeReady`/`helperMissing` in `SystemStatsModel`. The banner now reads "System helper not installed" instead of "mactop not found".
- **WelcomeView** — "GPU & Temps" description updated to "Native SMC + IOReport sensors — no third-party dependencies."
- **Homebrew cask** — removed the `postflight` block that installed mactop. Updated sudoers path from `macmonitor` to `macmonitor-helper`. Version bumped to 2.0.0.
- **README** — complete rewrite with SMC explainer, updated architecture diagram, hardware tested table, roadmap, and sensor reference link.
- **CONTRIBUTING.md** — updated setup instructions (no mactop step), added sensor contribution guide, updated architecture overview.

### Removed

- **mactop dependency** — MacMonitor no longer shells out to `mactop --headless`. The `mactop` binary is no longer installed, referenced, or required.

### Fixed

- `IOReportWrapper` now correctly handles both `mJ` and `nJ` unit labels for Energy Model channels, ensuring accurate watt conversions across all chip generations.
- M5+ chips that block `AMC Stats` now fall back to `PMP` group for DRAM bandwidth without requiring a separate subscription.

---

## [1.1.5] — 2026-04-03

### Fixed

- Strip quarantine attribute from downloaded DMG and installed app automatically during in-app update flow.

---

## [1.1.4] — 2026-04-02 *(skipped — build number only)*

---

## [1.1.3] — 2026-04-02

### Fixed

- Corrected `MARKETING_VERSION` mismatch between Info.plist and project file that caused the in-app update check to loop.

---

## [1.1.2] — 2026-04-01

### Fixed

- Temperature reading reliability — fallback logic improved when mactop JSON is malformed or returns partial data.
- Checkout action updated to `@v5` in CI workflow.

---

## [1.1.1] — 2026-03-31

### Fixed

- Bump build number to 2 for Homebrew cask v1.1.0 release compatibility.

---

## [1.1.0] — 2026-03-30

### Added

- In-app update checker — the gear icon shows an orange dot when a new version is available. Click to download, install, and relaunch without leaving the app.
- Support link in the widget footer.
- Logo added to app icon and README.
- `Install.command` helper script — double-clicking it in the DMG removes the quarantine flag automatically.

### Fixed

- BSD-compatible `sed -i ''` in Homebrew cask CI update step (was breaking on macOS runners).

---

## [1.0.0] — 2026-03-28

### Initial Release

- Menu bar indicator with live health dot (green / yellow / red)
- Full dark-mode dashboard popover with CPU, GPU, Memory, Battery, Network, Disk, Power, and Processes sections
- Desktop widget (Small + Medium sizes) running standalone via Mach kernel APIs
- GPU, temps, and power via mactop (v1.x approach)
- Battery detail: cycle count, health %, charge rate, adapter watts, cell temperature
- Homebrew cask distribution via `ryyansafar/macmonitor` tap
- Automated CI: build → DMG → GitHub Release → Homebrew formula update

---

[2.0.0]: https://github.com/ryyansafar/MacMonitor/compare/v1.1.5...v2.0.0
[1.1.5]: https://github.com/ryyansafar/MacMonitor/compare/v1.1.3...v1.1.5
[1.1.3]: https://github.com/ryyansafar/MacMonitor/compare/v1.1.1...v1.1.3
[1.1.1]: https://github.com/ryyansafar/MacMonitor/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/ryyansafar/MacMonitor/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ryyansafar/MacMonitor/releases/tag/v1.0.0
