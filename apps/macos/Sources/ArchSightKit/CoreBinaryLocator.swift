import Foundation

/// Resolves the `archsight-core` executable the app should launch. Resolution
/// order is:
///
/// 1. The `ARCHSIGHT_CORE_PATH` environment override (development and explicit
///    overrides win first).
/// 2. A binary bundled inside the app at `Contents/Resources/bin/archsight-core`.
/// 3. A binary placed next to the running app executable.
///
/// Keeping discovery in one tested type lets the packaged `.app` run with no
/// configuration while `swift run`/`swift build` development keeps working
/// through the environment override.
public enum CoreBinaryLocator {
    /// Environment override for the core executable path.
    public static let environmentKey = "ARCHSIGHT_CORE_PATH"

    /// File name of the core executable as bundled or built.
    public static let executableName = "archsight-core"

    /// Subdirectory under the app bundle resources that holds bundled binaries.
    public static let bundledSubdirectory = "bin"

    /// Resolve the core executable URL, or `nil` when no candidate exists.
    ///
    /// - Parameters:
    ///   - environment: process environment, injectable for tests.
    ///   - resourceDirectory: the bundle resource directory, e.g.
    ///     `Bundle.main.resourceURL`. A bundled binary is expected at
    ///     `resourceDirectory/bin/archsight-core`.
    ///   - executableDirectory: the directory of the running app executable,
    ///     e.g. `Bundle.main.executableURL?.deletingLastPathComponent()`.
    ///   - fileExists: existence probe, injectable for tests.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        resourceDirectory: URL? = Bundle.main.resourceURL,
        executableDirectory: URL? = Bundle.main.executableURL?.deletingLastPathComponent(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        if let override = environment[environmentKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        if let resourceDirectory {
            let bundled = resourceDirectory
                .appendingPathComponent(bundledSubdirectory, isDirectory: true)
                .appendingPathComponent(executableName)
            if fileExists(bundled.path) {
                return bundled
            }
        }

        if let executableDirectory {
            let sibling = executableDirectory.appendingPathComponent(executableName)
            if fileExists(sibling.path) {
                return sibling
            }
        }

        return nil
    }
}
