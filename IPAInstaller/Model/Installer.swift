import Foundation

/// 重签 .ipa 并安装到设备。
/// Bundle ID 改成描述文件绑定的 App ID，让 application-identifier 与 Bundle ID 一致；
/// 两者不一致时，App 里的文件选择器选中的目录会被系统拒绝。
struct Installer {
    let certificate: URL
    let password: String
    let profile: ProvisioningProfile
    let profileURL: URL
    let package: IPAPackage
    let device: Device
    let log: (String) -> Void

    var bundleID: String { profile.bundleID ?? package.bundleID }

    func run() async throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "\(SigningKeychain.marker)\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let keychain = SigningKeychain(folder: work)
        do {
            try await sign(in: work, keychain: keychain)
        } catch {
            await keychain.dispose()
            try? FileManager.default.removeItem(at: work)
            throw error
        }
        await keychain.dispose()
        try? FileManager.default.removeItem(at: work)
    }

    private func sign(in work: URL, keychain: SigningKeychain) async throws {
        log("导入证书")
        let identity = try await keychain.importIdentity(certificate, password: password, matching: profile.certificateHashes)

        log("解包 \(package.url.lastPathComponent)")
        let unpacked = work.appending(path: "unpacked")
        try await Shell.run("/usr/bin/ditto", ["-x", "-k", package.url.path, unpacked.path])
        let payload = unpacked.appending(path: "Payload")
        guard let app = try FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw AppError("安装包里没有 .app。") }

        log("Bundle ID 设为 \(bundleID)")
        let infoURL = app.appending(path: "Info.plist")
        guard var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any] else {
            throw AppError("Info.plist 无法读取。")
        }
        info["CFBundleIdentifier"] = bundleID
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: infoURL)

        // 一份描述文件只覆盖主程序，扩展和手表 App 没法一起签，直接去掉。
        for name in ["PlugIns", "Extensions", "Watch", "_CodeSignature"] {
            let item = app.appending(path: name)
            guard FileManager.default.fileExists(atPath: item.path) else { continue }
            if name != "_CodeSignature" { log("移除 \(name)（描述文件只覆盖主程序）") }
            try FileManager.default.removeItem(at: item)
        }
        let embedded = app.appending(path: "embedded.mobileprovision")
        try? FileManager.default.removeItem(at: embedded)
        try FileManager.default.copyItem(at: profileURL, to: embedded)

        let appID = "\(profile.teamID).\(bundleID)"
        let entitlements: [String: Any] = [
            "application-identifier": appID,
            "com.apple.developer.team-identifier": profile.teamID,
            "get-task-allow": profile.getTaskAllow,
            "keychain-access-groups": [appID],
        ]
        let entitlementsURL = work.appending(path: "entitlements.plist")
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: entitlementsURL)

        log("签名")
        let frameworks = app.appending(path: "Frameworks")
        let nested = (try? FileManager.default.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? []
        for item in nested where ["framework", "dylib"].contains(item.pathExtension) {
            try await codesign(item, identity: identity, keychain: keychain)
        }
        try await codesign(app, identity: identity, keychain: keychain, entitlements: entitlementsURL)
        try await Shell.run("/usr/bin/codesign", ["--verify", "--strict", app.path])

        log("安装到 \(device.name)")
        try await Shell.run("/usr/bin/xcrun", ["devicectl", "device", "install", "app", "--device", device.id, app.path])
        // 手机锁屏时打不开，不算失败。
        _ = try? await Shell.run("/usr/bin/xcrun", ["devicectl", "device", "process", "launch",
                                                    "--device", device.id, "--terminate-existing", bundleID])
    }

    private func codesign(_ item: URL, identity: String, keychain: SigningKeychain, entitlements: URL? = nil) async throws {
        var arguments = ["--force", "--sign", identity, "--keychain", keychain.path.path, "--timestamp=none", "--generate-entitlement-der"]
        if let entitlements { arguments += ["--entitlements", entitlements.path] }
        try await Shell.run("/usr/bin/codesign", arguments + [item.path])
    }
}

/// 临时钥匙串：导入证书供 codesign 使用，用完删除，不会弹窗要密码。
struct SigningKeychain {
    /// 临时目录和钥匙串路径都带这个前缀；上次异常退出留下的也会被清掉。
    static let marker = "IPAInstaller-sign-"
    private static let security = "/usr/bin/security"

    let folder: URL
    var path: URL { folder.appending(path: "signing.keychain-db") }
    private let keychainPassword = UUID().uuidString

    init(folder: URL) { self.folder = folder }

    /// 返回与描述文件匹配的签名身份（SHA-1）。
    func importIdentity(_ p12: URL, password: String, matching hashes: Set<String>) async throws -> String {
        // macOS 钥匙串读不了 OpenSSL 3 导出的 .p12，先转成旧格式。
        let pem = folder.appending(path: "identity.pem")
        let legacy = folder.appending(path: "identity.p12")
        try await OpenSSL.unpack(p12, password: password, to: pem)
        do {
            try await OpenSSL.exportLegacy(pem, to: legacy, password: password)
            try? FileManager.default.removeItem(at: pem)
        } catch {
            try? FileManager.default.removeItem(at: pem)
            throw error
        }

        try await Shell.run(Self.security, ["create-keychain", "-p", keychainPassword, path.path])
        try await Shell.run(Self.security, ["set-keychain-settings", path.path])
        try await Shell.run(Self.security, ["unlock-keychain", "-p", keychainPassword, path.path])
        try await Shell.run(Self.security, ["import", legacy.path, "-k", path.path, "-P", password, "-T", "/usr/bin/codesign"])
        try? FileManager.default.removeItem(at: legacy)
        try await Shell.run(Self.security, ["set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", keychainPassword, path.path])
        try await Shell.run(Self.security, ["list-keychains", "-d", "user", "-s", path.path] + Self.searchList())

        let identities = try await Shell.text(Self.security, ["find-identity", "-v", "-p", "codesigning", path.path])
        let found = identities.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(separator: " ")
            return fields.count > 1 && fields[0].hasSuffix(")") ? String(fields[1]) : nil
        }
        guard !found.isEmpty else { throw AppError("证书里没有可用于签名的身份。") }
        guard let identity = found.first(where: hashes.contains) ?? (hashes.isEmpty ? found.first : nil) else {
            throw AppError("证书和描述文件不配套：描述文件里没有这张证书。")
        }
        return identity
    }

    func dispose() async {
        if let list = try? await Self.searchList() {
            _ = try? await Shell.run(Self.security, ["list-keychains", "-d", "user", "-s"] + list)
        }
        _ = try? await Shell.run(Self.security, ["delete-keychain", path.path])
    }

    /// 当前的钥匙串搜索列表，去掉本工具建的临时钥匙串。
    private static func searchList() async throws -> [String] {
        try await Shell.text(security, ["list-keychains", "-d", "user"])
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty && !$0.contains(marker) }
    }
}
