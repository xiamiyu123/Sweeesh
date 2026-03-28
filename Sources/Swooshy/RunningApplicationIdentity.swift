import AppKit
import Foundation

enum RunningApplicationIdentity {
    static func isLikelyHelperProcess(_ application: NSRunningApplication) -> Bool {
        let localizedName = (application.localizedName ?? "").lowercased()
        let bundleIdentifier = (application.bundleIdentifier ?? "").lowercased()
        let bundlePath = (application.bundleURL?.path ?? "").lowercased()

        if localizedName.contains("helper") || localizedName.contains("notification service") {
            return true
        }

        if bundleIdentifier.contains(".framework.") || bundleIdentifier.contains(".helper") {
            return true
        }

        if bundlePath.contains("/frameworks/") || bundlePath.contains("/helpers/") || bundlePath.contains(".appex/") {
            return true
        }

        return false
    }

    static func aliases(for application: NSRunningApplication) -> [String] {
        var aliases: Set<String> = []

        if let localizedName = application.localizedName, localizedName.isEmpty == false {
            aliases.insert(localizedName)
        }

        if let bundleIdentifier = application.bundleIdentifier, bundleIdentifier.isEmpty == false {
            aliases.insert(bundleIdentifier)
        }

        if let bundleURL = application.bundleURL {
            aliases.insert(bundleURL.deletingPathExtension().lastPathComponent)

            if
                let bundle = Bundle(url: bundleURL),
                let info = bundle.infoDictionary
            {
                let keys = [
                    "CFBundleDisplayName",
                    "CFBundleName",
                    "CFBundleExecutable",
                ]

                for key in keys {
                    if let value = info[key] as? String, value.isEmpty == false {
                        aliases.insert(value)
                    }
                }
            }
        }

        return aliases.sorted()
    }

    static func normalizedAliases(from aliases: [String]) -> Set<String> {
        Set(
            aliases
                .map(normalizedAlias)
                .filter { $0.isEmpty == false }
        )
    }

    static func normalizedAlias(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }
}