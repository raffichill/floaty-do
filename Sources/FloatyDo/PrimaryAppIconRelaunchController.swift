#if canImport(AppKit)
import AppKit
import Foundation

final class PrimaryAppIconRelaunchController {
    static let shared = PrimaryAppIconRelaunchController()

    private enum Constants {
        static let themeMarkerFileName = ".floatydo-primary-icon-theme"
        static let supportDirectoryName = "FloatyDo"
        static let projectRootFileName = "project-root.txt"
        static let scriptsPath = "scripts"
        static let iconApplyScriptName = "apply_primary_icon_and_relaunch.sh"
        static let xcodeProjectPath = "FloatyDo/FloatyDo.xcodeproj"
    }

    private let fileManager = FileManager.default
    private let bashPath = "/bin/bash"
    private var cachedRepositoryRoot: URL?

    private init() {}

    func currentTheme() -> BuiltInTheme {
        guard let markerURL = repositoryRootURL().flatMap(themeMarkerURL),
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

    func iconApplyProcess(for theme: BuiltInTheme) throws -> Process {
        guard let repoRootURL = repositoryRootURL() else {
            throw RelaunchError.repositoryNotFound
        }

        let scriptURL = try iconApplyScriptURL(in: repoRootURL)
        guard fileManager.isExecutableFile(atPath: scriptURL.path) else {
            throw RelaunchError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bashPath)
        process.arguments = [
            scriptURL.path,
            repoRootURL.path,
            theme.rawValue,
            "\(ProcessInfo.processInfo.processIdentifier)",
        ]
        return process
    }

    private func themeMarkerURL(for repositoryRoot: URL) -> URL {
        repositoryRoot.appendingPathComponent(Constants.themeMarkerFileName)
    }

    private func repositoryRootURL() -> URL? {
        if let cachedRepositoryRoot {
            return cachedRepositoryRoot
        }

        if let persistedRootURL = persistedProjectRootURL() {
            cachedRepositoryRoot = persistedRootURL
            return persistedRootURL
        }

        var candidate = Bundle.main.bundleURL.deletingLastPathComponent()

        while candidate.path != "/" {
            if isValidRepositoryRoot(candidate) {
                cacheAndPersistRepositoryRoot(candidate)
                cachedRepositoryRoot = candidate
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        return nil
    }

    private func persistedProjectRootURL() -> URL? {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fileURL = applicationSupportURL
            .appendingPathComponent(Constants.supportDirectoryName, isDirectory: true)
            .appendingPathComponent(Constants.projectRootFileName)

        guard let rootFileContents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let trimmed = rootFileContents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidates = normalizedPersistedPathCandidates(from: trimmed)
        for candidatePath in candidates {
            let url = URL(fileURLWithPath: candidatePath).standardizedFileURL
            guard isValidRepositoryRoot(url) else { continue }
            if candidatePath != trimmed {
                cacheAndPersistRepositoryRoot(url)
            }
            cachedRepositoryRoot = url
            return url
        }

        return nil
    }

    private func cacheAndPersistRepositoryRoot(_ url: URL) {
        cachedRepositoryRoot = url

        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let directoryURL = applicationSupportURL.appendingPathComponent(Constants.supportDirectoryName, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent(Constants.projectRootFileName)

        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? url.path.appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func isValidRepositoryRoot(_ url: URL) -> Bool {
        let packageURL = url.appendingPathComponent("Package.swift")
        let projectURL = url.appendingPathComponent(Constants.xcodeProjectPath)
        return fileManager.fileExists(atPath: packageURL.path)
            && fileManager.fileExists(atPath: projectURL.path)
    }

    private func iconApplyScriptURL(in repositoryRoot: URL) throws -> URL {
        let scriptURL = repositoryRoot
            .appendingPathComponent(Constants.scriptsPath)
            .appendingPathComponent(Constants.iconApplyScriptName)
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw RelaunchError.scriptNotFound
        }
        return scriptURL
    }

    func previewImage(for theme: BuiltInTheme) -> NSImage? {
        guard let repositoryRootURL = repositoryRootURL() else { return nil }
        let previewURL = repositoryRootURL
            .appendingPathComponent("FloatyDo/FloatyDo/Icons")
            .appendingPathComponent("\(theme.rawValue).icon")
            .appendingPathComponent("Assets")
            .appendingPathComponent("\(theme.rawValue).png")
        guard fileManager.fileExists(atPath: previewURL.path) else { return nil }
        return NSImage(contentsOf: previewURL)
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
