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
        for path in ["/Users/test/Downloads/HushTranslate.app", "/Applications Backup/HushTranslate.app"] {
            XCTAssertTrue(AppInstallation.needsInstallation(at: URL(fileURLWithPath: path), applicationsDirectories: directories))
        }
        XCTAssertFalse(AppInstallation.needsInstallation(at: URL(fileURLWithPath: "/tmp/debug/HushTranslate"), applicationsDirectories: directories))
    }

    func testMovePreservesContentsAndCanBeRolledBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Installed.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("bundle contents".utf8).write(to: source.appendingPathComponent("payload"))
        try AppInstallation.move(from: source, to: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("payload")), "bundle contents")
        try AppInstallation.move(from: destination, to: source)
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("payload")), "bundle contents")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testExistingDestinationIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source.app")
        let destination = root.appendingPathComponent("Installed.app")
        try Data("new".utf8).write(to: source)
        try Data("existing".utf8).write(to: destination)
        XCTAssertThrowsError(try AppInstallation.move(from: source, to: destination))
        XCTAssertEqual(try String(contentsOf: source), "new")
        XCTAssertEqual(try String(contentsOf: destination), "existing")
    }
}
