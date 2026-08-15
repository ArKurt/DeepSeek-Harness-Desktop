import SwiftUI
import AppKit

extension Notification.Name {
    /// 触发网页刷新（Cmd+R）
    static let dshReload = Notification.Name("dshReload")
}

@main
struct DeepSeekDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var server = ServerManager.shared

    var body: some Scene {
        WindowGroup("DeepSeek") {
            RootView()
                .environmentObject(server)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            // 去掉默认“新建窗口”等无关菜单项
            CommandGroup(replacing: .newItem) { }
            CommandMenu("视图") {
                Button("刷新") {
                    NotificationCenter.default.post(name: .dshReload, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 防篡改自校验：关键文件哈希不匹配则拒绝启动（结果由 Integrity.passed 缓存）
        if !Integrity.passed {
            NSLog("INTEGRITY-FAIL: 应用文件校验失败，拒绝启动")
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "应用文件已被修改"
            alert.informativeText = "检测到 DeepSeek.app 的内容与原始版本不一致（可能被篡改）。为安全起见，应用将退出。请重新下载安装包。"
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        installSignalHandlers()
        // 尽早拉起本地服务器：与 SwiftUI 界面初始化并行，缩短等待时间
        Task { await ServerManager.shared.ensureServer() }
    }

    /// 拦截 SIGTERM/SIGINT/SIGHUP：即使进程被 kill 也会先关掉拉起的服务器。
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.handleTerminationSignal()
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func handleTerminationSignal() {
        ServerManager.shared.shutdown()
        exit(0)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出时关掉由本 App 拉起的服务器（外部已有的服务器不动）
        ServerManager.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// 根视图：先播启动动画，同时并行等待本地服务器就绪，然后淡入主界面。
struct RootView: View {
    @EnvironmentObject private var server: ServerManager
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()
                .opacity(showSplash ? 0 : 1)
            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            // 第一道闸门：篡改检测不通过，绝不进入主界面
            guard Integrity.passed else {
                server.state = .failed("应用文件已被修改，拒绝启动")
                return
            }
            // 服务器已由 AppDelegate 提前拉起。这里：最短动画 2.2s +
            // 等待服务器进入终态（ready/failed），然后淡入主界面。
            let minDelay = Task { try? await Task.sleep(nanoseconds: 5_200_000_000) }
            while case .starting = server.state {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            _ = await minDelay.value
            withAnimation(.easeInOut(duration: 0.45)) {
                showSplash = false
            }
        }
    }
}

/// 启动动画（约 5 秒）：
/// 鲸鱼作为 logo 静止在左侧，右侧是两行标题（"DeepSeek Harness" / "for Mac"），
/// 字母逐个弹入，作者名 "by Condex" 在 3.2s 浮现并留存约 2 秒。
struct SplashView: View {
    private static let line1Chars = Array("DeepSeek Harness")
    private static let line2Chars = Array("for Mac")

    @State private var whaleIn = false
    @State private var line1Shown = Array(repeating: false, count: SplashView.line1Chars.count)
    @State private var line2Shown = Array(repeating: false, count: SplashView.line2Chars.count)
    @State private var showAuthor = false

    private let line1 = SplashView.line1Chars
    private let line2 = SplashView.line2Chars

    /// 鲸鱼图片：直接按 Bundle 路径加载（SwiftUI Image("whale") 依赖 Asset Catalog，
    /// 没有 catalog 时会静默失败导致看不到鲸鱼，这里用文件路径加载保证可靠）。
    private var whaleImage: Image? {
        guard let url = Bundle.main.url(forResource: "whale", withExtension: "png"),
              let nsImage = NSImage(contentsOf: url) else {
            NSLog("SPLASH: whale.png 加载失败")
            return nil
        }
        return Image(nsImage: nsImage)
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 26) {
                // 鲸鱼 + 两行标题（横向 logo 布局，鲸鱼静止不跳）
                HStack(alignment: .center, spacing: 20) {
                    if let whaleImage {
                        whaleImage
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 88, height: 65)
                            .opacity(whaleIn ? 1 : 0)
                            .scaleEffect(whaleIn ? 1 : 0.92)
                    } else {
                        Color.clear.frame(width: 88, height: 65)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        // 第一行：DeepSeek Harness
                        HStack(spacing: 0) {
                            ForEach(0..<line1.count, id: \.self) { i in
                                Text(String(line1[i]))
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.black)
                                    .offset(y: line1Shown[i] ? 0 : 30)
                                    .opacity(line1Shown[i] ? 1 : 0)
                            }
                        }
                        // 第二行：for Mac
                        HStack(spacing: 0) {
                            ForEach(0..<line2.count, id: \.self) { i in
                                Text(String(line2[i]))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.75))
                                    .offset(y: line2Shown[i] ? 0 : 24)
                                    .opacity(line2Shown[i] ? 1 : 0)
                            }
                        }
                    }
                }

                // 作者名
                VStack(spacing: 4) {
                    Text("by Condex")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black.opacity(0.7))
                    Text("正在唤醒本地服务…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .opacity(showAuthor ? 1 : 0)
                .offset(y: showAuthor ? 0 : 10)
            }
        }
        .onAppear(perform: runAnimation)
    }

    private func runAnimation() {
        // 1) 鲸鱼优雅淡入（0.15s 起），之后完全静止
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.5)) {
                whaleIn = true
            }
        }
        // 2) 第一行字母逐个弹入（0.3s 起，16 字符 ≈ 1.4s 完成）
        for i in line1.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + 0.07 * Double(i)) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    line1Shown[i] = true
                }
            }
        }
        // 3) 第二行字母稍晚弹入（0.8s 起，7 字符 ≈ 1.3s 完成）
        for i in line2.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + 0.07 * Double(i)) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    line2Shown[i] = true
                }
            }
        }
        // 4) 作者名浮现（3.2s），留存到 5.2s 淡出 ≈ 2 秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.easeOut(duration: 0.4)) {
                showAuthor = true
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var server: ServerManager
    @State private var reloadToken = 0

    var body: some View {
        Group {
            switch server.state {
            case .starting, .ready:
                // 服务器启动期间就创建 WebView 预加载（带自动重试），
                // 服务器就绪后页面已加载完成，淡入即用。
                WebView(
                    url: URL(string: "http://127.0.0.1:\(server.preferredPort)")!,
                    reloadToken: reloadToken
                )
                .onReceive(NotificationCenter.default.publisher(for: .dshReload)) { _ in
                    reloadToken += 1
                }
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("DeepSeek 启动失败")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("重试") {
                        Task { await server.ensureServer() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
