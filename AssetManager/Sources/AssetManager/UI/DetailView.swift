import SwiftUI
import AppKit

struct DetailView: View {
    weak var controller: MenuBarController?
    @State private var snap = SystemSnapshot()
    @State private var procs: [ProcessSample] = []
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                metric("CPU", String(format: "%.0f%%", snap.cpuTotalPercent))
                metric("RAM",
                       String(format: "%.1f / %.1f GB",
                              Double(snap.ramUsedBytes)/1_073_741_824,
                              Double(snap.ramTotalBytes)/1_073_741_824))
                metric("Swap",
                       String(format: "%.1f / %.1f GB",
                              Double(snap.swapUsedBytes)/1_073_741_824,
                              Double(snap.swapTotalBytes)/1_073_741_824))
                metric("Compressed",
                       String(format: "%.1f GB",
                              Double(snap.compressedBytes)/1_073_741_824))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if !snap.cpuPerCore.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(snap.cpuPerCore.enumerated()), id: \.offset) { idx, val in
                        VStack(spacing: 2) {
                            ZStack(alignment: .bottom) {
                                Rectangle().fill(Color.gray.opacity(0.15)).frame(width: 18, height: 60)
                                Rectangle().fill(barColor(val)).frame(width: 18, height: max(1, 60 * val / 100))
                            }
                            Text("\(idx)").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Divider()

            HStack {
                Text("Top processes").font(.headline)
                Spacer()
                Text("\(procs.count)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(procs) { p in
                        ProcessRow(p: p) { action in
                            ProcessActions.apply(action, to: p.pid)
                        }
                        Divider()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear { startRefresh() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .monospaced))
        }
    }

    private func barColor(_ pct: Double) -> Color {
        if pct >= 80 { return .red }
        if pct >= 50 { return .orange }
        return .green
    }

    private func startRefresh() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in refresh() }
    }

    private func refresh() {
        guard let c = controller else { return }
        snap = c.currentSnapshot()
        procs = c.currentProcesses()
    }
}

private struct ProcessRow: View {
    let p: ProcessSample
    let onAction: (ProcessAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name.isEmpty ? "PID \(p.pid)" : p.name).font(.system(size: 12, weight: .medium))
                Text("PID \(p.pid)\(p.bundleId.map { " · \($0)" } ?? "")")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.0f%%", p.cpuPercent))
                .font(.system(.body, design: .monospaced)).frame(width: 56, alignment: .trailing)
                .foregroundColor(p.cpuPercent >= 100 ? .red : .primary)
            Text(String(format: "%.0f MB", Double(p.rssBytes)/(1024*1024)))
                .font(.system(.body, design: .monospaced)).frame(width: 80, alignment: .trailing)
            Menu("…") {
                Button("Kill") { onAction(.kill) }
                Button("Force kill") { onAction(.forceKill) }
                Button("Suspend") { onAction(.suspend) }
                Button("Resume") { onAction(.resume) }
                Divider()
                Button("Throttle to E-cores") { onAction(.throttle) }
                Button("Remove throttle") { onAction(.unthrottle) }
            }
            .frame(width: 50)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
}
