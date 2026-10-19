# NetPulseBar — specification

**Tagline:** See live upload and download speed in the menu bar, with per-day totals and a tiny history graph.

**Category:** System Monitoring

**Inspired by (paid):** Bandwidth+ ($4.99 one-time)

**Frameworks:** SwiftUI, AppKit, Network, SystemConfiguration, ServiceManagement, Charts

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Bandwidth+ is a Mac App Store menu bar monitor showing network speeds and usage totals, sold for around 5 dollars. Demand evidence: network speed meters are a staple of menu bar utility roundups, and larger suites such as iStat Menus sell for about 12 dollars a year mainly for this feature plus other meters, so many people want a lightweight single purpose version.

Our clean-room feature set: a menu bar item displaying current download and upload rates in a compact two line or single line format such as 1.2 MB/s with arrows. Clicking opens a popover with a sparkline chart of the last 60 seconds for each direction, the active interface name such as Wi-Fi or Ethernet, local IP address, total bytes downloaded and uploaded today and this month, and a Reset Counters button. Settings choose the unit style (bytes or bits per second), update interval (1, 2 or 5 seconds), which interfaces to count, and whether the menu bar shows only download, only upload, or both. Optionally pause counting on selected interfaces such as VPN tunnels to avoid double counting.

UI spec: MenuBarExtra using the window style with a custom label view that renders the text with a monospaced digit font so it does not jitter. The popover has a header with the interface, two chart cards, totals table with Today, This Month and All Time rows, and footer buttons Settings and Quit. Settings window fields: launch at login, unit style picker, interval picker, interface checkbox list with names, menu bar display mode, and a button to clear history. Empty state: before the first sample the label shows a dash and the chart shows Collecting data. If no network is active the label shows Offline and the interface line says No active connection.

Technical approach: read per interface byte counters using getifaddrs and the if_data structure in the link layer entries, summing input and output bytes for chosen interfaces, with deltas divided by elapsed time between samples measured by a monotonic clock. Handle 32-bit counter wraparound by treating a negative delta as a wrap. Use NWPathMonitor from the Network framework to know the current interface type and when connectivity changes. Names can be shown through SystemConfiguration interface lookups. Draw sparklines with Swift Charts or a SwiftUI Path. Store daily totals as a dictionary keyed by date string in a JSON file in Application Support, saving once a minute and on quit. Launch at login via SMAppService. No permissions are required and no packets are inspected.

Edge cases and error handling: ignore loopback and inactive interfaces by default. After sleep or wake, discard the first sample to avoid a huge spike. Interfaces that appear or vanish, such as USB tethering, are handled by recomputing the interface list every sample. Rollover at midnight moves the counter to a new day entry. If the counters reset because of an interface restart, treat the negative delta as zero rather than adding a giant value. Keep the label width stable by padding to a fixed number of characters. Limit history stored to 400 days and prune older entries on launch.
