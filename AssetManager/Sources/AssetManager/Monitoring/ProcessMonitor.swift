import Darwin
import Foundation

private let PROC_ALL_PIDS: Int32 = 1
private let PROC_PIDTASKINFO: Int32 = 4
private let PROC_PIDPATHINFO_MAXSIZE: Int32 = 4096

@_silgen_name("proc_listpids")
private func proc_listpids(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidpath")
private func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

@_silgen_name("proc_name")
private func proc_name(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

private struct ProcTaskInfo {
    var pti_virtual_size: UInt64 = 0
    var pti_resident_size: UInt64 = 0
    var pti_total_user: UInt64 = 0
    var pti_total_system: UInt64 = 0
    var pti_threads_user: UInt64 = 0
    var pti_threads_system: UInt64 = 0
    var pti_policy: Int32 = 0
    var pti_faults: Int32 = 0
    var pti_pageins: Int32 = 0
    var pti_cow_faults: Int32 = 0
    var pti_messages_sent: Int32 = 0
    var pti_messages_received: Int32 = 0
    var pti_syscalls_mach: Int32 = 0
    var pti_syscalls_unix: Int32 = 0
    var pti_csw: Int32 = 0
    var pti_threadnum: Int32 = 0
    var pti_numrunning: Int32 = 0
    var pti_priority: Int32 = 0
}

struct ProcessSample: Identifiable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    let path: String
    let bundleId: String?
    var cpuPercent: Double
    var rssBytes: UInt64
    var threads: Int
    var suspended: Bool
}

final class ProcessMonitor {
    private struct PrevSample { let totalNs: UInt64; let timestamp: TimeInterval }
    private var prev: [pid_t: PrevSample] = [:]
    private let logicalCoreCount: Double

    private struct PidMeta { let name: String; let path: String; let bundleId: String? }
    private var metaCache: [pid_t: PidMeta] = [:]

    init() {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.logicalcpu", &count, &size, nil, 0)
        logicalCoreCount = Double(max(count, 1))
    }

    func snapshot(top: Int = 30) -> [ProcessSample] {
        let pids = listAllPids()
        let now = Date().timeIntervalSince1970
        var results: [ProcessSample] = []
        results.reserveCapacity(pids.count)
        var newPrev: [pid_t: PrevSample] = [:]

        for pid in pids where pid > 0 {
            var info = ProcTaskInfo()
            let size = MemoryLayout<ProcTaskInfo>.size
            let r = withUnsafeMutablePointer(to: &info) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
            if r <= 0 { continue }

            let totalNs = info.pti_total_user &+ info.pti_total_system
            var cpuPct = 0.0
            if let p = prev[pid] {
                let dt = now - p.timestamp
                if dt > 0 {
                    let dNs = Double(totalNs &- p.totalNs)

                    cpuPct = min(logicalCoreCount * 100.0, (dNs / (dt * 1_000_000_000.0)) * 100.0)
                }
            }
            newPrev[pid] = PrevSample(totalNs: totalNs, timestamp: now)

            let meta = metaCache[pid] ?? loadMeta(pid: pid)
            metaCache[pid] = meta

            results.append(ProcessSample(
                pid: pid,
                name: meta.name,
                path: meta.path,
                bundleId: meta.bundleId,
                cpuPercent: cpuPct,
                rssBytes: info.pti_resident_size,
                threads: Int(info.pti_threadnum),
                suspended: false
            ))
        }
        prev = newPrev

        let alive = Set(pids)
        metaCache = metaCache.filter { alive.contains($0.key) }

        results.sort { ($0.cpuPercent, $0.rssBytes) > ($1.cpuPercent, $1.rssBytes) }
        if results.count > top { results.removeLast(results.count - top) }
        return results
    }

    private func listAllPids() -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        let count = Int(bytes) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count + 16)
        let written = pids.withUnsafeMutableBufferPointer { ptr -> Int32 in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, ptr.baseAddress, Int32(ptr.count * MemoryLayout<pid_t>.size))
        }
        let actual = Int(written) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(actual))
    }

    private func loadMeta(pid: pid_t) -> PidMeta {
        var nameBuf = [CChar](repeating: 0, count: 256)
        _ = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        let name = String(cString: nameBuf)

        var pathBuf = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_MAXSIZE))
        _ = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        let path = String(cString: pathBuf)

        let bundleId = bundleIdFromPath(path)
        return PidMeta(name: name, path: path, bundleId: bundleId)
    }

    private func bundleIdFromPath(_ path: String) -> String? {

        var cur = path
        while !cur.isEmpty && cur != "/" {
            if cur.hasSuffix(".app") {
                let info = cur + "/Contents/Info.plist"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: info)),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let id = plist["CFBundleIdentifier"] as? String {
                    return id
                }
                return nil
            }
            cur = (cur as NSString).deletingLastPathComponent
        }
        return nil
    }
}
