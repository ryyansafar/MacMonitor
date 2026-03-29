import SwiftUI

// MARK: - Root

struct PopoverView: View {
    @ObservedObject var model: SystemStatsModel
    @State private var showSettings = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Header(model: model, showSettings: $showSettings)
                if model.mactopMissing {
                    MactopMissingBanner()
                }
                sep
                CPUSection(model: model)
                sep
                GPUSection(model: model)
                sep
                MemorySection(model: model)
                sep
                BatterySection(model: model)
                sep
                NetworkDiskSection(model: model)
                sep
                PowerSection(model: model)
                sep
                ProcessSection(model: model)
                sep
                FooterBar(model: model)
            }
        }
        .frame(width: 340)
        .background(Color(hex: "0E0E12"))
        .sheet(isPresented: $showSettings) {
            SettingsSheet(isPresented: $showSettings)
        }
    }

    private var sep: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}

// MARK: - mactop missing banner

private struct MactopMissingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "FF9F0A"))
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("mactop not found")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "FF9F0A"))
                Text("Run Install.command from the DMG to enable GPU, temps, and power data.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "888899"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "FF9F0A").opacity(0.08))
    }
}

// MARK: - Header

private struct Header: View {
    @ObservedObject var model: SystemStatsModel
    @Binding var showSettings: Bool
    @ObservedObject private var updater = UpdateChecker.shared

    var thermalColor: Color {
        switch model.thermalState {
        case "Normal":   return Color(hex: "30D158")
        case "Fair":     return Color(hex: "FFD60A")
        default:         return Color(hex: "FF453A")
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.chipName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 5) {
                    Circle().fill(thermalColor).frame(width: 6, height: 6)
                    Text(model.thermalState)
                        .font(.system(size: 11))
                        .foregroundColor(thermalColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f W", model.totalPower))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Text("total power")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "666680"))
            }
            Button { showSettings = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "888899"))
                        .padding(.leading, 12)
                    if updater.updateAvailable {
                        Circle()
                            .fill(Color(hex: "FF9F0A"))
                            .frame(width: 7, height: 7)
                            .offset(x: -2, y: 1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - CPU

private struct CPUSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "cpu", title: "CPU") {
            Row(label: "Overall") { StatBar(pct: model.cpuUsage) }
            if model.eCoreCount > 0 {
                Row(label: "E-cluster  \(model.eCoresMHz) MHz") {
                    StatBar(pct: model.eCoresPct, color: Color(hex: "64D2FF"))
                }
                Row(label: "P-cluster  \(model.pCoresMHz) MHz") {
                    StatBar(pct: model.pCoresPct, color: Color(hex: "BF5AF2"))
                }
            }
            if !model.perCoreCPU.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(Array(model.perCoreCPU.enumerated()), id: \.offset) { i, pct in
                        CoreTile(index: i, pct: pct, isE: i < model.eCoreCount)
                    }
                }
                .padding(.top, 4)
            }
            HStack {
                Pill(icon: "thermometer", val: String(format: "%.0f°C", model.cpuTemp),
                     color: tempColor(model.cpuTemp))
                Spacer()
                Pill(icon: "bolt", val: String(format: "%.2f W", model.cpuPower),
                     color: Color(hex: "FFD60A"))
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - GPU

private struct GPUSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "rectangle.3.group", title: "GPU  ·  \(model.gpuCoreCount) cores") {
            Row(label: "\(model.gpuMHz) MHz") {
                StatBar(pct: model.gpuUsage, color: Color(hex: "FF9F0A"))
            }
            HStack {
                Pill(icon: "thermometer", val: String(format: "%.0f°C", model.gpuTemp),
                     color: tempColor(model.gpuTemp))
                Spacer()
                Pill(icon: "bolt", val: String(format: "%.3f W", model.gpuPower),
                     color: Color(hex: "FFD60A"))
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Memory

private struct MemorySection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "memorychip", title: "Memory") {
            Row(label: "\(fmtB(model.memUsed)) / \(fmtB(model.memTotal))") {
                StatBar(pct: model.memPct, color: Color(hex: "0A84FF"))
            }
            HStack(spacing: 16) {
                KV("DRAM BW",  String(format: "%.1f GB/s", model.dramBW))
                KV("Swap", model.swapTotal > 0
                    ? "\(fmtB(model.swapUsed)) / \(fmtB(model.swapTotal))" : "None")
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Battery

private struct BatterySection: View {
    @ObservedObject var model: SystemStatsModel

    var statusLabel: String {
        if model.batteryCharged  { return "Fully Charged" }
        if model.batteryCharging { return "Charging" }
        return "On Battery"
    }

    var batteryColor: Color {
        model.batteryPct < 20 ? Color(hex: "FF453A")
            : (model.batteryCharging || model.batteryCharged)
                ? Color(hex: "30D158") : Color(hex: "FFD60A")
    }

    var body: some View {
        SectionBox(icon: "battery.75percent", title: "Battery") {
            Row(label: statusLabel) {
                StatBar(pct: model.batteryPct, color: batteryColor)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    KV("Source",     model.batteryOnAC ? "AC Power" : "Battery")
                    KV("Remaining",  model.batteryTimeLeft)
                }
                GridRow {
                    KV("Adapter",    model.adapterWatts > 0
                        ? String(format: "%.0f W", model.adapterWatts) : "—")
                    KV("Charge rate",model.chargingWatts > 0
                        ? String(format: "%.1f W", model.chargingWatts) : "—")
                }
                GridRow {
                    KV("Temp",       model.batteryTempC > 0
                        ? String(format: "%.1f °C", model.batteryTempC) : "—")
                    KV("Cycles",     model.batteryCycles > 0
                        ? "\(model.batteryCycles)" : "—")
                }
                GridRow {
                    KV("Health",     "\(model.batteryHealthPct)%")
                    KV("Capacity",   model.batteryMaxMAh > 0
                        ? "\(model.batteryMaxMAh) / \(model.batteryDesignMAh) mAh" : "—")
                }
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Network + Disk

private struct NetworkDiskSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        HStack(spacing: 0) {
            SectionBox(icon: "wifi", title: "Network") {
                IORow(icon: "arrow.down", val: fmtB(model.netInBps)  + "/s", color: Color(hex:"30D158"))
                IORow(icon: "arrow.up",   val: fmtB(model.netOutBps) + "/s", color: Color(hex:"FF9F0A"))
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            SectionBox(icon: "internaldrive", title: "Disk I/O") {
                IORow(icon: "arrow.down", val: String(format: "%.0f KB/s", model.diskReadKBs),  color: Color(hex:"64D2FF"))
                IORow(icon: "arrow.up",   val: String(format: "%.0f KB/s", model.diskWriteKBs), color: Color(hex:"FF9F0A"))
            }
        }
    }
}

private struct IORow: View {
    let icon: String; let val: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(color)
            Text(val)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: "EBEBF5"))
            Spacer()
        }
    }
}

// MARK: - Power rails

private struct PowerSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "bolt.fill", title: "Power Rails") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                PowerTile(label: "CPU",   val: model.cpuPower)
                PowerTile(label: "GPU",   val: model.gpuPower)
                PowerTile(label: "ANE",   val: model.anePower)
                PowerTile(label: "DRAM",  val: model.dramPower)
                PowerTile(label: "SYS",   val: model.sysPower)
                PowerTile(label: "TOTAL", val: model.totalPower, highlight: true)
            }
        }
    }
}

