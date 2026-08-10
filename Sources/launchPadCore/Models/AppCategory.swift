import Foundation

/// Coarse grouping of installed apps for the grid filter.
public enum AppCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case system
    case user
    case homebrew

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .all:
            NSLocalizedString("全部", comment: "Filter: all apps")
        case .system:
            NSLocalizedString("系统应用", comment: "Filter: system apps")
        case .user:
            NSLocalizedString("用户应用", comment: "Filter: user apps")
        case .homebrew:
            NSLocalizedString("开发工具", comment: "Filter: Homebrew-installed apps")
        }
    }

    public func contains(_ app: AppRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .system:
            return app.url.path.hasPrefix("/System/")
        case .user:
            let path = app.url.path
            return path.hasPrefix("/Applications/")
                || path.hasPrefix(
                    FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications", isDirectory: true)
                        .path
                )
        case .homebrew:
            let path = app.url.path
            return path.contains("/Caskroom/") || path.contains("/Cellar/")
        }
    }
}
