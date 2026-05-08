import ApplicationServices
import Foundation

enum DebugLog {
    private static let defaultsKey = "debugLogging"
    private static let logURL = URL(fileURLWithPath: "/tmp/displayfocus-memory-debug.log")

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey) ||
            ProcessInfo.processInfo.environment["DFM_DEBUG"] == "1"
    }

    static func write(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }

        let line = "\(ISO8601DateFormatter().string(from: Date())) [DFM] \(message())\n"
        append(line)
        NSLog("%@", line)
    }

    static func snapshotWindowOrder(label: String, pids: Set<pid_t>) {
        guard isEnabled else { return }

        guard !pids.isEmpty else {
            write("\(label): no pids to snapshot")
            return
        }

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            write("\(label): CGWindowListCopyWindowInfo failed")
            return
        }

        let rows = windows.enumerated().compactMap { index, info -> String? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pids.contains(pid),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                return nil
            }

            let owner = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let number = info[kCGWindowNumber as String] as? Int ?? 0
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap(rectDescription) ?? "unknown-bounds"
            let name = info[kCGWindowName as String] as? String
            let title = name.map { " title='\($0)'" } ?? ""

            return "#\(index) owner='\(owner)' pid=\(pid) window=\(number) bounds=\(bounds)\(title)"
        }

        write("\(label): front-to-back layer0 windows for pids \(pids.sorted()): \(rows.joined(separator: " | "))")
    }

    private static func rectDescription(from dictionary: NSDictionary) -> String? {
        var rect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(dictionary as CFDictionary, &rect) else {
            return nil
        }

        return "x=\(Int(rect.origin.x)),y=\(Int(rect.origin.y)),w=\(Int(rect.width)),h=\(Int(rect.height))"
    }

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
        }
    }
}