private struct PowerTile: View {
    let label: String; let val: Double; var highlight: Bool = false
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(highlight ? Color(hex:"FFD60A") : Color(hex:"888899"))
            Spacer()
            Text(String(format: val >= 1 ? "%.2f W" : "%.3f W", val))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(highlight ? Color(hex:"FFD60A") : .white)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.white.opacity(highlight ? 0.07 : 0.03))
        .cornerRadius(6)
    }
}

// MARK: - Processes

private struct ProcessSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "list.bullet", title: "Top Processes") {
            HStack {
                Text("Process").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 40, alignment: .trailing)
                Text("Memory").frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 9)).foregroundColor(Color(hex: "666680"))

            ForEach(model.topProcs) { p in
                HStack(spacing: 0) {
                    Text(p.name)
                        .font(.system(size: 11)).foregroundColor(Color(hex: "EBEBF5"))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f%%", p.cpu))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(cpuClr(p.cpu))
                        .frame(width: 40, alignment: .trailing)
                    Text(fmtB(p.mem))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "64D2FF"))
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }
    func cpuClr(_ v: Double) -> Color {
        v >= 50 ? Color(hex:"FF453A") : v >= 20 ? Color(hex:"FFD60A") : Color(hex:"30D158")
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @ObservedObject var model: SystemStatsModel
    @State private var working = false
    var body: some View {
        HStack(spacing: 10) {
            Button {
                working = true
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    model.optimize()
                    DispatchQueue.main.async { working = false }
                }
            } label: {
                Label(working ? "Working…" : "Optimize", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent).tint(Color(hex: "FF9F0A")).disabled(working)

            Button { NSApp.terminate(nil) } label: {
                Text("Quit").frame(maxWidth: .infinity)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular).padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Settings sheet

struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @AppStorage("enableMenuBar") var enableMenuBar = true
    @AppStorage("enableWidget")  var enableWidget  = false
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.white)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Menu Bar App", isOn: $enableMenuBar)
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                Text("Live stats in your menu bar. Click to open the full dashboard.")
                    .font(.system(size: 11)).foregroundColor(Color(hex: "666680"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Desktop Widget", isOn: $enableWidget)
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                Text("Right-click your desktop → Edit Widgets → find MacMonitor.")
                    .font(.system(size: 11)).foregroundColor(Color(hex: "666680"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().background(Color.white.opacity(0.1))

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacMonitor  v\(updater.currentVersion)")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                    if updater.updateAvailable {
                        Text("v\(updater.latestVersion) available")
                            .font(.system(size: 10)).foregroundColor(Color(hex: "FF9F0A"))
                    } else {
                        Text("Apple Silicon  ·  macOS 13+  ·  MIT")
                            .font(.system(size: 10)).foregroundColor(Color(hex: "666680"))
                    }
                }
                Spacer()
                if updater.updateAvailable {
                    Button("Update") { updater.openReleasesPage() }
                        .buttonStyle(.borderedProminent).tint(Color(hex: "FF9F0A"))
                        .font(.system(size: 12, weight: .semibold))
                }
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent).tint(Color(hex: "0A84FF"))
            }
        }
        .padding(22).frame(width: 320)
        .background(Color(hex: "1C1C1E"))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reusable atoms

private struct SectionBox<Content: View>: View {
    let icon: String; let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "888899"))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "888899")).tracking(0.6)
            }
            content
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

