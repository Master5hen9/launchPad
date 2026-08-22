import Foundation

/// Watches the Launchpad's app directories for installs/uninstalls and posts
/// `didChangeNotification` after a short debounce, so an open Launchpad can
/// refresh its grid without a relaunch.
public final class AppDirectoryMonitor: @unchecked Sendable {
    public static let shared = AppDirectoryMonitor()
    public static let didChangeNotification = Notification.Name("launchPadAppDirectoriesDidChange")

    private let lock = NSLock()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var workItem: DispatchWorkItem?
    private let queue = DispatchQueue(
        label: "com.ming.launchpad.app-directory-monitor",
        qos: .utility
    )

    public func start() {
        lock.lock()
        guard sources.isEmpty else {
            lock.unlock()
            return
        }
        var started: [DispatchSourceFileSystemObject] = []
        for directory in AppScanner.searchDirectories {
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleChange()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            started.append(source)
        }
        sources = started
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        let sources = sources
        self.sources = []
        workItem?.cancel()
        workItem = nil
        lock.unlock()

        for source in sources {
            source.cancel()
        }
    }

    /// Coalesces bursts of filesystem events (an installer touches many
    /// files) into one notification.
    private func scheduleChange() {
        lock.lock()
        workItem?.cancel()
        let item = DispatchWorkItem {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            // The debounce only watches the app-directory itself, so large
            // installs are still copying (lproj localizations arrive last)
            // when this first scan runs. Rescan once more after the copy has
            // had time to finish so localized names show up without a restart.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6.0) {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
        workItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
