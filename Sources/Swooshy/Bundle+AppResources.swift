import Foundation

extension Bundle {
    static var appResources: Bundle {
        let bundleCandidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Swooshy_Swooshy.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Swooshy_Swooshy.bundle").absoluteURL,
        ]

        for candidate in bundleCandidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        return .module
    }
}
