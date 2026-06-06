import Foundation

/// Builds the environment handed to the spawned `archsight-core` process.
///
/// A GUI app launched from Finder (or Homebrew) inherits the *empty* launchd
/// `PATH`, so the process tree only sees the minimal `/usr/bin:/bin:/usr/sbin:/sbin`.
/// The core resolves language servers via `exec.LookPath`, which means `gopls`,
/// `typescript-language-server`, and friends — typically under Homebrew or the
/// Go bin directory — become invisible and all symbol navigation silently fails.
///
/// This augments `PATH` with the common developer-tool locations *without*
/// removing or reordering anything the user explicitly set, so symbol features
/// work from a packaged build the same way they do under `swift run`.
public enum CoreLaunchEnvironment {
    /// Directories that commonly hold language servers but are absent from the
    /// minimal PATH a GUI process inherits. `home`/`gopath` are interpolated by
    /// `resolvedEnvironment` so the list stays a pure function of its inputs.
    static func candidateDirectories(home: String, gopath: String?) -> [String] {
        var dirs = [
            "/opt/homebrew/bin", // Apple Silicon Homebrew
            "/usr/local/bin",    // Intel Homebrew + manual installs
        ]
        if let gopath, !gopath.isEmpty {
            dirs.append("\(gopath)/bin")
        }
        dirs.append("\(home)/go/bin")   // default GOPATH/bin
        dirs.append("\(home)/.local/bin")
        return dirs
    }

    /// Returns `base` with `PATH` extended to include any missing
    /// `candidateDirectories`. Existing entries keep their position and priority;
    /// candidates are appended only when absent, so system tools are never shadowed.
    public static func resolvedEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [String: String] {
        var env = base
        var ordered = (env["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        let seen = Set(ordered)
        var appended = seen
        for dir in candidateDirectories(home: home, gopath: env["GOPATH"]) where !appended.contains(dir) {
            ordered.append(dir)
            appended.insert(dir)
        }
        env["PATH"] = ordered.joined(separator: ":")
        return env
    }
}
