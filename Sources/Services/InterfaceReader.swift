import Darwin
import Foundation
import SystemConfiguration

/// One reading of a network interface's link-layer byte counters and IPv4 address.
struct InterfaceSnapshot {
    let name: String
    let inBytes: UInt32
    let outBytes: UInt32
    let isActive: Bool
    let isLoopback: Bool
    var ipv4: String?
}

/// Reads per-interface byte counters via `getifaddrs` and resolves friendly names via SystemConfiguration.
enum InterfaceReader {
    /// Returns a snapshot of every interface, keyed by BSD name (e.g. `en0`).
    static func snapshot() -> [String: InterfaceSnapshot] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var result: [String: InterfaceSnapshot] = [:]
        var addresses: [String: String] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let entry = pointer.pointee
            cursor = entry.ifa_next
            guard let addr = entry.ifa_addr else { continue }
            let name = String(cString: entry.ifa_name)
            let flags = Int32(entry.ifa_flags)

            if addr.pointee.sa_family == UInt8(AF_LINK), let raw = entry.ifa_data {
                let data = raw.assumingMemoryBound(to: if_data.self).pointee
                result[name] = InterfaceSnapshot(
                    name: name,
                    inBytes: data.ifi_ibytes,
                    outBytes: data.ifi_obytes,
                    isActive: flags & IFF_UP != 0 && flags & IFF_RUNNING != 0,
                    isLoopback: flags & IFF_LOOPBACK != 0
                )
            } else if addr.pointee.sa_family == UInt8(AF_INET), addresses[name] == nil {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    addresses[name] = String(cString: host)
                }
            }
        }
        for (name, ip) in addresses { result[name]?.ipv4 = ip }
        return result
    }

    /// Difference between two 32-bit counter readings.
    /// A backwards step near the top of the range is a wraparound; anything else is a counter reset and counts as zero.
    static func delta(old: UInt32, new: UInt32) -> UInt64 {
        if new >= old { return UInt64(new - old) }
        if old > UInt32.max / 4 * 3 {
            return UInt64(UInt32.max - old) + UInt64(new) + 1
        }
        return 0
    }

    /// Localized names such as "Wi-Fi" or "Thunderbolt Ethernet", keyed by BSD name.
    static func displayNames() -> [String: String] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var names: [String: String] = [:]
        for interface in all {
            if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
               let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                names[bsd] = display
            }
        }
        return names
    }

    /// Physical interfaces (Wi-Fi, Ethernet, USB tethering, cellular) are counted by default;
    /// VPN tunnels, bridges and AirDrop links are not, to avoid double counting.
    static func countedByDefault(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }
}
