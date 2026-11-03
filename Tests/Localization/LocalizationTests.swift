import Foundation

@MainActor
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct LocalizationTests {
    @MainActor
    static func main() {
        expect(
            ResolvedLanguage.resolve(
                selection: .system,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .simplifiedChinese,
            "Simplified Chinese system language should resolve to Simplified Chinese"
        )

        expect(
            ResolvedLanguage.resolve(
                selection: .system,
                preferredLanguages: ["zh-Hant-TW"]
            ) == .simplifiedChinese,
            "Traditional Chinese system language should resolve to Simplified Chinese"
        )

        expect(
            ResolvedLanguage.resolve(
                selection: .system,
                preferredLanguages: ["en-US"]
            ) == .english,
            "English system language should resolve to English"
        )

        expect(
            ResolvedLanguage.resolve(
                selection: .system,
                preferredLanguages: ["ja-JP"]
            ) == .english,
            "Unsupported system language should fall back to English"
        )

        expect(
            ResolvedLanguage.resolve(
                selection: .system,
                preferredLanguages: []
            ) == .english,
            "Missing preferred languages should fall back to English"
        )

        expect(
            ResolvedLanguage.resolve(
                selection: .simplifiedChinese,
                preferredLanguages: ["en-US"]
            ) == .simplifiedChinese,
            "An explicit Chinese selection should override the system language"
        )

        expect(
            ResolvedLanguage.resolve(
                selection: .english,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .english,
            "An explicit English selection should override the system language"
        )

        let suiteName = "MacMonitorLocalizationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("FAIL: could not create isolated UserDefaults suite\n", stderr)
            exit(1)
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("dark", forKey: "appTheme")
        defaults.set(true, forKey: "cpuOnlyMenuBar")

        var preferredLanguages = ["zh-Hans-CN"]
        let store = LanguageStore(
            defaults: defaults,
            preferredLanguages: { preferredLanguages }
        )

        expect(store.selection == .system, "Missing preference should default to Follow System")
        expect(store.resolvedLanguage == .simplifiedChinese,
               "The default Follow System selection should use the injected system language")

        store.select(.english)
        expect(defaults.string(forKey: AppLanguage.storageKey) == AppLanguage.english.rawValue,
               "An explicit English selection should be persisted")
        expect(store.resolvedLanguage == .english,
               "An explicit English selection should resolve immediately")

        let reloadedEnglish = LanguageStore(
            defaults: defaults,
            preferredLanguages: { preferredLanguages }
        )
        expect(reloadedEnglish.selection == .english,
               "The saved English selection should survive a reload")
        expect(reloadedEnglish.resolvedLanguage == .english,
               "The reloaded English selection should not follow the system language")

        reloadedEnglish.select(.simplifiedChinese)
        expect(defaults.string(forKey: AppLanguage.storageKey) == AppLanguage.simplifiedChinese.rawValue,
               "An explicit Chinese selection should be persisted")

        preferredLanguages = ["en-US"]
        reloadedEnglish.select(.system)
        expect(reloadedEnglish.resolvedLanguage == .english,
               "Follow System should re-resolve against the current preferred language")

        expect(defaults.string(forKey: "appTheme") == "dark",
               "Changing language should not modify the theme setting")
        expect(defaults.bool(forKey: "cpuOnlyMenuBar"),
               "Changing language should not modify menu bar settings")

        print("Localization resolution tests passed")
    }
}
