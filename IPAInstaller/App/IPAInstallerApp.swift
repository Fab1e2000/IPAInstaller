import SwiftUI

@main
struct IPAInstallerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("IPA 安装器", id: "main") {
            ContentView()
                .environment(delegate.model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件…") { delegate.model.isChoosingFiles = true }
                    .keyboardShortcut("o")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 把文件拖到 Dock 图标上，或用“打开方式”打开。
    func application(_ application: NSApplication, open urls: [URL]) {
        model.add(urls)
    }
}
