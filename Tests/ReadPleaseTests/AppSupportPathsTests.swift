import Foundation
import XCTest
@testable import ReadPlease

final class AppSupportPathsTests: XCTestCase {
    func testProductionURLMigratesExistingStagingConfigWhenDestinationIsMissing() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stagingURL = rootURL
            .appendingPathComponent(AppSupportPaths.stagingFolderName)
            .appendingPathComponent("shortcuts.json")
        let productionURL = rootURL
            .appendingPathComponent(AppSupportPaths.productionFolderName)
            .appendingPathComponent("shortcuts.json")

        try FileManager.default.createDirectory(
            at: stagingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("staging-config".utf8).write(to: stagingURL, options: .atomic)

        let resolvedURL = AppSupportPaths.configFileURL(
            fileName: "shortcuts.json",
            bundleIdentifier: "com.onestepp.ReadPlease",
            rootURL: rootURL
        )

        XCTAssertEqual(resolvedURL, productionURL)
        XCTAssertEqual(try Data(contentsOf: productionURL), Data("staging-config".utf8))
    }

    func testProductionURLLeavesExistingDestinationUntouched() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stagingURL = rootURL
            .appendingPathComponent(AppSupportPaths.stagingFolderName)
            .appendingPathComponent("pronunciations.json")
        let productionURL = rootURL
            .appendingPathComponent(AppSupportPaths.productionFolderName)
            .appendingPathComponent("pronunciations.json")

        try FileManager.default.createDirectory(
            at: stagingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: productionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("staging".utf8).write(to: stagingURL, options: .atomic)
        try Data("production".utf8).write(to: productionURL, options: .atomic)

        _ = AppSupportPaths.configFileURL(
            fileName: "pronunciations.json",
            bundleIdentifier: "com.onestepp.ReadPlease",
            rootURL: rootURL
        )

        XCTAssertEqual(try Data(contentsOf: productionURL), Data("production".utf8))
    }

    func testStagingURLDoesNotCopyIntoProduction() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stagingURL = AppSupportPaths.configFileURL(
            fileName: "shortcuts.json",
            bundleIdentifier: "com.onestepp.ReadPlease.staging",
            rootURL: rootURL
        )

        XCTAssertEqual(
            stagingURL,
            rootURL
                .appendingPathComponent(AppSupportPaths.stagingFolderName)
                .appendingPathComponent("shortcuts.json")
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: rootURL
                    .appendingPathComponent(AppSupportPaths.productionFolderName)
                    .appendingPathComponent("shortcuts.json")
                    .path()
            )
        )
    }
}
