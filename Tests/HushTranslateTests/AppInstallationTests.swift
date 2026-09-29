import XCTest
@testable import HushTranslate

final class AppInstallationTests: XCTestCase {
    private let directories = [URL(fileURLWithPath: "/Applications"),
                               URL(fileURLWithPath: "/Users/test/Applications")]

    func testInstallationLocationBoundaries() {
        for path in ["/Applications/HushTranslate.app", "/Applications/Utilities/HushTranslate.app",
                     "/Users/test/Applications/HushTranslate.app"] {
            XCTAssertFalse(AppInstallation.needsInstallation(at: URL(fileURLWithPath: path), applicationsDirectories: directories))
        }
        for path in ["/Users/test/Downloads/HushTranslate.app", "/Applications Backup/HushTranslate.app",
                     "/private/tmp/AppTranslocation/UUID/d/HushTranslate.app"] {
            XCTAssertTrue(AppInstallation.needsInstallation(at: URL(fileURLWithPath: path), applicationsDirectories: directories))
        }
        XCTAssertFalse(AppInstallation.needsInstallation(at: URL(fileURLWithPath: "/tmp/debug/HushTranslate"), applicationsDirectories: directories))
    }
}
