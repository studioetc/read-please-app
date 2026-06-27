import Foundation

enum AppSupportPaths {
    static let productionFolderName = "ReadPlease"
    static let stagingFolderName = "ReadPlease-Staging"

    static func configFileURL(
        fileName: String,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) -> URL {
        let resolvedRootURL = rootURL ?? defaultApplicationSupportRoot(fileManager: fileManager)
        let isStaging = bundleIdentifier?.contains(".staging") == true
        let appFolderName = isStaging ? stagingFolderName : productionFolderName
        let destinationURL = resolvedRootURL
            .appending(path: appFolderName)
            .appending(path: fileName)

        guard !isStaging else { return destinationURL }

        migrateStagingConfigIfNeeded(
            fileName: fileName,
            destinationURL: destinationURL,
            fileManager: fileManager,
            rootURL: resolvedRootURL
        )

        return destinationURL
    }

    private static func migrateStagingConfigIfNeeded(
        fileName: String,
        destinationURL: URL,
        fileManager: FileManager,
        rootURL: URL
    ) {
        guard !fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) else { return }

        let stagingURL = rootURL
            .appending(path: stagingFolderName)
            .appending(path: fileName)

        guard fileManager.fileExists(atPath: stagingURL.path(percentEncoded: false)) else { return }

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: stagingURL, to: destinationURL)
            print("Migrated \(fileName) from staging Application Support into production.")
        } catch {
            print("Failed to migrate \(fileName) from staging: \(error)")
        }
    }

    private static func defaultApplicationSupportRoot(fileManager: FileManager) -> URL {
        (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
    }
}
