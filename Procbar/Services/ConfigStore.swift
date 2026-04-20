import Foundation
import Combine
import os

final class ConfigStore {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "config")

    private let path: URL
    private(set) var current: Config = Config.defaultConfig()

    private let subject = PassthroughSubject<Config, Never>()
    var changes: AnyPublisher<Config, Never> { subject.eraseToAnyPublisher() }

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
        current = def
        return def
    }

    @discardableResult
    func reload() throws -> Config {
        let text = try String(contentsOf: path, encoding: .utf8)
        do {
            let cfg = try Config.decode(fromYAML: text)
            current = cfg
            logger.info("Config reloaded")
            return cfg
        } catch {
            logger.error("Invalid YAML: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func save(_ cfg: Config) throws {
        let text = try cfg.encodedYAML()
        try text.write(to: path, atomically: true, encoding: .utf8)
        current = cfg
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
                self.subject.send(cfg)
            } catch {
                // keep last-good, don't publish
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
