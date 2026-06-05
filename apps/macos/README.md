# ArchSight macOS App

This directory will contain the native SwiftUI/AppKit shell.

Phase 0 intentionally does not scaffold the Xcode or Swift package project yet. The app layer must remain focused on native presentation, read-only navigation, workspace browsing, tabs, split views, search UI, and explicit user-triggered symbol navigation.

Heavy filesystem scanning, search execution, syntax parsing, LSP process management, and protocol orchestration belong in `core/`.
