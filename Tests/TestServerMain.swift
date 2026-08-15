// 无头冒烟测试：验证 ServerManager 的 attach / spawn / shutdown 逻辑
// 编译：swiftc -swift-version 5 -parse-as-library Sources/ServerManager.swift Tests/TestServerMain.swift -o Tests/test-server
// 运行：DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=<writable-dir> ./Tests/test-server
import Foundation

@main
struct TestServerMain {
    static func main() async {
        let manager = ServerManager.shared
        let port = manager.preferredPort
        print("TEST: preferredPort = \(port)")

        // 打印启动结果
        await manager.ensureServer()

        // 检查状态
        switch manager.state {
        case .ready(let p):
            print("TEST: state = ready(\(p))")
            // 验证页面可访问
            let url = URL(string: "http://127.0.0.1:\(p)/")!
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                let http = resp as? HTTPURLResponse
                let body = String(data: data, encoding: .utf8) ?? ""
                let hasBoot = body.contains("__DSH_BOOT__")
                print("TEST: http=\(http?.statusCode ?? -1) bytes=\(data.count) hasBoot=\(hasBoot)")
            } catch {
                print("TEST: fetch failed: \(error)")
            }
        case .starting:
            print("TEST: state = starting (unexpected)")
        case .failed(let msg):
            print("TEST: state = failed: \(msg)")
        }

        // 等 1 秒让日志刷完，然后测试 shutdown
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        manager.shutdown()
        try? await Task.sleep(nanoseconds: 500_000_000)

        // 验证端口已关闭（shutdown 生效）
        do {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
            req.timeoutInterval = 2
            _ = try await URLSession.shared.data(for: req)
            print("TEST: after shutdown port still responds (BAD if we spawned)")
        } catch {
            print("TEST: after shutdown port closed (OK)")
        }
        print("TEST: done")
        exit(0)
    }
}
