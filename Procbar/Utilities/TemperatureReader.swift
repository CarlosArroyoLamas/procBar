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
/// `read()` returns the **maximum** sensor reading from all CPU-class
/// temperature channels (package-max semantics). On a dev Mac the hottest
/// sensor is almost always the busy CPU cluster; on an idle machine it
/// drifts to whatever happens to be warmest.
final class TemperatureReader {
    /// Initialized lazily and cached. Creating the client is the expensive
    /// part; the per-tick cost is just copying current values.
    private var client: HIDClient?
    private var services: [HIDService] = []
    private let setupLock = NSLock()

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
        return max == -Double.infinity ? nil : max
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
