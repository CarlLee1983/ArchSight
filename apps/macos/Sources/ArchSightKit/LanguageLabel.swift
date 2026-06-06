import Foundation

/// Maps a file path to a human-readable language name for the status bar, the
/// way VSCode labels the active editor's language mode. AppKit-free and pure so
/// it is unit-testable. This is display-only; syntax highlighting routing is
/// decided independently by the core.
public enum LanguageLabel {
    /// Returns a display language name for `path`. Unknown extensions fall back to
    /// the uppercased extension; a path with no extension is "Plain Text".
    public static func forPath(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return "Plain Text" }
        return known[ext] ?? ext.uppercased()
    }

    private static let known: [String: String] = [
        "swift": "Swift",
        "go": "Go",
        "ts": "TypeScript",
        "tsx": "TypeScript JSX",
        "js": "JavaScript",
        "jsx": "JavaScript JSX",
        "mjs": "JavaScript",
        "cjs": "JavaScript",
        "py": "Python",
        "rs": "Rust",
        "java": "Java",
        "kt": "Kotlin",
        "kts": "Kotlin",
        "c": "C",
        "h": "C",
        "cpp": "C++",
        "cc": "C++",
        "cxx": "C++",
        "hpp": "C++",
        "hh": "C++",
        "m": "Objective-C",
        "mm": "Objective-C++",
        "rb": "Ruby",
        "php": "PHP",
        "cs": "C#",
        "scala": "Scala",
        "dart": "Dart",
        "lua": "Lua",
        "r": "R",
        "json": "JSON",
        "jsonc": "JSON with Comments",
        "yaml": "YAML",
        "yml": "YAML",
        "toml": "TOML",
        "ini": "INI",
        "xml": "XML",
        "html": "HTML",
        "htm": "HTML",
        "css": "CSS",
        "scss": "SCSS",
        "sass": "Sass",
        "less": "Less",
        "md": "Markdown",
        "markdown": "Markdown",
        "sh": "Shell Script",
        "bash": "Shell Script",
        "zsh": "Shell Script",
        "fish": "Shell Script",
        "sql": "SQL",
        "proto": "Protocol Buffers",
        "graphql": "GraphQL",
        "gql": "GraphQL",
        "dockerfile": "Dockerfile",
        "makefile": "Makefile",
        "txt": "Plain Text",
    ]
}
