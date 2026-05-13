import Foundation
import AppKit
import Darwin
import Combine
import OSLog

// MARK: - Types

struct ProcInfo: Identifiable {
    let id   = UUID()
    let pid:  Int
    let name: String
    let cpu:  Double
    let mem:  Int64
}

// MARK: - Model

class SystemStatsModel: ObservableObject {
    private static let logger = Logger(subsystem: "rybo.Macmonitor", category: "metrics")

    // CPU
    @Published var cpuUsage:    Int     = 0
    @Published var perCoreCPU: [Double] = []
    @Published var eCoresPct:   Int     = 0
    @Published var pCoresPct:   Int     = 0
    @Published var eCoresMHz:   Int     = 0
    @Published var pCoresMHz:   Int     = 0
    @Published var cpuTemp:     Double  = 0
    @Published var cpuPower:    Double  = 0

    // GPU
    @Published var gpuUsage:    Int     = 0
    @Published var gpuMHz:      Int     = 0
    @Published var gpuTemp:     Double  = 0
    @Published var gpuPower:    Double  = 0

    // Power rails
    @Published var anePower:    Double  = 0
    @Published var dramPower:   Double  = 0
    @Published var sysPower:    Double  = 0
    @Published var totalPower:  Double  = 0
    @Published var dramBW:      Double  = 0

    // M5+ Super cluster (exposed so PopoverView can show it when present)
    @Published var sClusterPct: Int     = 0
    @Published var sClusterMHz: Int     = 0

    // Memory
    @Published var memUsed:     Int64   = 0
    @Published var memTotal:    Int64   = 0
    @Published var memPct:      Int     = 0
    @Published var swapUsed:    Int64   = 0
    @Published var swapTotal:   Int64   = 0

    // Network
    @Published var netInBps:    Int64   = 0
    @Published var netOutBps:   Int64   = 0

    // Disk
    @Published var diskReadKBs: Double  = 0
    @Published var diskWriteKBs:Double  = 0

    // Battery — every field
    @Published var batteryPct:       Int     = 0
    @Published var batteryCharging:  Bool    = false
    @Published var batteryCharged:   Bool    = false
    @Published var batteryOnAC:      Bool    = true
    @Published var batteryTimeLeft:  String  = "--:--"
    @Published var batteryTempC:     Double  = 0
    @Published var batteryCycles:    Int     = 0
    @Published var batteryHealthPct: Int     = 100
    @Published var batteryCurrentMAh:Int     = 0
    @Published var batteryMaxMAh:    Int     = 0
    @Published var batteryDesignMAh: Int     = 0
    @Published var adapterWatts:     Double  = 0
    @Published var chargingWatts:    Double  = 0

    // System info
    @Published var thermalState: String = "Normal"
    @Published var chipName:     String = "Apple Silicon"  // e.g. "M2", "M2 Pro", "M2 Max"
    @Published var eCoreCount:   Int    = 0
    @Published var pCoreCount:   Int    = 0
    @Published var gpuCoreCount: Int    = 0

    // Fan (0 = fanless model, e.g. MacBook Air)
    @Published var fanRPM:       Int    = 0

    // CPU die hotspot — TCMz, the absolute peak temperature on the CPU die.
    // This is the value TG Pro shows as "CPU Die (Hotspot)".
    @Published var cpuDieHotspot: Double = 0

    @Published var topProcs: [ProcInfo] = []
    @Published var nativeReady           = false
    @Published var helperMissing         = false

    // Private
    private var smcConn: io_connect_t     = 0
    private var nativeMetricsInFlight     = false
    private var tickInFlight              = false
    private var prevCPUTicks: [[UInt32]] = []
    private var prevNetIn:    Int64 = 0   // 0 = unseeded (skip first rate calc)
    private var prevNetOut:   Int64 = 0
    private var prevDiskReadBytes:  Int64 = 0
    private var prevDiskWriteBytes: Int64 = 0
    private var diskSeeded            = false  // true after first diskCumulative sample
    private var diskInFlight          = false  // prevent concurrent ioreg calls piling up
    private var prevTickTime: Date  = Date()
    private var batterySampleCountdown    = 0
    private var timer: Timer?
    private var diskTimer: Timer?          // independent timer — keeps ioreg off samplerQueue
    private let samplerQueue = DispatchQueue(label: "rybo.Macmonitor.sampler", qos: .utility)
    private let helperPath = "/Users/Shared/MacMonitor/macmonitor-helper"
    private let helperSudoersPath = "/etc/sudoers.d/macmonitor-helper"
    private var helperBootstrapInFlight = false

