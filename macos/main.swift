import Cocoa
import WebKit

// ============================================================
//  清账猫 · macOS 原生外壳
//  WKWebView 装载打包好的 HTML，数据通过 JS 桥写入本机 JSON 文件
// ============================================================

final class DataStore {
    let dir: URL
    let file: URL
    let backupDir: URL
    private let fm = FileManager.default

    init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let newDir = base.appendingPathComponent("清账猫", isDirectory: true)
        // 老版本数据自动迁移过来，不丢记录（按新旧顺序尝试）
        // 注意：「清帐猫」是 1.0.0 的旧写法，改名后首次启动会自动搬过来
        if !fm.fileExists(atPath: newDir.path) {
            for legacy in ["清帐猫", "上岸账本", "DebtTracker"] {
                let oldDir = base.appendingPathComponent(legacy, isDirectory: true)
                if fm.fileExists(atPath: oldDir.path) {
                    try? fm.moveItem(at: oldDir, to: newDir)
                    break
                }
            }
        }
        dir = newDir
        file = dir.appendingPathComponent("records.json")
        backupDir = dir.appendingPathComponent("backups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
    }

    func read() -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    /// 写主文件；写入前先把当前状态快照为当天的每日备份
    func write(_ s: String) {
        guard let d = s.data(using: .utf8) else { return }
        dailyBackup()
        do {
            try d.write(to: file, options: .atomic)
        } catch {
            NSLog("QingZhangMao: 写入失败 \(error)")
        }
    }

    func dailyBackup() {
        guard fm.fileExists(atPath: file.path) else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let name = "records-\(f.string(from: Date())).json"
        let target = backupDir.appendingPathComponent(name)
        if !fm.fileExists(atPath: target.path) {
            try? fm.copyItem(at: file, to: target)
            prune(keep: 30)
        }
    }

    private func prune(keep: Int) {
        guard let items = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil) else { return }
        let sorted = items.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for (i, u) in sorted.enumerated() where i >= keep {
            try? fm.removeItem(at: u)
        }
    }
}

func jsStringLiteral(_ s: String) -> String {
    let arr = try? JSONSerialization.data(withJSONObject: [s], options: [])
    guard let a = arr, let str = String(data: a, encoding: .utf8) else { return "\"\"" }
    return String(str.dropFirst().dropLast())
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let store = DataStore()
    var selftest = false
    var selftestStage = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        selftest = CommandLine.arguments.contains("--selftest")

        // ---- 菜单 ----
        buildMenus()

        // ---- 窗口 ----
        let frame = NSRect(x: 0, y: 0, width: 1180, height: 820)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "清账猫"
        window.minSize = NSSize(width: 760, height: 560)
        window.delegate = self
        window.setFrameAutosaveName("DebtTrackerMain")
        window.backgroundColor = NSColor(srgbRed: 0.043, green: 0.059, blue: 0.078, alpha: 1) // #0b0f14

        // ---- WebView ----
        let cfg = WKWebViewConfiguration()
        let boot = "window.__NATIVE_BOOT__ = { json: \(jsStringLiteral(store.read())), path: \(jsStringLiteral(store.file.path)) };"
        cfg.userContentController.addUserScript(
            WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController.add(self, name: "store")

        webView = WKWebView(frame: frame, configuration: cfg)
        webView.navigationDelegate = self
        window.contentView = webView

        if let url = Bundle.main.url(forResource: "app", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // ---- JS → Swift：保存数据 ----
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "store", let s = message.body as? String else { return }
        store.write(s)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard selftest else { return }
        runSelftest()
    }

    // ---- 自检：首次运行写入示例；已有数据则验证读回 ----
    private func runSelftest() {
        let existing = store.read()
        if !existing.isEmpty, selftestStage == 0 {
            let loans = (try? JSONSerialization.jsonObject(with: Data(existing.utf8)) as? [String: Any])
                .flatMap { $0["loans"] as? [Any] }?.count ?? -1
            print("SELFTEST existing loans=\(loans) bytes=\(existing.utf8.count) -> readback OK")
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if self.selftestStage == 0 {
                self.selftestStage = 1
                self.webView.evaluateJavaScript("document.querySelector('#btn-sample').click(); 'clicked'") { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self.selftestStage = 2
                        let raw = self.store.read()
                        let loans = (try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
                            .flatMap { $0?["loans"] as? [Any] }?.count ?? -1
                        print("SELFTEST saved loans=\(loans) bytes=\(raw.utf8.count) path=\(self.store.file.path)")
                        // 第二阶段：重新注入验证读回
                        self.webView.evaluateJavaScript(
                            "JSON.parse(window.__NATIVE_BOOT__.json).loans.length") { v, _ in
                            print("SELFTEST readback=\(v ?? "nil")")
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
    }

    // ---- 菜单动作 ----
    @objc func openDataFolder() {
        NSWorkspace.shared.open(store.dir)
    }
    @objc func backupNow() {
        store.dailyBackup()
        let alert = NSAlert()
        alert.messageText = "已备份"
        alert.informativeText = "备份位置：\n\(store.backupDir.path)"
        alert.runModal()
    }

    private func buildMenus() {
        let main = NSMenu()

        // 应用菜单
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于清账猫", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏清账猫", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出清账猫", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // 编辑菜单（保证输入框快捷键可用）
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // 视图
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "视图")
        viewMenu.addItem(withTitle: "重新载入", action: #selector(WKWebView.reload(_:)), keyEquivalent: "r")
        viewItem.submenu = viewMenu

        // 数据
        let dataItem = NSMenuItem()
        main.addItem(dataItem)
        let dataMenu = NSMenu(title: "数据")
        dataMenu.addItem(withTitle: "打开数据文件夹", action: #selector(openDataFolder), keyEquivalent: "d")
        dataMenu.addItem(withTitle: "立即备份", action: #selector(backupNow), keyEquivalent: "b")
        dataItem.submenu = dataMenu

        // 窗口
        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: "窗口")
        winMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = winMenu

        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
