import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .system:
            return "app.language.system"
        case .simplifiedChinese:
            return "app.language.simplifiedChinese"
        case .english:
            return "app.language.english"
        }
    }
}

enum ResolvedLanguage: String, Equatable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static func resolve(
        selection: AppLanguage,
        preferredLanguages: [String]
    ) -> ResolvedLanguage {
        switch selection {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        case .system:
            guard let preferred = preferredLanguages.first?
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            else {
                return .english
            }

            if preferred.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if preferred.hasPrefix("en") {
                return .english
            }
            return .english
        }
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}

@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    @Published private(set) var selection: AppLanguage
    @Published private(set) var resolvedLanguage: ResolvedLanguage

    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages

        let saved = defaults.string(forKey: AppLanguage.storageKey)
        let selection = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.selection = selection
        self.resolvedLanguage = ResolvedLanguage.resolve(
            selection: selection,
            preferredLanguages: preferredLanguages()
        )
    }

    func select(_ language: AppLanguage) {
        selection = language
        defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        updateResolvedLanguage(notifyWhenUnchanged: true)
    }

    func refreshSystemLanguage() {
        guard selection == .system else { return }
        updateResolvedLanguage(notifyWhenUnchanged: false)
    }

    private func updateResolvedLanguage(notifyWhenUnchanged: Bool) {
        let resolved = ResolvedLanguage.resolve(
            selection: selection,
            preferredLanguages: preferredLanguages()
        )
        let changed = resolvedLanguage != resolved
        if changed {
            resolvedLanguage = resolved
        }
        if changed || notifyWhenUnchanged {
            NotificationCenter.default.post(name: .appLanguageDidChange, object: self)
        }
    }
}
