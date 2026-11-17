import Darwin
import Foundation

enum ProcessAction {
    case kill
    case forceKill
    case suspend
    case resume
    case throttle
    case unthrottle
}

struct ProcessActions {
    @discardableResult
    static func apply(_ action: ProcessAction, to pid: pid_t) -> Bool {
        switch action {
        case .kill:       return Darwin.kill(pid, SIGTERM) == 0
        case .forceKill:  return Darwin.kill(pid, SIGKILL) == 0
        case .suspend:    return Darwin.kill(pid, SIGSTOP) == 0
        case .resume:     return Darwin.kill(pid, SIGCONT) == 0
        case .throttle:   return runTaskpolicy(["-b", "-p", "\(pid)"])
        case .unthrottle: return runTaskpolicy(["-B", "-p", "\(pid)"])
        }
    }

    private static func runTaskpolicy(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
