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
}