    // MARK: - Start

    func startMonitoring() {
        smcConn = SMCOpen()
        _ = sampleCPU()      // fast Mach call — OK on main thread
        prevTickTime = Date()

        // Start main 2-second tick timer immediately — app is responsive at launch.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // Disk I/O is sampled via ioreg which can take 1-5+ seconds.
        // Run it on its own independent timer so it NEVER blocks samplerQueue.
        // Fires every 6 s; first sample seeds the baseline (shows 0 rate).
        diskTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.tickDisk()
        }
        tickDisk()   // seed immediately (async, doesn't block)

        // Static system info (includes one ioreg call for GPU core count).
        // Run on a background queue so it doesn't block samplerQueue either.
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.loadStaticSystemInfo()
        }

        ensurePrivilegedHelperAccess()
        fetchNativeMetrics()
        fetchBattery()
    }

    // MARK: - Tick

    private func tick() {
        guard !tickInFlight else { return }
        tickInFlight = true

        samplerQueue.async { [weak self] in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async { self.tickInFlight = false }
            }

            let (cpu, cores) = self.sampleCPU()
            let (mUsed, mTot) = self.sampleMemory()
            let (sUsed, sTot) = self.sampleSwap()
            let (ni, no)      = self.netCumulative()

            let dt     = max(Date().timeIntervalSince(self.prevTickTime), 0.001)
            // Guard against first tick where prevNetIn is 0 (unseeded).
            // That would make inBps = totalBytesSinceBoot / 2s — wildly wrong.
            let netSeeded = self.prevNetIn > 0
            let inBps  = netSeeded ? Int64(Double(ni - self.prevNetIn)  / dt) : 0
            let outBps = netSeeded ? Int64(Double(no - self.prevNetOut) / dt) : 0
            self.prevNetIn    = ni
            self.prevNetOut   = no
            self.prevTickTime = Date()

            // Disk I/O is handled by diskTimer (every 6 s) on a background queue
            // to avoid ioreg blocking samplerQueue. Nothing to do here.

            self.batterySampleCountdown -= 1
            let shouldFetchBattery = self.batterySampleCountdown <= 0
            if shouldFetchBattery { self.batterySampleCountdown = 5 }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cpuUsage    = Int(cpu.rounded())
                self.perCoreCPU  = cores
                self.memUsed     = mUsed
                self.memTotal    = mTot
                self.memPct      = mTot > 0 ? Int(mUsed * 100 / mTot) : 0
                self.swapUsed    = sUsed
                self.swapTotal   = sTot
                self.netInBps    = max(0, inBps)
                self.netOutBps   = max(0, outBps)
                self.thermalState = Self.currentThermalState()
            }

            self.fetchNativeMetrics()
            if shouldFetchBattery { self.fetchBattery() }
        }
    }

    // MARK: - Disk I/O (independent timer — never blocks samplerQueue)

    // Called from diskTimer on the main thread every 6 s.
    // Runs ioreg on a global background queue so samplerQueue stays clean.
    // All disk state is written on the main thread only.
    private func tickDisk() {
        // Guard: ioreg can take longer than the 6 s timer interval.
        // Without this, concurrent ioreg processes pile up and waste CPU/memory.
        guard !diskInFlight else { return }
        diskInFlight = true

        let prevRead  = prevDiskReadBytes
        let prevWrite = prevDiskWriteBytes
        let seeded    = diskSeeded
        diskSeeded = true   // mark seeded so next call computes a delta

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let (readBytes, writeBytes) = self.diskCumulative()
            // First call seeds baseline — show 0 so we don't display boot-time totals.
            let readKBs  = seeded ? max(0, Double(readBytes  - prevRead)  / 6.0 / 1024.0) : 0
            let writeKBs = seeded ? max(0, Double(writeBytes - prevWrite) / 6.0 / 1024.0) : 0
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.prevDiskReadBytes  = readBytes
                self.prevDiskWriteBytes = writeBytes
                self.diskReadKBs        = readKBs
                self.diskWriteKBs       = writeKBs
                self.diskInFlight       = false
            }
        }
    }

    // MARK: - CPU (Mach kernel)

    private func sampleCPU() -> (Double, [Double]) {
        var numCPUs:   natural_t               = 0
        var rawInfo:   processor_info_array_t? = nil
        var infoCount: mach_msg_type_number_t  = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &numCPUs, &rawInfo, &infoCount) == KERN_SUCCESS,
              let rawInfo = rawInfo else { return (0, []) }

        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: rawInfo),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let n = Int(numCPUs)
        var cur = [[UInt32]](repeating: [0,0,0,0], count: n)
        for i in 0..<n {
            let b = i * Int(CPU_STATE_MAX)
            cur[i][0] = UInt32(bitPattern: rawInfo[b + Int(CPU_STATE_USER)])
            cur[i][1] = UInt32(bitPattern: rawInfo[b + Int(CPU_STATE_SYSTEM)])
            cur[i][2] = UInt32(bitPattern: rawInfo[b + Int(CPU_STATE_IDLE)])
            cur[i][3] = UInt32(bitPattern: rawInfo[b + Int(CPU_STATE_NICE)])
        }

        var perCore = [Double](); var sumUsed = 0.0; var sumTotal = 0.0
        for i in 0..<n {
            let p = prevCPUTicks.count > i ? prevCPUTicks[i] : [0,0,0,0]
            let user = Double(cur[i][0] &- p[0])
            let sys  = Double(cur[i][1] &- p[1])
            let idle = Double(cur[i][2] &- p[2])
            let nice = Double(cur[i][3] &- p[3])
            let all  = user + sys + idle + nice
            let used = user + sys + nice
            perCore.append(all > 0 ? (used / all * 100) : 0)
            sumUsed += used; sumTotal += all
        }
        prevCPUTicks = cur
        return (sumTotal > 0 ? sumUsed / sumTotal * 100 : 0, perCore)
    }

    // MARK: - Memory (Mach kernel)

    private func sampleMemory() -> (used: Int64, total: Int64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard kr == KERN_SUCCESS else { return (0, total) }
        let page  = Int64(vm_kernel_page_size)
        let used  = (Int64(stats.active_count) + Int64(stats.wire_count)
                   + Int64(stats.compressor_page_count)) * page
        return (min(max(used, 0), total), total)
    }

    private func sampleSwap() -> (used: Int64, total: Int64) {
        let output = shell("/usr/sbin/sysctl", ["vm.swapusage"])
        let total = Self.firstSizeMatch(in: output, pattern: #"total = ([0-9.]+[KMGTP]i?)"#)
        let used = Self.firstSizeMatch(in: output, pattern: #"used = ([0-9.]+[KMGTP]i?)"#)
        return (used, total)
    }

    // MARK: - Network cumulative

    private func netCumulative() -> (rx: Int64, tx: Int64) {
        let out = shell("/usr/sbin/netstat", ["-ib"])
        var rx = Int64(0), tx = Int64(0), seen = Set<String>()
        for line in out.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 10 else { continue }
            let name = String(cols[0])
            guard name.hasPrefix("en"), !seen.contains(name) else { continue }
            seen.insert(name)
            if let r = Int64(cols[6]), let t = Int64(cols[9]) { rx += r; tx += t }
        }
        return (rx, tx)
    }

    private func diskCumulative() -> (readBytes: Int64, writeBytes: Int64) {
        let output = shell("/usr/sbin/ioreg", ["-r", "-c", "IOBlockStorageDriver", "-l"])
        let read = Self.firstIntegerMatch(in: output, pattern: #""Bytes \(Read\)"\s*=\s*(\d+)"#)
        let write = Self.firstIntegerMatch(in: output, pattern: #""Bytes \(Write\)"\s*=\s*(\d+)"#)
        return (read, write)
    }

    // MARK: - Battery (pmset + ioreg)

    private func fetchBattery() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            // ── pmset -g batt ──
            let batt = self.shell("/usr/bin/pmset", ["-g", "batt"])
            let onAC      = batt.contains("AC Power")
            let charging  = batt.contains("charging") && !batt.contains("discharging")
            let charged   = batt.contains("charged") || batt.contains("finishing charge")
            let pctMatch  = batt.range(of: #"(\d+)%"#, options: .regularExpression)
            let pct       = pctMatch.map { Int(batt[$0].dropLast()) ?? 0 } ?? 0
            let timeMatch = batt.range(of: #"\d+:\d+"#, options: .regularExpression)
            let timeLeft  = timeMatch.map { String(batt[$0]) } ?? "--:--"

            // ── pmset -g adapter ──
            // macOS outputs "Wattage = 35W" (not "Watts: 35"), so match accordingly.
            let adapterOut = self.shell("/usr/bin/pmset", ["-g", "adapter"])
            let adWatts: Double
            if let r = adapterOut.range(of: #"Wattage\s*=\s*(\d+(?:\.\d+)?)W?"#, options: .regularExpression) {
                let token = adapterOut[r]
                    .components(separatedBy: "=").last?
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "W"))
                adWatts = Double(token ?? "") ?? 0
            } else {
                adWatts = 0
            }

            // ── ioreg (cycle count, health, temp, capacity) ──
            let ioreg = self.shell("/usr/sbin/ioreg",
                                   ["-l", "-n", "AppleSmartBattery", "-r"])

            func ioInt(_ key: String) -> Int {
                let pattern = "\"\(key)\" = (\\d+)"
                if let r = ioreg.range(of: pattern, options: .regularExpression) {
                    return Int(ioreg[r].components(separatedBy: "= ").last ?? "") ?? 0
                }
                return 0
            }

            let cycles  = ioInt("CycleCount")
            // MaxCapacity and CurrentCapacity are percentages (0–100), NOT mAh.
            // AppleRawMaxCapacity and AppleRawCurrentCapacity are the actual mAh values.
            // NominalChargeCapacity is the learned full-charge capacity in mAh.
            // DesignCapacity is the factory-rated capacity in mAh.
            let rawMaxCap  = ioInt("AppleRawMaxCapacity")   // mAh — actual full-charge capacity
            let nomCap     = ioInt("NominalChargeCapacity") // mAh — fallback for maxCap
            let desCap     = ioInt("DesignCapacity")        // mAh — factory rated
            let rawCurCap  = ioInt("AppleRawCurrentCapacity") // mAh — actual current charge
            // Use AppleRawMaxCapacity if available; fall back to NominalChargeCapacity.
            let maxCapMAh  = rawMaxCap > 0 ? rawMaxCap : nomCap
            let rawTemp = ioInt("Temperature")           // in 0.01°C
            let battTemp = Double(rawTemp) / 100.0

            // Charging current (mA) × voltage (mV) → watts
            let voltage    = Double(ioInt("Voltage")) / 1000.0        // V
            let amperage   = abs(Double(ioInt("Amperage"))) / 1000.0  // A
            let chrgWatts  = voltage * amperage

            let health = desCap > 0 ? Int(Double(maxCapMAh) / Double(desCap) * 100) : 100

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.batteryPct        = pct
                self.batteryCharging   = charging
                self.batteryCharged    = charged
                self.batteryOnAC       = onAC
                self.batteryTimeLeft   = timeLeft
                self.batteryTempC      = battTemp
                self.batteryCycles     = cycles
                self.batteryHealthPct  = min(100, health)
                self.batteryCurrentMAh = rawCurCap
                self.batteryMaxMAh     = maxCapMAh
                self.batteryDesignMAh  = desCap
                self.adapterWatts      = adWatts
                self.chargingWatts     = chrgWatts
            }
        }
    }

    // MARK: - Native GPU / Temps / Clusters / Power

    private func fetchNativeMetrics() {
        guard !nativeMetricsInFlight else { return }
        nativeMetricsInFlight = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            defer { DispatchQueue.main.async { self.nativeMetricsInFlight = false } }

            let nativeData = IOReportWrapper.fetchIOReportData(withSMC: self.smcConn)
            let helperData = self.fetchHelperMetrics()
            let pData = self.mergeMetrics(primary: helperData, fallback: nativeData)
            let sysP = SMCGetFloatValue(self.smcConn, "PSTR")
            let procs = self.sampleTopProcesses()
            fputs("[metrics] cpuTemp=\(pData.cpuTemp) gpuTemp=\(pData.gpuTemp) cpuPow=\(pData.cpuPower) gpuPow=\(pData.gpuPower) gpuPct=\(pData.gpuUsage) gpuMHz=\(pData.gpuFreqMHz) ePct=\(pData.eClusterActive) eMHz=\(pData.eClusterFreqMHz) pPct=\(pData.pClusterActive) pMHz=\(pData.pClusterFreqMHz) dramR=\(pData.dramReadBytes) dramW=\(pData.dramWriteBytes)\n", stderr)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cpuTemp        = pData.cpuTemp > 0        ? pData.cpuTemp        : self.cpuTemp
                self.cpuDieHotspot  = pData.cpuDieHotspot > 0  ? pData.cpuDieHotspot  : self.cpuDieHotspot
                self.gpuTemp        = pData.gpuTemp > 0        ? pData.gpuTemp        : self.gpuTemp
                self.fanRPM         = Int(pData.fanRPM)
                
                self.cpuPower  = pData.cpuPower
                self.gpuPower  = pData.gpuPower
                self.anePower  = pData.anePower
                self.dramPower = pData.dramPower
                // systemPower: prefer SMC PSTR (wall input power); IOReport doesn't expose it
                self.sysPower  = sysP > 0 ? sysP : (pData.systemPower > 0 ? pData.systemPower : 0)
                self.totalPower = self.cpuPower + self.gpuPower + self.anePower + self.dramPower

                self.gpuUsage  = Int(pData.gpuUsage.rounded())
                self.gpuMHz    = Int(pData.gpuFreqMHz)
                self.eCoresPct = Int(pData.eClusterActive.rounded())
                self.pCoresPct = Int(pData.pClusterActive.rounded())
                self.eCoresMHz = Int(pData.eClusterFreqMHz)
                self.pCoresMHz = Int(pData.pClusterFreqMHz)
                self.sClusterPct = Int(pData.sClusterActive.rounded())
                self.sClusterMHz = Int(pData.sClusterFreqMHz)

                // DRAM bandwidth: bytes transferred / sample interval (0.1 s) → GB/s
                let totalDramBytes = pData.dramReadBytes + pData.dramWriteBytes
                self.dramBW = Double(totalDramBytes) / 0.1 / 1_000_000_000

                self.topProcs = procs

                self.nativeReady    = true
                self.helperMissing  = false
            }
        }
    }

    private func sampleTopProcesses() -> [ProcInfo] {
        let out = shell("/bin/ps", ["-axo", "%cpu,rss,pid,comm", "-r"])
        var results: [ProcInfo] = []
        let lines = out.split(separator: "\n").dropFirst() // Skip header
        
        for line in lines.prefix(12) {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }
            
            let cpu   = Double(parts[0]) ?? 0
            let rssKB = Int64(parts[1]) ?? 0
            let pid   = Int(parts[2]) ?? 0
            let path  = String(parts[3])
            let name  = (path as NSString).lastPathComponent
            
            if name == "kernel_task" || name.lowercased().contains("macmonitor") { continue }
            
            results.append(ProcInfo(
                pid: pid,
                name: name,
                cpu: cpu,
                mem: rssKB * 1024
            ))
        }
        return Array(results.prefix(8))
    }

    private func fetchHelperMetrics() -> IOReportData? {
        let execOK = FileManager.default.isExecutableFile(atPath: helperPath)
        fputs("[helper] isExecutable=\(execOK) path=\(helperPath)\n", stderr)
        guard execOK else { return nil }

        // IOReport does not require root on Apple Silicon; try direct execution first.
        // Fall back to sudo -n (requires a pre-installed sudoers entry) if direct fails.
        var helperResult = shellResult(helperPath, [])
        fputs("[helper] direct status=\(helperResult.status) outLen=\(helperResult.stdout.count) err=\(helperResult.stderr)\n", stderr)
        if helperResult.status != 0 {
            helperResult = shellResult("/usr/bin/sudo", ["-n", helperPath])
            fputs("[helper] sudo status=\(helperResult.status) outLen=\(helperResult.stdout.count)\n", stderr)
        }
        guard helperResult.status == 0 else {
            fputs("[helper] FAILED status=\(helperResult.status) err=\(helperResult.stderr)\n", stderr)
            return nil
        }

        let output = helperResult.stdout
        fputs("[helper] raw output prefix=\(output.prefix(120))\n", stderr)
        guard let data = output.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fputs("[helper] JSON parse failed output=\(output.prefix(200))\n", stderr)
            return nil
        }

        fputs("[helper] parsed keys=\(payload.keys.sorted())\n", stderr)

        // JSONSerialization returns all numbers as NSNumber. Use .doubleValue / .intValue
        // instead of `as? Int32` / `as? Int64` — those fail when the NSNumber's underlying
        // ObjC type doesn't match exactly (e.g., integer JSON values stored as 64-bit long).
        func dbl(_ key: String) -> Double { (payload[key] as? NSNumber)?.doubleValue ?? 0 }
        func i32(_ key: String) -> Int32  { (payload[key] as? NSNumber).map { Int32($0.intValue) } ?? 0 }
        func i64(_ key: String) -> Int64  { (payload[key] as? NSNumber).map { Int64($0.int64Value) } ?? 0 }

        var result = IOReportData()
        result.cpuTemp         = dbl("cpuTemp")
        result.cpuDieHotspot   = dbl("cpuDieHotspot")
        result.gpuTemp         = dbl("gpuTemp")
        result.cpuPower        = dbl("cpuPower")
        result.gpuPower        = dbl("gpuPower")
        result.anePower        = dbl("anePower")
        result.dramPower       = dbl("dramPower")
        result.systemPower     = dbl("systemPower")
        result.gpuUsage        = dbl("gpuUsage")
        result.gpuFreqMHz      = i32("gpuFreqMHz")
        result.eClusterActive  = dbl("eClusterActive")
        result.pClusterActive  = dbl("pClusterActive")
        result.eClusterFreqMHz = i32("eClusterFreqMHz")
        result.pClusterFreqMHz = i32("pClusterFreqMHz")
        result.dramReadBytes   = i64("dramReadBytes")
        result.dramWriteBytes  = i64("dramWriteBytes")
        result.fanRPM          = i32("fanRPM")
        return result
    }

    private func ensurePrivilegedHelperAccess() {
        samplerQueue.async { [weak self] in
            guard let self = self else { return }
            guard FileManager.default.isExecutableFile(atPath: self.helperPath) else {
                Self.logger.error("helper missing at \(self.helperPath, privacy: .public)")
                return
            }
            guard !self.helperBootstrapInFlight else { return }

            let probe = self.shellResult("/usr/bin/sudo", ["-n", self.helperPath])
            if probe.status == 0 {
                Self.logger.debug("helper already authorized")
                return
            }

            self.helperBootstrapInFlight = true
            defer { self.helperBootstrapInFlight = false }

            Self.logger.notice("requesting one-time administrator approval for helper access")
            let user = NSUserName()
            let sudoersLine = Self.shellSingleQuote("\(user) ALL=(root) NOPASSWD: \(self.helperPath)")
            let command = "/bin/mkdir -p /etc/sudoers.d && /usr/bin/printf '%s\\n' \(sudoersLine) > \(self.helperSudoersPath) && /bin/chmod 440 \(self.helperSudoersPath) && /usr/sbin/visudo -cf \(self.helperSudoersPath)"
            let script = "do shell script \(Self.appleScriptLiteral(command)) with administrator privileges"
            let setup = self.shellResult("/usr/bin/osascript", ["-e", script])

            if setup.status == 0 {
                Self.logger.notice("helper sudoers rule installed successfully")
            } else {
                Self.logger.error("helper bootstrap failed status=\(setup.status) stderr=\(setup.stderr, privacy: .public)")
            }
        }
    }

    private func mergeMetrics(primary: IOReportData?, fallback: IOReportData) -> IOReportData {
        guard let primary = primary else { return fallback }

        var merged = fallback
        if primary.cpuTemp > 0        { merged.cpuTemp        = primary.cpuTemp }
        if primary.gpuTemp > 0        { merged.gpuTemp        = primary.gpuTemp }
        if primary.cpuPower > 0       { merged.cpuPower       = primary.cpuPower }
        if primary.gpuPower > 0       { merged.gpuPower       = primary.gpuPower }
        if primary.anePower > 0       { merged.anePower       = primary.anePower }
        if primary.dramPower > 0      { merged.dramPower      = primary.dramPower }
        if primary.systemPower > 0    { merged.systemPower    = primary.systemPower }
        if primary.gpuUsage > 0       { merged.gpuUsage       = primary.gpuUsage }
        if primary.gpuFreqMHz > 0     { merged.gpuFreqMHz     = primary.gpuFreqMHz }
        if primary.eClusterActive > 0 { merged.eClusterActive = primary.eClusterActive }
        if primary.pClusterActive > 0 { merged.pClusterActive = primary.pClusterActive }
        if primary.eClusterFreqMHz > 0 { merged.eClusterFreqMHz = primary.eClusterFreqMHz }
        if primary.pClusterFreqMHz > 0 { merged.pClusterFreqMHz = primary.pClusterFreqMHz }
        if primary.sClusterActive > 0 { merged.sClusterActive = primary.sClusterActive }
        if primary.sClusterFreqMHz > 0 { merged.sClusterFreqMHz = primary.sClusterFreqMHz }
        if primary.dramReadBytes > 0   { merged.dramReadBytes   = primary.dramReadBytes }
        if primary.dramWriteBytes > 0  { merged.dramWriteBytes  = primary.dramWriteBytes }
        if primary.cpuDieHotspot > 0   { merged.cpuDieHotspot   = primary.cpuDieHotspot }
        if primary.fanRPM > 0          { merged.fanRPM          = primary.fanRPM }
        return merged
    }

    private func loadStaticSystemInfo() {
        // brand_string returns e.g. "Apple M2 Pro" — strip the "Apple " prefix so we
        // display "M2", "M2 Pro", "M2 Max", "M2 Ultra" directly in the UI.
        let rawBrand = Self.sysctlString("machdep.cpu.brand_string")
            ?? Self.sysctlString("hw.model")
            ?? "Apple Silicon"
        let chip = rawBrand.hasPrefix("Apple ") ? String(rawBrand.dropFirst(6)) : rawBrand
        let eCores = Self.sysctlInt("hw.perflevel0.physicalcpu")
        let pCores = Self.sysctlInt("hw.perflevel1.physicalcpu")
        let gpuCores = Self.detectGPUCoreCount()
        let thermal = Self.currentThermalState()

        DispatchQueue.main.async {
            self.chipName = chip
            self.eCoreCount = eCores
            self.pCoreCount = pCores > 0 ? pCores : max(0, ProcessInfo.processInfo.processorCount - eCores)
            self.gpuCoreCount = gpuCores
            self.thermalState = thermal
        }
    }

    // MARK: - Optimize

    func optimize() {
        DispatchQueue.global(qos: .background).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["purge"]
            p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }

        let heavyApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        var candidates: [(app: NSRunningApplication, memMB: Int)] = []
        for proc in topProcs {
            if let app = heavyApps.first(where: { Int($0.processIdentifier) == proc.pid }) {
                let mb = Int(proc.mem / 1_048_576)
                if mb > 250 { candidates.append((app, mb)) }
            }
        }

        DispatchQueue.main.async {
            guard !candidates.isEmpty else {
                let a = NSAlert()
                a.messageText = "System looks healthy"
                a.informativeText = "No heavy user apps found.\nDisk cache has been purged."
                a.runModal(); return
            }
            let names = candidates.map { "\($0.app.localizedName ?? "?")  (\($0.memMB) MB)" }
                                  .joined(separator: "\n")
            let alert = NSAlert()
            alert.messageText = "Heavy Apps Found"
            alert.informativeText = "These apps are using significant RAM:\n\n\(names)\n\nQuit them?"
            alert.addButton(withTitle: "Quit All")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            if alert.runModal() == .alertFirstButtonReturn {
                candidates.forEach { $0.app.terminate() }
            }
        }
    }

    // MARK: - Shell helper

    private func shell(_ path: String, _ args: [String]) -> String {
        shellResult(path, args).stdout
    }

    private func shellResult(_ path: String, _ args: [String]) -> (stdout: String, stderr: String, status: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        do {
            try task.run()
        } catch {
            return ("", "launch failed: \(error)", -1)
        }
        // Drain both pipes concurrently BEFORE waitUntilExit. Otherwise, if the
        // child writes more than the pipe buffer (~16-64 KB) it blocks on write
        // while we block on waitUntilExit → deadlock. `ps -axo ... -r` on a busy
        // Mac (~1000 processes) easily exceeds the buffer.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let q = DispatchQueue.global(qos: .utility)
        group.enter()
        q.async {
            outData = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        q.async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        task.waitUntilExit()
        group.wait()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (out, err, task.terminationStatus)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

private extension SystemStatsModel {
    static func currentThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Normal"
        }
    }

    static func sysctlString(_ name: String) -> String? {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(size))
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return Int(value)
    }

    static func firstSizeMatch(in text: String, pattern: String) -> Int64 {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return 0 }
        let token = String(text[range]).split(separator: " ").last.map(String.init) ?? ""
        return parseSize(token)
    }

    static func firstIntegerMatch(in text: String, pattern: String) -> Int64 {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return 0 }
        let match = String(text[range])
        let digits = match.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int64(digits) ?? 0
    }

    static func detectGPUCoreCount() -> Int {
        let output = shellStatic("/usr/sbin/ioreg", ["-rc", "AGXAcceleratorG14", "-l"])
        let direct = firstIntegerMatch(in: output, pattern: #""gpu-core-count"\s*=\s*(\d+)"#)
        if direct > 0 { return Int(direct) }

        let nested = firstIntegerMatch(in: output, pattern: #""num_cores"\s*=\s*(\d+)"#)
        if nested > 0 { return Int(nested) }
        return 0
    }

    static func shellStatic(_ path: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return "" }
        // Drain pipe before waitUntilExit to avoid deadlock on large output
        // (ioreg can emit hundreds of KB, way past the pipe buffer).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func parseSize(_ token: String) -> Int64 {
        guard !token.isEmpty else { return 0 }
        let sanitized = token.replacingOccurrences(of: "i", with: "", options: .caseInsensitive)
        let suffix = sanitized.last?.uppercased() ?? ""
        let numericPart: String
        if sanitized.last?.isLetter == true {
            numericPart = String(sanitized.dropLast())
        } else {
            numericPart = sanitized
        }
        let value = Double(numericPart) ?? 0

        switch suffix {
        case "K": return Int64(value * 1024)
        case "M": return Int64(value * 1_048_576)
        case "G": return Int64(value * 1_073_741_824)
        case "T": return Int64(value * 1_099_511_627_776)
        default: return Int64(Double(token) ?? 0)
        }
    }
}
