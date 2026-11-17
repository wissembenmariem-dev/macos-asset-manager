import AppKit
import SwiftUI

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let systemMonitor = SystemMonitor()
    private let processMonitor = ProcessMonitor()
    private let ruleEngine = RuleEngine()
    private var detailWindow: NSWindow?
    private var timer: DispatchSourceTimer?
    private var lastProcesses: [ProcessInfo] = []
    private var lastSnap: SystemSnapshot = SystemSnapshot()
    private var alertedPids: Set<pid_t> = []

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "AM"
        statusItem.button?.font = NSFont.menuBarFont(ofSize: 11)
        rebuildMenu()
        startTimer()
    }

    deinit { timer?.cancel() }

    private func startTimer() {
        let q = DispatchQueue(label: "am.monitor", qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: q)
        let interval = ConfigStore.shared.config.pollIntervalActiveSec
        t.schedule(deadline: .now() + 0.2, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        let snap = systemMonitor.snapshot()
        let procs = processMonitor.snapshot(top: 30)
        let cfg = ConfigStore.shared.config
        let flagged = ruleEngine.evaluate(processes: procs, thresholds: cfg.thresholds, tickIntervalSec: cfg.pollIntervalActiveSec)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastSnap = snap
            self.lastProcesses = procs
            self.updateStatusTitle(snap: snap)
            self.handleFlagged(pids: flagged, processes: procs)

        }
    }

    private func updateStatusTitle(snap: SystemSnapshot) {
        let cpu = Int(snap.cpuTotalPercent.rounded())
        let ramPct = Int(snap.ramPressurePercent.rounded())
        let title = "\(cpu)%·\(ramPct)%"
        statusItem.button?.title = title

        let warn = ConfigStore.shared.config.thresholds.ramPressureWarn
        let crit = ConfigStore.shared.config.thresholds.ramPressureCritical
        if Double(ramPct) >= crit {
            statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
        } else if Double(ramPct) >= warn {
            statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemOrange])
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.labelColor])
        }
    }

    private func handleFlagged(pids: [pid_t], processes: [ProcessInfo]) {
        for pid in pids where !alertedPids.contains(pid) {
            guard let p = processes.first(where: { $0.pid == pid }) else { continue }
            alertedPids.insert(pid)
            postNotification(p)
        }

        let stillFlagged = Set(pids)
        alertedPids = alertedPids.intersection(stillFlagged)
    }

    private func postNotification(_ p: ProcessInfo) {
        let n = NSUserNotification()
        n.title = "Runaway process detected"
        n.subtitle = p.name
        n.informativeText = String(format: "%@ — CPU %.0f%%, RAM %.1f GB", p.name, p.cpuPercent, Double(p.rssBytes) / 1_073_741_824)
        n.actionButtonTitle = "Kill"
        n.hasActionButton = true
        n.identifier = "am.runaway.\(p.pid)"
        NSUserNotificationCenter.default.deliver(n)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        header.tag = 1
        header.isEnabled = false
        menu.addItem(header)

        let swapItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        swapItem.tag = 2
        swapItem.isEnabled = false
        menu.addItem(swapItem)

        menu.addItem(NSMenuItem.separator())

        let topHeader = NSMenuItem(title: "Top processes", action: nil, keyEquivalent: "")
        topHeader.isEnabled = false
        menu.addItem(topHeader)

        for i in 0..<10 {
            let item = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
            item.tag = 100 + i
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let detailItem = NSMenuItem(title: "Open detail window…", action: #selector(openDetail), keyEquivalent: "d")
        detailItem.target = self
        menu.addItem(detailItem)

        let purgeItem = NSMenuItem(title: "Trigger memory pressure", action: #selector(triggerMemoryPressure), keyEquivalent: "")
        purgeItem.target = self
        menu.addItem(purgeItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Asset Manager", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshMenuItems() {
        guard let menu = statusItem.menu else { return }

        if let h = menu.item(withTag: 1) {
            h.title = String(format: "CPU %.0f%%   RAM used %.1f / %.1f GB",
                             lastSnap.cpuTotalPercent,
                             Double(lastSnap.ramUsedBytes)/1_073_741_824,
                             Double(lastSnap.ramTotalBytes)/1_073_741_824)
        }
        if let s = menu.item(withTag: 2) {
            s.title = String(format: "Swap %.1f / %.1f GB   Compressed %.1f GB",
                             Double(lastSnap.swapUsedBytes)/1_073_741_824,
                             Double(lastSnap.swapTotalBytes)/1_073_741_824,
                             Double(lastSnap.compressedBytes)/1_073_741_824)
        }

        let top = Array(lastProcesses.prefix(10))
        for i in 0..<10 {
            guard let item = menu.item(withTag: 100 + i) else { continue }
            if i < top.count {
                let p = top[i]
                let ramMB = Double(p.rssBytes) / (1024 * 1024)
                item.title = String(format: "%@ — %.0f%% / %.0f MB", p.name.isEmpty ? "(\(p.pid))" : p.name, p.cpuPercent, ramMB)
                item.isEnabled = true
                item.submenu = buildProcessSubmenu(for: p)
            } else {
                item.title = "—"
                item.isEnabled = false
                item.submenu = nil
            }
        }
    }

    private func buildProcessSubmenu(for p: ProcessInfo) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false

        let info = NSMenuItem(title: String(format: "PID %d   %.0f%% CPU   %.1f MB", p.pid, p.cpuPercent, Double(p.rssBytes)/(1024*1024)), action: nil, keyEquivalent: "")
        info.isEnabled = false
        m.addItem(info)
        if let bid = p.bundleId {
            let bi = NSMenuItem(title: bid, action: nil, keyEquivalent: "")
            bi.isEnabled = false
            m.addItem(bi)
        }
        m.addItem(NSMenuItem.separator())

        m.addItem(actionItem("Kill (SIGTERM)", action: .kill, pid: p.pid))
        m.addItem(actionItem("Force kill (SIGKILL)", action: .forceKill, pid: p.pid))
        m.addItem(actionItem("Suspend (SIGSTOP)", action: .suspend, pid: p.pid))
        m.addItem(actionItem("Resume (SIGCONT)", action: .resume, pid: p.pid))
        m.addItem(NSMenuItem.separator())
        m.addItem(actionItem("Throttle to E-cores", action: .throttle, pid: p.pid))
        m.addItem(actionItem("Remove throttle", action: .unthrottle, pid: p.pid))
        m.addItem(NSMenuItem.separator())

        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = p.path
        m.addItem(reveal)

        let actMon = NSMenuItem(title: "Open in Activity Monitor", action: #selector(openInActivityMonitor(_:)), keyEquivalent: "")
        actMon.target = self
        actMon.representedObject = p.pid
        m.addItem(actMon)

        return m
    }

    private func actionItem(_ title: String, action: ProcessAction, pid: pid_t) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ActionPayload(action: action, pid: pid)
        return item
    }

    private struct ActionPayload { let action: ProcessAction; let pid: pid_t }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ActionPayload else { return }
        let ok = ProcessActions.apply(payload.action, to: payload.pid)
        if !ok {
            let alert = NSAlert()
            alert.messageText = "Action failed"
            alert.informativeText = "Could not apply action on PID \(payload.pid). It may belong to another user or be a system process."
            alert.runModal()
        }
        ruleEngine.clear(pid: payload.pid)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func openInActivityMonitor(_ sender: NSMenuItem) {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func triggerMemoryPressure() {

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/memory_pressure")
        p.arguments = ["-l", "critical"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()

    }

    @objc private func openDetail() {
        if detailWindow == nil {
            let view = DetailView(controller: self)
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = "Asset Manager"
            w.setContentSize(NSSize(width: 640, height: 520))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            detailWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        detailWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func currentSnapshot() -> SystemSnapshot { lastSnap }
    func currentProcesses() -> [ProcessInfo] { lastProcesses }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuItems()
    }
}