private struct Row<R: View>: View {
    let label: String; @ViewBuilder let right: R
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11)).foregroundColor(Color(hex: "ABABC0"))
                .frame(width: 130, alignment: .leading).lineLimit(1)
            right
        }
    }
}

private struct StatBar: View {
    let pct: Int; var color: Color = Color(hex: "30D158")
    private var barColor: Color {
        pct >= 85 ? Color(hex:"FF453A") : pct >= 60 ? Color(hex:"FFD60A") : color
    }
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.07))
                    RoundedRectangle(cornerRadius: 3).fill(barColor)
                        .frame(width: g.size.width * CGFloat(min(pct,100)) / 100)
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 7)
            Text("\(pct)%")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

private struct CoreTile: View {
    let index: Int; let pct: Double; let isE: Bool
    var color: Color {
        pct >= 85 ? Color(hex:"FF453A") : pct >= 60 ? Color(hex:"FFD60A")
            : (isE ? Color(hex:"64D2FF") : Color(hex:"BF5AF2"))
    }
    var body: some View {
        HStack(spacing: 5) {
            Text("C\(index)").font(.system(size: 9, design: .monospaced))
                .foregroundColor(color.opacity(0.7)).frame(width: 16)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: g.size.width * CGFloat(min(pct,100)) / 100)
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 5)
            Text("\(Int(pct))%").font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(hex:"666680")).frame(width: 26, alignment: .trailing)
        }
    }
}

private struct Pill: View {
    let icon: String; let val: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(val).font(.system(size: 10, design: .monospaced))
        }
        .foregroundColor(color)
    }
}

private struct KV: View {
    let k: String; let v: String
    init(_ k: String, _ v: String) { self.k = k; self.v = v }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 9)).foregroundColor(Color(hex:"666680"))
            Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex:"EBEBF5"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Helpers

private func fmtB(_ b: Int64) -> String {
    let d = Double(b)
    if d >= 1_073_741_824 { return String(format: "%.1f GB", d/1_073_741_824) }
    if d >= 1_048_576     { return String(format: "%.1f MB", d/1_048_576) }
    if d >= 1_024         { return String(format: "%.0f KB", d/1_024) }
    return "\(b) B"
}

private func tempColor(_ t: Double) -> Color {
    t >= 80 ? Color(hex:"FF453A") : t >= 65 ? Color(hex:"FFD60A") : Color(hex:"888899")
}

// MARK: - Hex colour helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double((int)       & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
