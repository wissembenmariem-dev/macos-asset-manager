import Foundation

final class RuleEngine {
    private var hotTicks: [pid_t: Int] = [:]

    func evaluate(processes: [ProcessSample], thresholds: Thresholds, tickIntervalSec: Double) -> [pid_t] {
        let requiredTicks = max(1, Int(Double(thresholds.processRunawayDurationSec) / tickIntervalSec))
        let runawayBytes = UInt64(thresholds.processRunawayRAMGB * 1_073_741_824)
        var flagged: [pid_t] = []
        var next: [pid_t: Int] = [:]

        for p in processes where p.cpuPercent >= thresholds.processRunawayCPU || p.rssBytes >= runawayBytes {
            let ticks = (hotTicks[p.pid] ?? 0) + 1
            next[p.pid] = ticks
            if ticks >= requiredTicks {
                flagged.append(p.pid)
            }
        }

        hotTicks = next
        return flagged
    }

    func clear(pid: pid_t) {
        hotTicks.removeValue(forKey: pid)
    }
}
