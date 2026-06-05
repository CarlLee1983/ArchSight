import XCTest
@testable import ArchSightKit

final class AppStateTests: XCTestCase {
    func testInitialStateHasNoEditingAffordances() {
        let state = WorkspaceViewState()

        XCTAssertTrue(state.roots.isEmpty)
        XCTAssertTrue(state.openTabs.isEmpty)
        XCTAssertFalse(state.allowsEditing)
        XCTAssertFalse(state.showsDiagnostics)
        XCTAssertFalse(state.showsCodeActions)
    }

    func testOpeningFileCreatesReadOnlyTab() {
        var state = WorkspaceViewState()
        state.openFile(rootID: "root_1", path: "Sources/App.swift", content: "import SwiftUI\n")

        XCTAssertEqual(state.openTabs.count, 1)
        XCTAssertEqual(state.openTabs.first?.path, "Sources/App.swift")
        XCTAssertTrue(state.openTabs.first?.isReadOnly ?? false)
    }

    func testReopeningSameFileSelectsExistingTabWithoutDuplicating() {
        var state = WorkspaceViewState()
        state.openFile(rootID: "root_1", path: "Sources/App.swift", content: "v1")
        state.selectedTabID = nil
        state.openFile(rootID: "root_1", path: "Sources/App.swift", content: "v1")

        XCTAssertEqual(state.openTabs.count, 1)
        XCTAssertEqual(state.selectedTabID, "root_1:Sources/App.swift")
    }

    func testClosingSelectedTabSelectsNextNeighbor() {
        var state = WorkspaceViewState()
        state.openFile(rootID: "r", path: "a", content: "")
        state.openFile(rootID: "r", path: "b", content: "")
        state.openFile(rootID: "r", path: "c", content: "")
        state.selectedTabID = "r:b"

        state.closeTab(id: "r:b")

        XCTAssertEqual(state.openTabs.map(\.path), ["a", "c"])
        XCTAssertEqual(state.selectedTabID, "r:c")
    }

    func testClosingLastSelectedTabSelectsPrevious() {
        var state = WorkspaceViewState()
        state.openFile(rootID: "r", path: "a", content: "")
        state.openFile(rootID: "r", path: "b", content: "")
        state.selectedTabID = "r:b"

        state.closeTab(id: "r:b")

        XCTAssertEqual(state.selectedTabID, "r:a")
    }

    func testClosingOnlyTabClearsSelection() {
        var state = WorkspaceViewState()
        state.openFile(rootID: "r", path: "a", content: "")

        state.closeTab(id: "r:a")

        XCTAssertTrue(state.openTabs.isEmpty)
        XCTAssertNil(state.selectedTabID)
    }

    func testClosingNonSelectedTabKeepsSelection() {
        var state = WorkspaceViewState()
        state.openFile(rootID: "r", path: "a", content: "")
        state.openFile(rootID: "r", path: "b", content: "")
        state.selectedTabID = "r:b"

        state.closeTab(id: "r:a")

        XCTAssertEqual(state.selectedTabID, "r:b")
    }

    func testSelectNextTabWrapsAround() {
        var state = WorkspaceViewState()
        state.openFile(rootID: "r", path: "a", content: "")
        state.openFile(rootID: "r", path: "b", content: "")
        state.selectedTabID = "r:b"

        state.selectNextTab()

        XCTAssertEqual(state.selectedTabID, "r:a")
    }

    func testSelectPreviousTabWrapsAround() {
        var state = WorkspaceViewState()
        state.openFile(rootID: "r", path: "a", content: "")
        state.openFile(rootID: "r", path: "b", content: "")
        state.selectedTabID = "r:a"

        state.selectPreviousTab()

        XCTAssertEqual(state.selectedTabID, "r:b")
    }

    func testOpenFileCarriesTokens() {
        let json = """
        {"startLine":1,"startColumn":1,"endLine":1,"endColumn":5,"type":"keyword"}
        """.data(using: .utf8)!
        let token = try! JSONDecoder().decode(SyntaxToken.self, from: json)
        var state = WorkspaceViewState()
        state.openFile(rootID: "r", path: "main.go", content: "func x() {}", tokens: [token])
        XCTAssertEqual(state.openTabs.first?.tokens, [token])
    }

    func testMarkdownPreviewEligibilityUsesCommonMarkdownExtensions() {
        let readme = FileTab(rootID: "r", path: "README.md", content: "# Title")
        let note = FileTab(rootID: "r", path: "docs/Decision.MarkDown", content: "# Title")
        let swift = FileTab(rootID: "r", path: "Sources/App.swift", content: "import SwiftUI")

        XCTAssertTrue(readme.canPreviewMarkdown)
        XCTAssertTrue(note.canPreviewMarkdown)
        XCTAssertFalse(swift.canPreviewMarkdown)
    }

    func testBuildsHierarchicalWorkspaceTreeFromFlattenedEntries() {
        let root = WorkspaceRoot(id: "root_1", name: "service", path: "/tmp/service")
        let state = WorkspaceViewState(
            roots: [root],
            entries: [
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/service", path: "README.md", name: "README.md", kind: "file"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/service", path: "Sources", name: "Sources", kind: "directory"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/service", path: "Sources/App.swift", name: "App.swift", kind: "file"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/service", path: "Sources/Views", name: "Views", kind: "directory"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/service", path: "Sources/Views/MainView.swift", name: "MainView.swift", kind: "file")
            ]
        )

        let tree = state.treeEntries(for: root)

        XCTAssertEqual(tree.map(\.name), ["Sources", "README.md"])
        XCTAssertTrue(tree[0].isDirectory)
        XCTAssertEqual(tree[0].children.map(\.name), ["Views", "App.swift"])
        XCTAssertEqual(tree[0].children[0].children.map(\.name), ["MainView.swift"])
    }

