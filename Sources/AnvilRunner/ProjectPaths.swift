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
    /// 2. Search upward from the current working directory (most reliable at
    ///    runtime because `swift run` and the built binary are executed from
    ///    the project root).
    /// 3. Search upward from `#file` as a compile-time fallback.
    public static var projectRoot: String {
        if let envRoot = ProcessInfo.processInfo.environment["ANVIL_RUNNER_PROJECT_ROOT"],
           isProjectRoot(envRoot) {
            return envRoot
        }

        // Primary: search upward from the current working directory.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let root = searchProjectRoot(from: cwd) {
            return root
        }

        // Fallback: search upward from this source file.
        let sourceFile = URL(fileURLWithPath: #file)
        if let root = searchProjectRoot(from: sourceFile) {
            return root
        }

        return sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    /// Path to the built binary.
    ///
    /// Checks both release and debug build directories so that `swift run`
    /// (debug) and `swift build -c release` (release) both work without
    /// requiring a rebuild.
    public static var releaseBinary: String {
        let candidates = [
            URL(fileURLWithPath: projectRoot).appendingPathComponent(".build/release/anvil-runner").path,
            URL(fileURLWithPath: projectRoot).appendingPathComponent(".build/debug/anvil-runner").path,
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? candidates[0]
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
