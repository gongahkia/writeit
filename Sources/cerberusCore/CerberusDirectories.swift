import Foundation

public enum CerberusDirectories {
    public static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent(CerberusCore.appName, isDirectory: true)
    }

    public static func cachesDirectory(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        return baseURL.appendingPathComponent(CerberusCore.appName, isDirectory: true)
    }

    public static func applicationSupportFile(_ name: String, fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager).appendingPathComponent(name, isDirectory: false)
    }

    public static func applicationSupportSubdirectory(_ name: String, fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager).appendingPathComponent(name, isDirectory: true)
    }

    public static func cacheSubdirectory(_ name: String, fileManager: FileManager = .default) -> URL {
        cachesDirectory(fileManager: fileManager).appendingPathComponent(name, isDirectory: true)
    }
}