    func testWorkspaceTreeSortsRootFoldersBeforeFilesLikeVSCode() {
        let root = WorkspaceRoot(id: "root_1", name: "ArchSight", path: "/tmp/ArchSight")
        let state = WorkspaceViewState(
            roots: [root],
            entries: [
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/ArchSight", path: ".gitignore", name: ".gitignore", kind: "file"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/ArchSight", path: "AGENTS.md", name: "AGENTS.md", kind: "file"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/ArchSight", path: "apps", name: "apps", kind: "directory"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/ArchSight", path: ".omx", name: ".omx", kind: "directory"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/ArchSight", path: "core", name: "core", kind: "directory"),
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/ArchSight", path: "README.md", name: "README.md", kind: "file")
            ]
        )

        let tree = state.treeEntries(for: root)

        XCTAssertEqual(tree.map(\.name), [".omx", "apps", "core", ".gitignore", "AGENTS.md", "README.md"])
        XCTAssertEqual(tree.map(\.isDirectory), [true, true, true, false, false, false])
    }

    func testRemoveRootDropsRootEntriesAndItsTabs() {
        var state = WorkspaceViewState(
            workspaceId: "ws_1",
            roots: [
                WorkspaceRoot(id: "root_1", name: "a", path: "/tmp/a"),
                WorkspaceRoot(id: "root_2", name: "b", path: "/tmp/b"),
            ],
            entries: [
                WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/a", path: "a.txt", name: "a.txt", kind: "file"),
                WorkspaceEntry(rootId: "root_2", rootPath: "/tmp/b", path: "b.txt", name: "b.txt", kind: "file"),
            ]
        )
        state.openFile(rootID: "root_1", path: "a.txt", content: "a")
        state.openFile(rootID: "root_2", path: "b.txt", content: "b")
        // selectedTabID is now root_2:b.txt

        state.removeRoot(id: "root_1")

        XCTAssertEqual(state.roots.map(\.id), ["root_2"])
        XCTAssertTrue(state.entries.allSatisfy { $0.rootId == "root_2" })
        XCTAssertEqual(state.openTabs.map(\.rootID), ["root_2"])
        XCTAssertEqual(state.selectedTabID, "root_2:b.txt")
    }

    func testRemoveRootClearsSelectionWhenSelectedTabRemoved() {
        var state = WorkspaceViewState(
            workspaceId: "ws_1",
            roots: [WorkspaceRoot(id: "root_1", name: "a", path: "/tmp/a")],
            entries: []
        )
        state.openFile(rootID: "root_1", path: "a.txt", content: "a")
        state.removeRoot(id: "root_1")
        XCTAssertTrue(state.openTabs.isEmpty)
        XCTAssertNil(state.selectedTabID)
    }

    func testRemoveRootRepairsSelectionToSurvivingTab() {
        var state = WorkspaceViewState(
            workspaceId: "ws_1",
            roots: [
                WorkspaceRoot(id: "root_1", name: "a", path: "/tmp/a"),
                WorkspaceRoot(id: "root_2", name: "b", path: "/tmp/b"),
            ],
            entries: []
        )
        state.openFile(rootID: "root_1", path: "f.txt", content: "")
        state.openFile(rootID: "root_2", path: "g.txt", content: "")
        state.selectedTabID = "root_1:f.txt"   // select the tab about to be removed

        state.removeRoot(id: "root_1")

        XCTAssertEqual(state.selectedTabID, "root_2:g.txt")
    }

    func testCloseWorkspaceClearsEverythingIncludingWorkspaceId() {
        let searchMatch = try! JSONDecoder().decode(SearchMatch.self, from: """
        {"rootId":"root_1","rootPath":"/tmp/a","path":"a.txt","line":1,"column":1,"preview":"hit","ranges":[]}
        """.data(using: .utf8)!)
        var state = WorkspaceViewState(
            workspaceId: "ws_1",
            roots: [WorkspaceRoot(id: "root_1", name: "a", path: "/tmp/a")],
            entries: [WorkspaceEntry(rootId: "root_1", rootPath: "/tmp/a", path: "a.txt", name: "a.txt", kind: "file")]
        )
        state.openFile(rootID: "root_1", path: "a.txt", content: "a")
        state.searchQuery = "todo"
        state.searchResults = [searchMatch]
        state.references = [
            Location(rootId: "root_1", rootPath: "/tmp/a", path: "a.txt",
                     startLine: 1, startColumn: 1, endLine: 1, endColumn: 4)
        ]
        state.referencesContext = "a.txt:1"
        state.isLoading = true
        state.errorMessage = "boom"

        state.closeWorkspace()

        XCTAssertNil(state.workspaceId)
        XCTAssertTrue(state.roots.isEmpty)
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertTrue(state.openTabs.isEmpty)
        XCTAssertNil(state.selectedTabID)
        XCTAssertEqual(state.searchQuery, "")
        XCTAssertTrue(state.searchResults.isEmpty)
        XCTAssertTrue(state.references.isEmpty)
        XCTAssertNil(state.referencesContext)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.errorMessage)
    }
}
