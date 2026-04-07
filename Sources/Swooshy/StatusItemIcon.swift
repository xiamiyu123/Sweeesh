import AppKit

enum StatusItemIcon: String, CaseIterable, Codable, Identifiable, Sendable {
    case swooshy = "swooshy"
    case gale = "gale"
    case groupedWindows = "grouped_windows"
    case splitView = "split_view"
    case stackedWindows = "stacked_windows"
    case focusedWindow = "focused_window"
    case windowGrid = "window_grid"

    var id: Self { self }

    @MainActor
    private static let imageCache = NSCache<NSString, NSImage>()

    init(storageValue: String?) {
        self = StatusItemIcon(rawValue: storageValue ?? "") ?? .gale
    }

    var storageValue: String {
        rawValue
    }

    var symbolName: String? {
        switch self {
        case .swooshy, .gale:
            return nil
        case .groupedWindows:
            return "rectangle.3.group"
        case .splitView:
            return "rectangle.split.2x1"
        case .stackedWindows:
            return "rectangle.on.rectangle"
        case .focusedWindow:
            return "macwindow.on.rectangle"
        case .windowGrid:
            return "square.grid.2x2"
        }
    }

    func title(
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        L10n.string(
            "settings.status_item_icon.\(storageValue)",
            localeIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )
    }

    @MainActor
    func makeImage(accessibilityDescription: String) -> NSImage? {
        let cacheKey = "\(storageValue)|\(accessibilityDescription)" as NSString
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let image: NSImage?

        switch self {
        case .swooshy:
            image = StatusItemTemplateImage.loadTemplateImage(
                named: "SwooshyStatusTemplate",
                accessibilityDescription: accessibilityDescription
            )
        case .gale:
            if let image = StatusItemTemplateImage.loadTemplateImage(
                named: "GaleStatusTemplate",
                accessibilityDescription: accessibilityDescription
            ) {
                Self.imageCache.setObject(image, forKey: cacheKey)
                return image
            }

            image = StatusItemTemplateImage.makeGaleTemplateImage()
        case .groupedWindows, .splitView, .stackedWindows, .focusedWindow, .windowGrid:
            guard
                let symbolName,
                let generatedImage = NSImage(
                    systemSymbolName: symbolName,
                    accessibilityDescription: accessibilityDescription
                )
            else {
                return nil
            }

            generatedImage.isTemplate = true
            image = generatedImage
        }

        guard let image else {
            return nil
        }

        Self.imageCache.setObject(image, forKey: cacheKey)
        return image
    }
}
