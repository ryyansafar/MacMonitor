import Foundation
import AppKit
import Combine

// Copyright (c) 2025-2026 MacMonitor Contributors. MIT License.

/// Checks GitHub Releases for a newer version and publishes the result.
/// Singleton — call `UpdateChecker.shared.check()` once at launch.
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()

    // ── Replace ryyansafar with your GitHub username ──────────────────────────
    private let apiURL = URL(string: "https://api.github.com/repos/ryyansafar/MacMonitor/releases/latest")!
    private let releasesURL = URL(string: "https://github.com/ryyansafar/MacMonitor/releases/latest")!

    @Published private(set) var updateAvailable = false
    @Published private(set) var latestVersion   = ""

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

    func openReleasesPage() {
        NSWorkspace.shared.open(releasesURL)
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
