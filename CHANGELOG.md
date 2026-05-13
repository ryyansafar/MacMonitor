# Changelog

All notable changes to MacMonitor are documented here.

Format: [Semantic Versioning](https://semver.org) — `MAJOR.MINOR.PATCH`  
Dates: ISO 8601 (YYYY-MM-DD)

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
