import Foundation

/// Reads CPU-die temperature from the system's HID temperature sensors.
///
/// There is no public macOS API for per-core temperature. Every tool that
/// reports °C (iStats, Stats, smcFanControl) uses private IOKit surfaces.
/// This reader calls `IOHIDEventSystemClient*` functions that are
/// linked-but-unexposed in IOKit.framework. The symbols exist on every
/// modern macOS (they back Apple's own sensor daemons), but because
/// they're private they could theoretically change between OS releases.
///
/// Failure mode is always nil — the caller renders a placeholder. We do
/// not crash, do not throw, do not retry.
///
/// `read()` returns a **20-second rolling average** of the hottest CPU-class
/// temperature channel (package-max semantics smoothed over time). The raw
/// instantaneous readings can bounce 3–5 °C between ticks as a single core
/// wakes and sleeps; averaging over ~10 samples (at the default 2s refresh)
/// makes the displayed number feel stable without hiding real trends.
final class TemperatureReader {
    private struct Sample {
        let at: Date
        let value: Double
    }

    /// Initialized lazily and cached. Creating the client is the expensive
    /// part; the per-tick cost is just copying current values.
    private var client: HIDClient?
    private var services: [HIDService] = []
    private let setupLock = NSLock()

    /// Sliding window of recent readings. Pruned on every call to `read()`
    /// so the buffer size stays bounded by poll rate × window.
    private var samples: [Sample] = []
    private let windowSeconds: TimeInterval = 20

    func read() -> Double? {
        setupLock.lock()
        defer { setupLock.unlock() }
        ensureSetup()
        guard !services.isEmpty else { return nil }

        var max: Double = -Double.infinity
        for svc in services {
            guard let event = hidServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let v = hidEventGetFloatValue(event, kIOHIDEventFieldTemperature)
            // Sanity: drop impossible values and disconnected sensors.
            if v > 5 && v < 150 && v > max {
                max = v
            }
        }
        guard max != -Double.infinity else { return nil }

        let now = Date()
        samples.append(Sample(at: now, value: max))
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.at < cutoff }

        let sum = samples.reduce(0.0) { $0 + $1.value }
        return sum / Double(samples.count)
    }

    private func ensureSetup() {
        guard client == nil else { return }
        let matching: [String: Any] = [
            // kHIDPage_AppleVendor + kHIDUsage_AppleVendor_TemperatureSensor
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 0x0005,
        ]
        guard let c = hidEventSystemClientCreate(kCFAllocatorDefault) else { return }
        hidEventSystemClientSetMatching(c, matching as CFDictionary)
        client = c

        guard let rawServices = hidEventSystemClientCopyServices(c) else { return }
        services = (rawServices as NSArray).compactMap { $0 as HIDService }
    }
}

// MARK: - Private IOKit HID Event System bindings
//
// These symbols live in IOKit.framework but aren't declared in any public
// header. The types flow through as opaque references (AnyObject); the
// runtime retains them through CF/ARC bridging.

private typealias HIDClient = AnyObject
private typealias HIDService = AnyObject
private typealias HIDEvent = AnyObject

private let kIOHIDEventTypeTemperature: Int32 = 15
/// Field = (type << 16) | 0 — convention encoded in IOHIDEventFields.h.
private let kIOHIDEventFieldTemperature: Int32 = 15 << 16

@_silgen_name("IOHIDEventSystemClientCreate")
private func hidEventSystemClientCreate(_ allocator: CFAllocator?) -> HIDClient?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func hidEventSystemClientSetMatching(_ client: HIDClient, _ matching: CFDictionary)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func hidEventSystemClientCopyServices(_ client: HIDClient) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func hidServiceClientCopyEvent(_ service: HIDService, _ type: Int32, _ options: Int32, _ timestamp: Int64) -> HIDEvent?

@_silgen_name("IOHIDEventGetFloatValue")
private func hidEventGetFloatValue(_ event: HIDEvent, _ field: Int32) -> Double
