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
}
