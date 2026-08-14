import Foundation

extension Notification.Name {
    static let menuBarLayoutChanged = Notification.Name("menuBarLayoutChanged")
}

struct MenuBarSnapshot {
    var cpuUsage = 0
    var memoryPercent = 0
    var cpuTemperature = 0.0
    var networkInBytesPerSecond: Int64 = 0
    var networkOutBytesPerSecond: Int64 = 0
    var diskReadKilobytesPerSecond = 0.0
    var diskWriteKilobytesPerSecond = 0.0
    var totalPower = 0.0
    var batteryPercent = 0
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case network
    case disk
    case power
    case battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .disk: return "Disk I/O"
        case .power: return "Power"
        case .battery: return "Battery"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "arrow.down.arrow.up"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        case .battery: return "battery.75percent"
        }
    }

    var defaultVisible: Bool {
        self == .cpu || self == .memory
    }

    func titleFragment(snapshot: MenuBarSnapshot) -> String? {
        switch self {
        case .cpu:
            let temperature = snapshot.cpuTemperature > 0
                ? String(format: " %.0f°", snapshot.cpuTemperature)
                : ""
            return "CPU \(snapshot.cpuUsage)%\(temperature)"
        case .memory:
            return "MEM \(snapshot.memoryPercent)%"
        case .network:
            return "NET ↓\(Self.formatRate(snapshot.networkInBytesPerSecond)) ↑\(Self.formatRate(snapshot.networkOutBytesPerSecond))"
        case .disk:
            let read = Int64(snapshot.diskReadKilobytesPerSecond * 1024)
            let write = Int64(snapshot.diskWriteKilobytesPerSecond * 1024)
            return "DSK R\(Self.formatRate(read)) W\(Self.formatRate(write))"
        case .power:
            guard snapshot.totalPower > 0 else { return nil }
            return String(format: "PWR %.1fW", snapshot.totalPower)
        case .battery:
            guard snapshot.batteryPercent > 0 else { return nil }
            return "BAT \(snapshot.batteryPercent)%"
        }
    }

    private static func formatRate(_ bytesPerSecond: Int64) -> String {
        let value = Double(max(0, bytesPerSecond))
        if value >= 1_048_576 {
            return String(format: "%.1fM/s", value / 1_048_576)
        }
        if value >= 1_024 {
            return String(format: "%.0fK/s", value / 1_024)
        }
        return "\(Int(value))B/s"
    }
}

enum MenuBarLayoutStore {
    private static let orderKey = "menuBarMetricOrder"
    private static let visiblePrefix = "menuBarMetricVisible."

    static func orderedMetrics() -> [MenuBarMetric] {
        let saved = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        var metrics = saved.compactMap(MenuBarMetric.init(rawValue:))
        for metric in MenuBarMetric.allCases where !metrics.contains(metric) {
            metrics.append(metric)
        }
        return metrics
    }

    static func visibleMetrics() -> [MenuBarMetric] {
        orderedMetrics().filter(isVisible)
    }

    static func isVisible(_ metric: MenuBarMetric) -> Bool {
        let key = visiblePrefix + metric.rawValue
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return metric.defaultVisible
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    @discardableResult
    static func setVisible(_ metric: MenuBarMetric, _ visible: Bool) -> Bool {
        if !visible && isVisible(metric) && visibleMetrics().count == 1 {
            return false
        }
        UserDefaults.standard.set(visible, forKey: visiblePrefix + metric.rawValue)
        notify()
        return true
    }

    static func move(_ metric: MenuBarMetric, direction: Int) {
        var metrics = orderedMetrics()
        guard let index = metrics.firstIndex(of: metric) else { return }
        let target = index + direction
        guard metrics.indices.contains(target) else { return }
        metrics.swapAt(index, target)
        UserDefaults.standard.set(metrics.map(\.rawValue), forKey: orderKey)
        notify()
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: orderKey)
        for metric in MenuBarMetric.allCases {
            UserDefaults.standard.removeObject(forKey: visiblePrefix + metric.rawValue)
        }
        notify()
    }

    private static func notify() {
        NotificationCenter.default.post(name: .menuBarLayoutChanged, object: nil)
    }
}
