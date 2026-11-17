import XCTest
@testable import AssetManager

final class RuleEngineTests: XCTestCase {
    private var thresholds = Thresholds(processRunawayCPU: 200, processRunawayRAMGB: 1.0, processRunawayDurationSec: 6)

    private func sample(pid: pid_t, cpu: Double = 0, ramGB: Double = 0.1) -> ProcessSample {
        ProcessSample(pid: pid, name: "p\(pid)", path: "/bin/p", bundleId: nil, cpuPercent: cpu,
                      rssBytes: UInt64(ramGB * 1_073_741_824), threads: 1, suspended: false)
    }

    func testFlagsProcessAfterSustainedHighCPU() {
        let engine = RuleEngine()
        let hot = [sample(pid: 1, cpu: 350)]
        XCTAssertEqual(engine.evaluate(processes: hot, thresholds: thresholds, tickIntervalSec: 2), [])
        XCTAssertEqual(engine.evaluate(processes: hot, thresholds: thresholds, tickIntervalSec: 2), [])
        XCTAssertEqual(engine.evaluate(processes: hot, thresholds: thresholds, tickIntervalSec: 2), [1])
    }

    func testFlagsProcessAboveMemoryThreshold() {
        let engine = RuleEngine()
        let heavy = [sample(pid: 2, ramGB: 2)]
        _ = engine.evaluate(processes: heavy, thresholds: thresholds, tickIntervalSec: 2)
        _ = engine.evaluate(processes: heavy, thresholds: thresholds, tickIntervalSec: 2)
        XCTAssertEqual(engine.evaluate(processes: heavy, thresholds: thresholds, tickIntervalSec: 2), [2])
    }

    func testCoolingDownResetsTheCounter() {
        let engine = RuleEngine()
        _ = engine.evaluate(processes: [sample(pid: 3, cpu: 300)], thresholds: thresholds, tickIntervalSec: 2)
        _ = engine.evaluate(processes: [sample(pid: 3, cpu: 300)], thresholds: thresholds, tickIntervalSec: 2)
        _ = engine.evaluate(processes: [sample(pid: 3, cpu: 10)], thresholds: thresholds, tickIntervalSec: 2)
        XCTAssertEqual(engine.evaluate(processes: [sample(pid: 3, cpu: 300)], thresholds: thresholds, tickIntervalSec: 2), [])
    }

    func testExitedProcessesAreForgotten() {
        let engine = RuleEngine()
        _ = engine.evaluate(processes: [sample(pid: 4, cpu: 300)], thresholds: thresholds, tickIntervalSec: 2)
        _ = engine.evaluate(processes: [], thresholds: thresholds, tickIntervalSec: 2)
        _ = engine.evaluate(processes: [sample(pid: 4, cpu: 300)], thresholds: thresholds, tickIntervalSec: 2)
        XCTAssertEqual(engine.evaluate(processes: [sample(pid: 4, cpu: 300)], thresholds: thresholds, tickIntervalSec: 2), [])
    }
}
