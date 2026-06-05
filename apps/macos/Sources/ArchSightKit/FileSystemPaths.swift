/// Pure path helpers for the workspace sidebar. Side-effect-free so they can be
/// unit-tested; AppKit actions (Finder reveal, pasteboard) live in the App target.
public enum FileSystemPaths {
    /// Path of `path` relative to `rootPath`. Returns "" when they are equal and
    /// falls back to the original `path` when `path` is not under `rootPath`.
    public static func relative(of path: String, under rootPath: String) -> String {
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        if path == normalizedRoot { return "" }
        let prefix = normalizedRoot + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }
}
