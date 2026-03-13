#if canImport(AppKit)
import AppKit
import Foundation

final class PrimaryAppIconRelaunchController {
    static let shared = PrimaryAppIconRelaunchController()

    private let themeMarkerFileName = ".floatydo-primary-icon-theme"
    private let supportDirectoryName = "FloatyDo"
    private let projectRootFileName = "project-root.txt"

    private init() {}

    func currentTheme() -> BuiltInTheme {
        guard let markerURL = themeMarkerURL(),
              let rawValue = try? String(contentsOf: markerURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let theme = BuiltInTheme(rawValue: rawValue) else {
            return .theme1
        }
        return theme
    }

    func canApplyIconChanges() -> Bool {
        repositoryRootURL() != nil
    }

    func applyAndRelaunch(theme: BuiltInTheme) throws {
        guard let repoRootURL = repositoryRootURL() else {
            throw RelaunchError.repositoryNotFound
        }

        let scriptURL = repoRootURL.appendingPathComponent("scripts/apply_primary_icon_and_relaunch.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw RelaunchError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            repoRootURL.path,
            theme.rawValue,
            "\(ProcessInfo.processInfo.processIdentifier)",
        ]
        try process.run()
    }

    private func themeMarkerURL() -> URL? {
        repositoryRootURL()?.appendingPathComponent(themeMarkerFileName)
    }

    private func repositoryRootURL() -> URL? {
        if let persistedRootURL = persistedProjectRootURL() {
            return persistedRootURL
        }

        var candidate = Bundle.main.bundleURL.deletingLastPathComponent()

        while candidate.path != "/" {
            if isValidRepositoryRoot(candidate) {
                persistRepositoryRoot(candidate)
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        return nil
    }

    private func persistedProjectRootURL() -> URL? {
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fileURL = applicationSupportURL
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(projectRootFileName)
        guard let path = try? String(contentsOf: fileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        let candidates = normalizedPersistedPathCandidates(from: path)
        for candidatePath in candidates {
            let url = URL(fileURLWithPath: candidatePath).standardizedFileURL
            guard isValidRepositoryRoot(url) else { continue }
            if candidatePath != path {
                persistRepositoryRoot(url)
            }
            return url
        }

        return nil
    }

    private func persistRepositoryRoot(_ url: URL) {
        guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let directoryURL = applicationSupportURL.appendingPathComponent(supportDirectoryName, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent(projectRootFileName)

        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? url.path.appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func isValidRepositoryRoot(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let packageURL = url.appendingPathComponent("Package.swift")
        let projectURL = url.appendingPathComponent("FloatyDo/FloatyDo.xcodeproj")
        return fileManager.fileExists(atPath: packageURL.path)
            && fileManager.fileExists(atPath: projectURL.path)
    }

    private func normalizedPersistedPathCandidates(from path: String) -> [String] {
        var candidates = [path]

        // Older local relaunch commands wrote "%s\\n" without shell quoting,
        // which persisted a trailing literal "n" instead of a newline.
        if path.hasSuffix("n") {
            candidates.append(String(path.dropLast()))
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}

extension PrimaryAppIconRelaunchController {
    enum RelaunchError: LocalizedError {
        case repositoryNotFound
        case scriptNotFound

        var errorDescription: String? {
            switch self {
            case .repositoryNotFound:
                return "FloatyDo couldn’t find its local project files."
            case .scriptNotFound:
                return "FloatyDo couldn’t find the icon relaunch script."
            }
        }
    }
}
#endif
