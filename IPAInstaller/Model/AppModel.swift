import Foundation
import Observation

@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case working(String)
        case succeeded(String)
        case failed(String)

        var isWorking: Bool { if case .working = self { true } else { false } }
    }

    let signing = SigningSetup()
    private(set) var package: IPAPackage?
    private(set) var devices: [Device] = []
    var selectedDeviceID: String?
    private(set) var isLoadingDevices = false
    private(set) var deviceIssue: String?
    private(set) var phase = Phase.idle
    private(set) var log: [String] = []
    /// 拖入或选择文件时的提示，例如格式不支持。
    var notice: String?
    var isChoosingFiles = false

    var selectedDevice: Device? { devices.first { $0.id == selectedDeviceID } }

    /// 安装后的 Bundle ID：描述文件绑定的 ID，通配符时沿用安装包的。
    var targetBundleID: String? { signing.profile?.bundleID ?? package?.bundleID }

    var blocker: String? {
        guard let profile = signing.profile else { return "添加描述文件" }
        guard signing.certificateName != nil else { return "添加 .p12 证书" }
        guard signing.hasPassword else { return "填写证书密码" }
        if profile.isExpired { return "描述文件已过期" }
        guard package != nil else { return "添加 .ipa 安装包" }
        guard let device = selectedDevice else { return "连接并选择设备" }
        if !profile.allows(device) { return "描述文件不包含这台设备" }
        return nil
    }

    /// 按扩展名分派：.p12 证书、.mobileprovision 描述文件、.ipa 安装包，可以一次拖多个。
    func add(_ urls: [URL]) {
        notice = nil
        for url in urls {
            switch url.pathExtension.lowercased() {
            case "p12", "pfx":
                attempt { try signing.importCertificate(url) }
            case "mobileprovision":
                attempt { try signing.importProfile(url) }
            case "ipa":
                Task { await loadPackage(url) }
            default:
                notice = "不支持 \(url.lastPathComponent)：只接受 .p12、.mobileprovision 和 .ipa。"
            }
        }
    }

    func savePassword(_ password: String) async {
        notice = nil
        do { try await signing.savePassword(password) } catch { notice = error.localizedDescription }
    }

    func refreshDevices() async {
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        do {
            devices = try await Device.paired()
            deviceIssue = nil
        } catch {
            devices = []
            deviceIssue = error.localizedDescription
        }
        if selectedDevice == nil {
            selectedDeviceID = (devices.first { $0.isAvailable } ?? devices.first)?.id
        }
    }

    func install() async {
        guard blocker == nil, let profile = signing.profile, let package, let device = selectedDevice,
              let password = PasswordStore.load() else { return }
        log = []
        phase = .working("准备")
        let installer = Installer(certificate: signing.certificateURL, password: password, profile: profile,
                                  profileURL: signing.profileURL, package: package, device: device) { [weak self] step in
            self?.log.append(step)
            self?.phase = .working(step)
        }
        do {
            try await installer.run()
            log.append("完成")
            phase = .succeeded("已安装到 \(device.name)")
        } catch {
            log.append("失败：\(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadPackage(_ url: URL) async {
        do {
            package = try await IPAPackage.load(url)
            phase = .idle
        } catch {
            notice = error.localizedDescription
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { notice = error.localizedDescription }
    }
}
