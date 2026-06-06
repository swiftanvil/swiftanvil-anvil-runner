import Foundation

/// Resolves paths relative to the anvil-runner project root.
///
/// This avoids hardcoding absolute paths so the tool works on any machine
/// where the repository is cloned.
public enum ProjectPaths {
    /// Returns the project root directory (the folder containing `Package.swift`).
    ///
    /// Resolution order:
    /// 1. `ANVIL_RUNNER_PROJECT_ROOT` environment variable.
    /// 2. Search upward from `#file` for a directory containing `Package.swift`.
    /// 3. Search upward from the current working directory.
    public static var projectRoot: String {
        if let envRoot = ProcessInfo.processInfo.environment["ANVIL_RUNNER_PROJECT_ROOT"],
           isProjectRoot(envRoot) {
            return envRoot
        }

        let sourceFile = URL(fileURLWithPath: #file)
        if let root = searchProjectRoot(from: sourceFile) {
            return root
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let root = searchProjectRoot(from: cwd) {
            return root
        }

        let sourceBased = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return sourceBased.path
    }

    /// Path to the release binary built by `swift build -c release`.
    public static var releaseBinary: String {
        URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(".build/release/anvil-runner")
            .path
    }

    // MARK: - Helpers

    private static func isProjectRoot(_ path: String) -> Bool {
        let packageSwift = URL(fileURLWithPath: path).appendingPathComponent("Package.swift").path
        return FileManager.default.fileExists(atPath: packageSwift)
    }

    private static func searchProjectRoot(from start: URL) -> String? {
        var current = start
        for _ in 0..<10 {
            if isProjectRoot(current.path) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }
}
