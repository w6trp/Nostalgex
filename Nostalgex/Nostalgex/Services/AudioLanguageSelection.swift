import Foundation

/// Language matching for both local audio options and server-selected HLS tracks.
enum AudioLanguageSelection {
    static let defaultsKey = "nostalgex_audio_language"

    static func preferredLanguages(defaults: UserDefaults = .standard,
                                   systemLanguages: [String] = Locale.preferredLanguages) -> [String] {
        guard let stored = defaults.string(forKey: defaultsKey),
              !stored.isEmpty, stored != "__system__" else { return systemLanguages }
        return [stored]
    }

    static func primaryLanguage(_ tag: String?) -> String? {
        guard let tag else { return nil }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let canonical = Locale.canonicalLanguageIdentifier(from: trimmed)
        let code = Locale.Language(identifier: canonical).languageCode
        let primary = (code?.identifier(.alpha2) ?? canonical.components(separatedBy: "-")[0]).lowercased()
        return ["und", "zxx"].contains(primary) ? nil : primary
    }

    static func preferredOptionIndex(tags: [String?], preferredLanguages: [String]) -> Int? {
        for language in preferredLanguages {
            guard let wanted = primaryLanguage(language) else { continue }
            if let index = tags.firstIndex(where: { primaryLanguage($0) == wanted }) { return index }
        }
        return nil
    }
}
