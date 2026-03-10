import Foundation

enum DebugLogPaths {
    static let directoryURL: URL = {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return libraryURL.appendingPathComponent("Logs/FloatyDo", isDirectory: true)
    }()

    static let launchURL = directoryURL.appendingPathComponent("launch.log")
    static let layoutURL = directoryURL.appendingPathComponent("layout.log")

    static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
