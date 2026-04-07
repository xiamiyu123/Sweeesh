import Foundation
import OSLog

enum DebugLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Swooshy"

    struct Channel {
        let name: String
        let logger: Logger
    }

    static let app = Channel(name: "app", logger: Logger(subsystem: subsystem, category: "app"))
    static let settings = Channel(name: "settings", logger: Logger(subsystem: subsystem, category: "settings"))
    static let hotkeys = Channel(name: "hotkeys", logger: Logger(subsystem: subsystem, category: "hotkeys"))
    static let dock = Channel(name: "dock", logger: Logger(subsystem: subsystem, category: "dock"))
    static let windows = Channel(name: "windows", logger: Logger(subsystem: subsystem, category: "windows"))
    static let accessibility = Channel(name: "accessibility", logger: Logger(subsystem: subsystem, category: "accessibility"))

    private static let fileSink = DebugLogFileSink()

    static func debug(_ channel: Channel, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let rendered = message()
        channel.logger.debug("\(rendered, privacy: .public)")
        writeToFile(level: "DEBUG", channel: channel, message: rendered)
    }

    static func info(_ channel: Channel, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let rendered = message()
        channel.logger.info("\(rendered, privacy: .public)")
        writeToFile(level: "INFO", channel: channel, message: rendered)
    }

    static func error(_ channel: Channel, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let rendered = message()
        channel.logger.error("\(rendered, privacy: .public)")
        writeToFile(level: "ERROR", channel: channel, message: rendered)
    }

    static var logFilePathDescription: String {
        fileSink.currentLogFileURL.path
    }

    private static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["SWOOSHY_DEBUG_LOGS"] == "1" {
            return true
        }

        return UserDefaults.standard.bool(forKey: "settings.debugLoggingEnabled")
    }

    private static func writeToFile(level: String, channel: Channel, message: String) {
        Task {
            await fileSink.append(level: level, channel: channel.name, message: message)
        }
    }
}

/// Serializes file I/O and log rotation so hot paths can append debug output
/// without coordinating access to the underlying file handle.
actor DebugLogFileSink {
    private let fileManager = FileManager.default
    let logDirectoryURL: URL
    let currentLogFileURL: URL
    private let timestampFormatter = ISO8601DateFormatter()
    private let archiveNameFormatter: DateFormatter
    private let maximumLogFileSize: Int64 = 5 * 1024 * 1024
    private let maximumArchivedLogCount = 10
    private let archivedLogRetentionInterval: TimeInterval = 7 * 24 * 60 * 60
    private let maintenanceInterval: TimeInterval = 24 * 60 * 60
    private var fileHandle: FileHandle?
    private var lastMaintenanceDate: Date?

    init(logDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Swooshy", isDirectory: true)) {
        self.logDirectoryURL = logDirectoryURL
        self.currentLogFileURL = logDirectoryURL.appendingPathComponent("debug.log")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        self.archiveNameFormatter = formatter
    }

    deinit {
        do {
            try fileHandle?.close()
        } catch {
            NSLog("Swooshy debug log file close failed: %@", error.localizedDescription)
        }
    }

    func append(level: String, channel: String, message: String) {
        do {
            let line = "\(timestampFormatter.string(from: Date())) [\(level)] [\(channel)] \(message)\n"
            try performMaintenanceIfNeeded()
            try rotateCurrentLogIfNeeded(projectedAdditionalBytes: Int64(line.utf8.count))
            let handle = try logFileHandle()
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            NSLog("Swooshy debug log file write failed: %@", error.localizedDescription)
        }
    }

    private func performMaintenanceIfNeeded() throws {
        let now = Date()

        // Archive pruning is much slower than an append, so keep that work on a
        // coarse timer instead of re-scanning the log directory on every write.
        if let lastMaintenanceDate, now.timeIntervalSince(lastMaintenanceDate) < maintenanceInterval {
            return
        }

        try ensureLogDirectoryExists()
        try pruneArchivedLogs(now: now)
        lastMaintenanceDate = now
    }

    private func ensureLogDirectoryExists() throws {
        try fileManager.createDirectory(
            at: logDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func rotateCurrentLogIfNeeded(projectedAdditionalBytes: Int64) throws {
        guard let currentFileSize = currentLogFileSize() else {
            return
        }

        guard currentFileSize + projectedAdditionalBytes > maximumLogFileSize else {
            return
        }

        try closeCurrentFileHandle()

        guard fileManager.fileExists(atPath: currentLogFileURL.path) else {
            return
        }

        let rotatedLogURL = try uniqueArchivedLogURL()
        try fileManager.moveItem(at: currentLogFileURL, to: rotatedLogURL)
    }

    private func pruneArchivedLogs(now: Date) throws {
        let archiveURLs = archivedLogURLs()
        let expiredCutoff = now.addingTimeInterval(-archivedLogRetentionInterval)

        var retainedArchiveURLs: [(url: URL, date: Date)] = []

        for archiveURL in archiveURLs {
            if let modificationDate = modificationDate(for: archiveURL) {
                if modificationDate < expiredCutoff {
                    try fileManager.removeItem(at: archiveURL)
                    continue
                }

                retainedArchiveURLs.append((archiveURL, modificationDate))
            } else {
                retainedArchiveURLs.append((archiveURL, .distantPast))
            }
        }

        if retainedArchiveURLs.count <= maximumArchivedLogCount {
            return
        }

        let sortedArchiveURLs = retainedArchiveURLs.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.url.lastPathComponent < rhs.url.lastPathComponent
            }

            return lhs.date < rhs.date
        }

        let excessArchives = sortedArchiveURLs.prefix(sortedArchiveURLs.count - maximumArchivedLogCount)
        for archive in excessArchives {
            try fileManager.removeItem(at: archive.url)
        }
    }

    private func logFileHandle() throws -> FileHandle {
        if let fileHandle {
            return fileHandle
        }

        try ensureLogDirectoryExists()

        if fileManager.fileExists(atPath: currentLogFileURL.path) == false {
            let created = fileManager.createFile(atPath: currentLogFileURL.path, contents: nil)
            guard created else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteUnknownError,
                    userInfo: [NSFilePathErrorKey: currentLogFileURL.path]
                )
            }
        }

        let handle = try FileHandle(forWritingTo: currentLogFileURL)
        self.fileHandle = handle
        return handle
    }

    private func closeCurrentFileHandle() throws {
        guard let fileHandle else {
            return
        }

        try fileHandle.close()
        self.fileHandle = nil
    }

    private func currentLogFileSize() -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: currentLogFileURL.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }

        return fileSize.int64Value
    }

    private func archivedLogURLs() -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: logDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents.filter { url in
            url.lastPathComponent.hasPrefix("debug-") && url.pathExtension == "log"
        }
    }

    private func modificationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private func uniqueArchivedLogURL() throws -> URL {
        let baseName = "debug-\(archiveNameFormatter.string(from: Date()))"
        var candidateURL = logDirectoryURL.appendingPathComponent("\(baseName).log")
        var suffix = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = logDirectoryURL.appendingPathComponent("\(baseName)-\(suffix).log")
            suffix += 1
        }

        return candidateURL
    }
}
