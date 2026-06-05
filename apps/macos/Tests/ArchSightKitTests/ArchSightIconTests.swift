import XCTest
import SwiftUI
@testable import ArchSightKit

final class ArchSightIconTests: XCTestCase {
    func testCustomIconsCompileAndCanBeInstantiated() {
        _ = ArchSightIcon.Folder()
        _ = ArchSightIcon.FolderOpen()
        _ = ArchSightIcon.File()
        _ = ArchSightIcon.Search()
        _ = ArchSightIcon.Explorer()
        _ = ArchSightIcon.Settings()
        _ = ArchSightIcon.Close()
        _ = ArchSightIcon.StatusIndicator(color: .green, pulsing: true)
        XCTAssertTrue(true)
    }
}
