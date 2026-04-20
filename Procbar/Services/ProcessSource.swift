import Foundation

protocol ProcessSource {
    /// Cheap: all processes with PID/PPID/name/command.
    func listAll() -> [RawProcess]

    /// Expensive: details for the given PIDs only. Missing PIDs are omitted.
    func fetchDetails(for pids: [Int32]) -> [Int32: ProcessDetail]
}
