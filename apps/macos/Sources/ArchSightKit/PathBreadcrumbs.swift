import Foundation

/// Splits a file path into display segments for a VSCode-style breadcrumb bar.
/// Pure and separator-only so it stays testable and independent of the filesystem.
public enum PathBreadcrumbs {
    /// Path components in order, dropping empty pieces so a leading slash or
    /// doubled separators never produce blank crumbs. Returns `[]` for an empty path.
    public static func segments(for path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
