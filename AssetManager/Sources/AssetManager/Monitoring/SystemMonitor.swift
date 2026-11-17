import Darwin
import Foundation

struct SystemSnapshot {
    var cpuTotalPercent: Double = 0
    var cpuPerCore: [Double] = []
    var ramUsedBytes: UInt64 = 0
    var ramTotalBytes: UInt64 = 0
    var ramPressurePercent: Double = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var compressedBytes: UInt64 = 0
    var timestamp: Date = Date()
}

final class SystemMonitor {
    private var prevCPUTicks: [host_cpu_load_info] = []
    private let pageSize: UInt64
    private let totalRAM: UInt64

    init() {
        var size: UInt64 = 0
        var sz = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &sz, nil, 0)
        totalRAM = size

        var psz: vm_size_t = 0
        host_page_size(mach_host_self(), &psz)
        pageSize = UInt64(psz)
    }

    func snapshot() -> SystemSnapshot {
        var snap = SystemSnapshot()
        snap.ramTotalBytes = totalRAM
        readMemory(into: &snap)
        readSwap(into: &snap)
        readCPU(into: &snap)
        return snap
    }

    private func readMemory(into snap: inout SystemSnapshot) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        snap.ramUsedBytes = used
        snap.compressedBytes = UInt64(stats.compressor_page_count) * pageSize

        let usedRatio = Double(used) / Double(totalRAM)
        snap.ramPressurePercent = min(100, max(0, usedRatio * 100))
    }

    private func readSwap(into snap: inout SystemSnapshot) {
        var xsw = xsw_usage()
        var sz = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &xsw, &sz, nil, 0) == 0 {
            snap.swapUsedBytes = xsw.xsu_used
            snap.swapTotalBytes = xsw.xsu_total
        }
    }

    private func readCPU(into snap: inout SystemSnapshot) {

        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t? = nil
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount)
        guard kr == KERN_SUCCESS, let info = infoArray else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size))
        }

        let buf = UnsafeBufferPointer(start: info, count: Int(infoCount))
        var current: [host_cpu_load_info] = []
        current.reserveCapacity(Int(cpuCount))
        let perCpuStride = Int(CPU_STATE_MAX)
        for i in 0..<Int(cpuCount) {
            let base = i * perCpuStride
            var load = host_cpu_load_info()
            load.cpu_ticks.0 = UInt32(bitPattern: buf[base + Int(CPU_STATE_USER)])
            load.cpu_ticks.1 = UInt32(bitPattern: buf[base + Int(CPU_STATE_SYSTEM)])
            load.cpu_ticks.2 = UInt32(bitPattern: buf[base + Int(CPU_STATE_IDLE)])
            load.cpu_ticks.3 = UInt32(bitPattern: buf[base + Int(CPU_STATE_NICE)])
            current.append(load)
        }

        if prevCPUTicks.count == current.count {
            var perCore: [Double] = []
            perCore.reserveCapacity(current.count)
            var sumActive: UInt64 = 0
            var sumTotal: UInt64 = 0
            for i in 0..<current.count {
                let pu = UInt64(current[i].cpu_ticks.0) &- UInt64(prevCPUTicks[i].cpu_ticks.0)
                let ps = UInt64(current[i].cpu_ticks.1) &- UInt64(prevCPUTicks[i].cpu_ticks.1)
                let pi = UInt64(current[i].cpu_ticks.2) &- UInt64(prevCPUTicks[i].cpu_ticks.2)
                let pn = UInt64(current[i].cpu_ticks.3) &- UInt64(prevCPUTicks[i].cpu_ticks.3)
                let active = pu &+ ps &+ pn
                let total = active &+ pi
                let pct: Double = total > 0 ? Double(active) / Double(total) * 100.0 : 0
                perCore.append(pct)
                sumActive &+= active
                sumTotal &+= total
            }
            snap.cpuPerCore = perCore
            snap.cpuTotalPercent = sumTotal > 0 ? Double(sumActive) / Double(sumTotal) * 100.0 : 0
        }
        prevCPUTicks = current
    }
}
