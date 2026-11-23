import Foundation
import SwiftUI

enum L10n {
    static var locale: Locale {
        LanguageStore.shared.resolvedLanguage.locale
    }

    static func string(_ key: String, locale: Locale? = nil) -> String {
        let locale = locale ?? Self.locale
        if let path = Bundle.main.path(forResource: locale.identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: key, table: nil)
            if value != key {
                return value
            }
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg..., locale: Locale? = nil) -> String {
        let template = string(key, locale: locale)
        return String(format: template, locale: locale ?? Self.locale, arguments: arguments)
    }
}

struct LocalizationRoot<Content: View>: View {
    @ObservedObject private var store: LanguageStore
    private let content: Content

    @MainActor
    init(
        store: LanguageStore? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store ?? LanguageStore.shared
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, store.resolvedLanguage.locale)
    }
}
