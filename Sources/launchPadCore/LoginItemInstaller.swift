import Foundation

/// Installs the app as a login item by packaging the running executable into
/// `~/Applications/launchPad.app` and registering a user LaunchAgent.
///
/// The agent takes effect at the next login, so installing from a running app
/// does not spawn a second instance immediately.
public enum LoginItemInstaller {
    public static let appName = "launchPad"
    public static let bundleIdentifier = "com.ming.launchpad"

    public static var installedAppURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/\(appName).app", isDirectory: true)
    }

    public static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleIdentifier).plist")
    }

    public enum InstallError: Error, LocalizedError {
        case missingExecutable
        case commandFailed(String, String)

        public var errorDescription: String? {
            switch self {
            case .missingExecutable:
                NSLocalizedString("找不到应用可执行文件。", comment: "Login item install error")
            case .commandFailed(let command, let output):
                String(
                    format: NSLocalizedString("%@ 失败:%@", comment: "Command failed with output"),
                    command,
                    output
                )
            }
        }
    }

    public static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    public static func install() throws {
        guard let executablePath = Bundle.main.executablePath else {
            throw InstallError.missingExecutable
        }

        let appURL = installedAppURL
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let targetURL = macosURL.appendingPathComponent(appName)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: executablePath), to: targetURL)

        // Bundle the app icon so the installed app shows a real icon instead of
        // the generic executable placeholder.
        if let iconURL = AppAssets.iconURL {
            let iconTarget = resourcesURL.appendingPathComponent("AppIcon.icns")
            if FileManager.default.fileExists(atPath: iconTarget.path) {
                try FileManager.default.removeItem(at: iconTarget)
            }
            try FileManager.default.copyItem(at: iconURL, to: iconTarget)
        }

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": appName,
            "CFBundleDisplayName": "launchPad",
            "CFBundleExecutable": appName,
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.4.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "26.0",
            "NSHighResolutionCapable": true
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        // Prefer the stable local identity ("launchPad Local") so TCC grants
        // such as Accessibility survive reinstalls; fall back to ad-hoc when
        // that identity is not installed on the machine.
        let stableIdentity = "launchPad Local"
        let signedWithStableIdentity = (try? run(
            "/usr/bin/codesign",
            ["--force", "--sign", stableIdentity, appURL.path]
        )) != nil
        if !signedWithStableIdentity {
            try run("/usr/bin/codesign", ["--force", "--sign", "-", appURL.path])
        }

        let agentPlist: [String: Any] = [
            "Label": bundleIdentifier,
            "ProgramArguments": [targetURL.path],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let agentData = try PropertyListSerialization.data(fromPropertyList: agentPlist, format: .xml, options: 0)
        try agentData.write(to: agentPlistURL)
    }

    public static func uninstall() throws {
        // Ignore errors: the agent may not be loaded in the current session.
        _ = try? run("/bin/launchctl", ["bootout", "gui/\(getuid())", agentPlistURL.path])
        if FileManager.default.fileExists(atPath: agentPlistURL.path) {
            try FileManager.default.removeItem(at: agentPlistURL)
        }
    }

    @discardableResult
    private static func run(_ command: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw InstallError.commandFailed(command, output)
        }
        return output
    }
}
