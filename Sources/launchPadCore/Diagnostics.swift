import Foundation

/// Appends lightweight diagnostic lines to `/tmp/launchpad-diagnostic.log`.
/// The logging body only exists in debug builds so gesture/activation issues
/// stay observable on a real trackpad; release builds compile the work out
/// and the call sites cost nothing.
enum Diagnostics {
    private static let logURL = URL(fileURLWithPath: "/tmp/launchpad-diagnostic.log")

    static func log(_ message: String) {
        #if DEBUG
        let line = "\(Date().description) \(message)\n"
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        #endif
    }
}
