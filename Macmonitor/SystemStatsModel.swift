import Foundation
import AppKit
import Darwin
import Combine

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
    @Published var chipName:     String = "Apple Silicon"
    @Published var eCoreCount:   Int    = 0
    @Published var pCoreCount:   Int    = 0
    @Published var gpuCoreCount: Int    = 0

    @Published var topProcs: [ProcInfo] = []
    @Published var mactopReady   = false
    @Published var mactopMissing = false

    // Private
    private var prevCPUTicks: [[UInt32]] = []
    private var prevNetIn:    Int64 = 0
    private var prevNetOut:   Int64 = 0
    private var prevTickTime: Date  = Date()
    private var timer: Timer?

    private static let mactopPath: String = {
        let candidates = ["/opt/homebrew/bin/mactop", "/usr/local/bin/mactop"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }()

    // MARK: - Start

    func startMonitoring() {
        _ = sampleCPU()
        let (ni, no) = netCumulative()
        prevNetIn = ni; prevNetOut = no; prevTickTime = Date()
        fetchMactop()
        fetchBattery()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: - Tick

    private func tick() {
        let (cpu, cores) = sampleCPU()
        let (mUsed, mTot) = sampleMemory()
        let (ni, no) = netCumulative()
        let dt = max(Date().timeIntervalSince(prevTickTime), 0.001)
        let inBps  = Int64(Double(ni - prevNetIn)  / dt)
        let outBps = Int64(Double(no - prevNetOut) / dt)
        prevNetIn = ni; prevNetOut = no; prevTickTime = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cpuUsage   = Int(cpu.rounded())
            self.perCoreCPU = cores
            self.memUsed    = mUsed
            self.memTotal   = mTot
            self.memPct     = mTot > 0 ? Int(mUsed * 100 / mTot) : 0
            self.netInBps   = max(0, inBps)
            self.netOutBps  = max(0, outBps)
        }
        fetchMactop()
        fetchBattery()
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
            let adapterOut = self.shell("/usr/bin/pmset", ["-g", "adapter"])
            let wattsMatch = adapterOut.range(of: #"Watts:\s+([\d.]+)"#, options: .regularExpression)
            let adWatts: Double
            if let r = wattsMatch {
                adWatts = Double(adapterOut[r].components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
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
            let maxCap  = ioInt("MaxCapacity")
            let desCap  = ioInt("DesignCapacity")
            let curCap  = ioInt("CurrentCapacity")
            let rawTemp = ioInt("Temperature")           // in 0.01°C
            let battTemp = Double(rawTemp) / 100.0

            // Charging current (mA) × voltage (mV) → watts
            let voltage    = Double(ioInt("Voltage")) / 1000.0        // V
            let amperage   = abs(Double(ioInt("Amperage"))) / 1000.0  // A
            let chrgWatts  = voltage * amperage

            let health = desCap > 0 ? Int(Double(maxCap) / Double(desCap) * 100) : 100

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
                self.batteryCurrentMAh = curCap
                self.batteryMaxMAh     = maxCap
                self.batteryDesignMAh  = desCap
                self.adapterWatts      = adWatts
                self.chargingWatts     = chrgWatts
            }
        }
    }

    // MARK: - GPU / Temps / Clusters / Power (mactop)

    private func fetchMactop() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let mactop = SystemStatsModel.mactopPath
            guard FileManager.default.fileExists(atPath: mactop) else {
                DispatchQueue.main.async { self.mactopMissing = true }
                return
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            task.arguments = [mactop,
                              "--headless", "--count", "1", "-i", "2000", "--format", "json"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError  = Pipe()
            guard (try? task.launch()) != nil else { return }
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let d   = arr.first else { return }

            let soc  = d["soc_metrics"]  as? [String: Any] ?? [:]
            let mem  = d["memory"]        as? [String: Any] ?? [:]
            let nd   = d["net_disk"]      as? [String: Any] ?? [:]
            let si   = d["system_info"]   as? [String: Any] ?? [:]

            func dbl(_ dict: [String:Any], _ k: String) -> Double { dict[k] as? Double ?? 0 }
            func int_(_ dict: [String:Any], _ k: String) -> Int   { dict[k] as? Int   ?? 0 }

            let procs: [ProcInfo] = (d["processes"] as? [[String: Any]] ?? [])
                .sorted { ($0["cpu_percent"] as? Double ?? 0) > ($1["cpu_percent"] as? Double ?? 0) }
                .prefix(8)
                .compactMap { p in
                    guard let name = p["command"] as? String else { return nil }
                    return ProcInfo(
                        pid:  p["pid"]         as? Int    ?? 0,
                        name: String((name.components(separatedBy: "/").last ?? name).prefix(34)),
                        cpu:  p["cpu_percent"] as? Double ?? 0,
                        mem:  p["mem_bytes"]   as? Int64  ?? 0
                    )
                }

            let swapU = mem["swap_used"]  as? Int64 ?? 0
            let swapT = mem["swap_total"] as? Int64 ?? 0
            let eCl   = (d["ecpu_usage"] as? [Double])?[safe: 1] ?? 0
            let pCl   = (d["pcpu_usage"] as? [Double])?[safe: 1] ?? 0
            let eMHz  = Int((d["ecpu_usage"] as? [Double])?[safe: 0] ?? 0)
            let pMHz  = Int((d["pcpu_usage"] as? [Double])?[safe: 0] ?? 0)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.gpuUsage       = Int((d["gpu_usage"] as? Double ?? 0).rounded())
                self.gpuMHz         = Int(dbl(soc, "gpu_freq_mhz"))
                self.cpuTemp        = dbl(soc, "cpu_temp")
                self.gpuTemp        = dbl(soc, "gpu_temp")
                self.cpuPower       = dbl(soc, "cpu_power")
                self.gpuPower       = dbl(soc, "gpu_power")
                self.anePower       = dbl(soc, "ane_power")
                self.dramPower      = dbl(soc, "dram_power")
                self.sysPower       = dbl(soc, "system_power")
                self.totalPower     = dbl(soc, "total_power")
                self.dramBW         = dbl(soc, "dram_bw_combined_gbs")
                self.swapUsed       = swapU
                self.swapTotal      = swapT
                self.diskReadKBs    = dbl(nd,  "read_kbytes_per_sec")
                self.diskWriteKBs   = dbl(nd,  "write_kbytes_per_sec")
                self.eCoresPct      = Int(eCl.rounded())
                self.pCoresPct      = Int(pCl.rounded())
                self.eCoresMHz      = eMHz
                self.pCoresMHz      = pMHz
                self.thermalState   = d["thermal_state"] as? String ?? "Normal"
                self.chipName       = si["name"]         as? String ?? "Apple Silicon"
                self.eCoreCount     = int_(si, "e_core_count")
                self.pCoreCount     = int_(si, "p_core_count")
                self.gpuCoreCount   = int_(si, "gpu_core_count")
                self.topProcs       = procs
                self.mactopReady    = true
            }
        }
    }

    // MARK: - Optimize

    func optimize() {
        DispatchQueue.global(qos: .background).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            p.arguments = ["purge"]
            p.standardError = Pipe()
            try? p.launch(); p.waitUntilExit()
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = Pipe()
        guard (try? task.launch()) != nil else { return "" }
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
