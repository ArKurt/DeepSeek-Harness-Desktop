import Foundation
import Combine

/// 管理 DeepSeek Harness 本地 Web 服务器：
/// 1) 若目标端口已有服务在跑（例如用户已手动启动过 dsh web）→ 直接连接；
/// 2) 否则用 App 内置的 Node 运行时 + dsh 包拉起一个服务器，等待就绪。
final class ServerManager: ObservableObject {
    static let shared = ServerManager()

    enum ServerState: Equatable {
        case starting
        case ready(port: Int)
        case failed(String)
    }

    @Published var state: ServerState = .starting

    private var serverProcess: Process?
    private var logURL: URL?

    private init() {}

    // MARK: - 配置

    /// 目标端口：环境变量 DSH_DESKTOP_PORT 优先，默认 3080（与 dsh web 默认一致）
    var preferredPort: Int {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["DSH_DESKTOP_PORT"], let p = Int(raw), p >= 0, p <= 65535 {
            return p
        }
        return 3080
    }

    /// 数据目录覆盖（默认不设置 → 使用用户真实 ~/.dsh，与命令行一致）
    private var homeOverride: String? {
        let env = ProcessInfo.processInfo.environment
        let v = env["DSH_DESKTOP_HOME"] ?? ""
        return v.isEmpty ? nil : v
    }

    // MARK: - 主流程

    func ensureServer() async {
        state = .starting
        let port = preferredPort

        if await isServing(port: port) {
            state = .ready(port: port)
            return
        }

        do {
            try spawn(port: port)
            if await waitUntilServing(port: port, timeout: 25) {
                state = .ready(port: port)
            } else {
                state = .failed("服务器启动超时。日志：\(logURL?.path ?? "无")")
            }
        } catch {
            state = .failed("启动失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 探测

    private func isServing(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - 启动

    private func runtimeRoot() throws -> URL {
        guard let res = Bundle.main.resourceURL else {
            throw ServerError.noResources
        }
        let runtime = res.appendingPathComponent("runtime", isDirectory: true)
        guard FileManager.default.fileExists(atPath: runtime.path) else {
            throw ServerError.noRuntime
        }
        return runtime
    }

    enum ServerError: LocalizedError {
        case noResources
        case noRuntime

        var errorDescription: String? {
            switch self {
            case .noResources: return "应用资源缺失"
            case .noRuntime: return "内置运行时缺失（runtime/ 未找到）"
            }
        }
    }

    private func spawn(port: Int) throws {
        let runtime = try runtimeRoot()
        let node = runtime.appendingPathComponent("node")
        let bin = runtime.appendingPathComponent("bundle/node_modules/@deepseek-ai/dsh/lib/bin.js")

        guard FileManager.default.isExecutableFile(atPath: node.path) else {
            throw ServerError.noRuntime
        }

        let p = Process()
        p.executableURL = node
        p.arguments = [bin.path, "web", "--port", String(port)]
        p.currentDirectoryURL = runtime.appendingPathComponent("bundle")

        var env = ProcessInfo.processInfo.environment
        env["DSH_DESKTOP"] = "1"
        if let home = homeOverride {
            env["DSH_HOME"] = home
        }
        p.environment = env

        // 日志写进 ~/Library/Application Support/DeepSeek/server.log
        let logDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DeepSeek", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("server.log")
        logURL = logFile
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        if let fh = FileHandle(forWritingAtPath: logFile.path) {
            fh.seekToEndOfFile()
            p.standardOutput = fh
            p.standardError = fh
        }

        try p.run()
        serverProcess = p
    }

    private func waitUntilServing(port: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isServing(port: port) { return true }
            // 进程提前退出（启动失败），不再空等
            if let p = serverProcess, !p.isRunning {
                return await isServing(port: port)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return await isServing(port: port)
    }

    // MARK: - 进程树清理

    private func children(of pid: Int32) -> [Int32] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-P", String(pid)]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func processAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    /// 递归向整棵树发 SIGTERM
    private func termTree(_ pid: Int32) {
        for child in children(of: pid) { termTree(child) }
        kill(pid, SIGTERM)
    }

    /// 递归向整棵树发 SIGKILL（兜底）
    private func killTree(_ pid: Int32) {
        for child in children(of: pid) { killTree(child) }
        kill(pid, SIGKILL)
    }

    private func treeAlive(_ pid: Int32) -> Bool {
        if processAlive(pid) { return true }
        return children(of: pid).contains { processAlive($0) }
    }

    /// 由本 App 拉起的服务器退出时调用；外部已存在的服务器不受影响。
    /// 同步等待整棵进程树退出（SIGTERM → 3 秒 → SIGKILL），避免残留孤儿进程。
    func shutdown() {
        guard let p = serverProcess else { return }
        let root = p.processIdentifier
        termTree(root)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && treeAlive(root) {
            Thread.sleep(forTimeInterval: 0.15)
        }
        killTree(root)
        serverProcess = nil
    }
}
