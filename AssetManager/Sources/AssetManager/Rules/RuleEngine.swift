import Foundation

final class RuleEngine {
    struct Tracker {
        var firstSeen: Date
        var consecutiveTicks: Int
        var lastRSS: UInt64
        var growthCount: Int
    }

    private var trackers: [pid_t: Tracker] = [:]

    func evaluate(processes: [ProcessInfo], thresholds: Thresholds, tickIntervalSec: Double) -> [pid_t] {
        let now = Date()
        var flagged: [pid_t] = []
        let durationTicks = max(1, Int(Double(thresholds.processRunawayDurationSec) / tickIntervalSec))
        let runawayBytes = UInt64(thresholds.processRunawayRAMGB * 1_073_741_824)

        var alive = Set<pid_t>()
        for p in processes {
            alive.insert(p.pid)
            let cpuHot = p.cpuPercent >= thresholds.processRunawayCPU
            let ramHot = p.rssBytes >= runawayBytes

            if cpuHot || ramHot {
                if var t = trackers[p.pid] {
                    t.consecutiveTicks += 1
                    if p.rssBytes > t.lastRSS { t.growthCount += 1 }
                    t.lastRSS = p.rssBytes
                    trackers[p.pid] = t
                    if t.consecutiveTicks >= durationTicks {
                        flagged.append(p.pid)
                    }
                } else {
                    trackers[p.pid] = Tracker(firstSeen: now, consecutiveTicks: 1, lastRSS: p.rssBytes, growthCount: 0)
                }
            } else {
                trackers.removeValue(forKey: p.pid)
            }
        }

        trackers = trackers.filter { alive.contains($0.key) }
        return flagged
    }

    func clear(pid: pid_t) {
        trackers.removeValue(forKey: pid)
    }
}
