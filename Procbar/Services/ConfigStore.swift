import Foundation
import Combine
import os

final class ConfigStore {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "config")

    let path: URL
    private let stateQueue = DispatchQueue(label: "com.carlos.procbar.configstore.state")
    private var _current: Config = Config.defaultConfig()

    /// Thread-safe snapshot of the most recently loaded (valid) config.
    var current: Config { stateQueue.sync { _current } }

    private let changesSubject = PassthroughSubject<Config, Never>()
    /// Fires whenever the on-disk file is successfully parsed and differs from
    /// the last-known-good config (or when `save(_:)` writes new content).
    var changes: AnyPublisher<Config, Never> { changesSubject.eraseToAnyPublisher() }

    private let errorsSubject = CurrentValueSubject<String?, Never>(nil)
    /// Fires `String` when the on-disk file fails to parse, and `nil` on
    /// recovery. Subscribers drive the "config error" UI pill.
    var errors: AnyPublisher<String?, Never> { errorsSubject.eraseToAnyPublisher() }

    private var watchSource: DispatchSourceFileSystemObject?
    private var watchDescriptor: Int32 = -1
    private var watchQueue = DispatchQueue(label: "com.carlos.procbar.configwatch")
    private var debounceItem: DispatchWorkItem?

    init(path: URL) {
        self.path = path
    }

    static var defaultPath: URL {
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let base: URL = {
            if let xdg, !xdg.isEmpty {
                return URL(fileURLWithPath: PathUtils.expand(xdg), isDirectory: true)
            }
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".config", isDirectory: true)
        }()
        return base.appendingPathComponent("procbar", isDirectory: true)
                   .appendingPathComponent("config.yaml")
    }

    @discardableResult
    func loadOrCreateDefault() throws -> Config {
        if FileManager.default.fileExists(atPath: path.path) {
            return try reload()
        }
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let def = Config.defaultConfig()
        try save(def)
        stateQueue.sync { _current = def }
        return def
    }

    @discardableResult
    func reload() throws -> Config {
        let text = try String(contentsOf: path, encoding: .utf8)
        do {
            let cfg = try Config.decode(fromYAML: text)
            stateQueue.sync { _current = cfg }
            errorsSubject.send(nil)
            logger.info("Config reloaded")
            return cfg
        } catch {
            let msg = error.localizedDescription
            logger.error("Invalid YAML: \(msg, privacy: .public)")
            errorsSubject.send(msg)
            throw error
        }
    }

    func save(_ cfg: Config) throws {
        let text = try cfg.encodedYAML()
        try text.write(to: path, atomically: true, encoding: .utf8)
        stateQueue.sync { _current = cfg }
        changesSubject.send(cfg)
        errorsSubject.send(nil)
    }

    func startWatching() {
        stopWatching()
        let fd = open(path.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("Failed to open config for watching: \(String(cString: strerror(errno)), privacy: .public)")
            return
        }
        watchDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: watchQueue
        )
        source.setEventHandler { [weak self] in self?.handleFileEvent() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchDescriptor, fd >= 0 { close(fd) }
            self?.watchDescriptor = -1
        }
        source.resume()
        watchSource = source
    }

    func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
    }

    private func handleFileEvent() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let cfg = try self.reload()
                self.changesSubject.send(cfg)
            } catch {
                // reload() has already published the error.
            }
            // If file was deleted & recreated (atomic write), re-arm watch.
            if !FileManager.default.fileExists(atPath: self.path.path) {
                self.stopWatching()
            } else if self.watchSource == nil {
                self.startWatching()
            }
        }
        debounceItem = item
        watchQueue.asyncAfter(deadline: .now() + 0.15, execute: item)
    }
}
