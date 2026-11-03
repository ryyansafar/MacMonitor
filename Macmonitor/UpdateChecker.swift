import Foundation
import AppKit
import Combine

// Copyright (c) 2025-2026 MacMonitor Contributors. MIT License.

enum UpdateFailure: String, Equatable {
    case download
    case save
    case mount
    case mountPoint
    case appMissing
    case installer
    case cancelled

    var titleKey: String {
        "update.error.\(rawValue)"
    }
}

/// Checks GitHub Releases for a newer version and publishes the result.
/// Singleton — call `UpdateChecker.shared.check()` once at launch.
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()

    // ── Replace ryyansafar with your GitHub username ──────────────────────────
    private let apiURL = URL(string: "https://api.github.com/repos/ryyansafar/MacMonitor/releases/latest")!
    private let releasesURL = URL(string: "https://github.com/ryyansafar/MacMonitor/releases/latest")!

    @Published private(set) var updateAvailable   = false
    @Published private(set) var latestVersion     = ""
    @Published private(set) var updatePhase: UpdatePhase = .idle
    @Published private(set) var downloadFraction: Double  = 0

    enum UpdatePhase: Equatable {
        case idle
        case downloading
        case installing
        case readyToRelaunch
        case failed(UpdateFailure)
    }

    private var progressObs: NSKeyValueObservation?
    private init() {}

    // MARK: - Public

    func check() {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacMonitor/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag  = json["tag_name"] as? String
            else { return }

            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

            DispatchQueue.main.async {
                self.latestVersion   = latest
                self.updateAvailable = Self.isNewer(latest, than: self.currentVersion)
            }
        }.resume()
    }

    // MARK: - In-app update

    func startUpdate() {
        guard updateAvailable, !latestVersion.isEmpty else { return }
        let version = latestVersion
        let dmgName = "MacMonitor-\(version).dmg"
        guard let url = URL(string: "https://github.com/ryyansafar/MacMonitor/releases/download/v\(version)/\(dmgName)") else { return }

        updatePhase = .downloading
        downloadFraction = 0

        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(dmgName)

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tmpURL, _, error in
            guard let self else { return }
            if error != nil {
                self.fail(.download); return
            }
            guard let tmpURL else { self.fail(.download); return }
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tmpURL, to: dest)
            } catch {
                self.fail(.save); return
            }
            self.install(dmg: dest)
        }

        progressObs = task.progress.observe(\.fractionCompleted, options: .new) { [weak self] p, _ in
            DispatchQueue.main.async { self?.downloadFraction = p.fractionCompleted }
        }
        task.resume()
    }

    func relaunch() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/MacMonitor.app"))
        NSApp.terminate(nil)
    }

    func dismissUpdateError() {
        updatePhase = .idle
    }

    // MARK: - Install

    private func install(dmg: URL) {
        DispatchQueue.main.async { self.updatePhase = .installing }

        // Strip quarantine from downloaded DMG so Gatekeeper doesn't block the mount
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", dmg.path]
        xattr.standardOutput = Pipe(); xattr.standardError = Pipe()
        try? xattr.launch(); xattr.waitUntilExit()

        // Mount DMG
        let mountTask = Process()
        mountTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mountTask.arguments = ["attach", dmg.path, "-nobrowse", "-plist"]
        let pipe = Pipe()
        mountTask.standardOutput = pipe
        mountTask.standardError  = Pipe()
        guard (try? mountTask.launch()) != nil else { fail(.mount); return }
        mountTask.waitUntilExit()

        let plistData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist     = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entities  = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else { fail(.mountPoint); return }

        // Find .app in the DMG
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: mountPoint)) ?? []
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            detach(mountPoint); fail(.appMissing); return
        }
        let srcApp  = (mountPoint as NSString).appendingPathComponent(appName)
        let destApp = "/Applications/MacMonitor.app"

        // Replace app and strip quarantine — prompts for admin password if needed
        let script = "do shell script \"rm -rf '\(destApp)' && cp -R '\(srcApp)' '\(destApp)' && xattr -dr com.apple.quarantine '\(destApp)'\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        guard (try? p.launch()) != nil else {
            detach(mountPoint); fail(.installer); return
        }
        p.waitUntilExit()

        detach(mountPoint)
        try? FileManager.default.removeItem(at: dmg)

        DispatchQueue.main.async {
            self.updatePhase = p.terminationStatus == 0 ? .readyToRelaunch : .failed(.cancelled)
        }
    }

    private func detach(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["detach", path, "-quiet"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.launch(); p.waitUntilExit()
    }

    private func fail(_ failure: UpdateFailure) {
        DispatchQueue.main.async { self.updatePhase = .failed(failure) }
    }

    // MARK: - Private

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// True if `a` is a higher semantic version than `b`.
    /// Handles 1.2.3 style — safe for any number of components.
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let parts: (String) -> [Int] = {
            $0.split(separator: ".").compactMap { Int($0) }
        }
        let av = parts(a), bv = parts(b)
        for i in 0..<max(av.count, bv.count) {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}
