import Foundation
import Observation
import Security

/// 保存的证书和描述文件。文件复制到 ~/Library/Application Support/IPAInstaller，证书密码存在钥匙串。
@Observable
final class SigningSetup {
    private(set) var profile: ProvisioningProfile?
    private(set) var profileIssue: String?
    private(set) var certificateName: String?
    private(set) var hasPassword = false

    private let folder = URL.applicationSupportDirectory.appending(path: "IPAInstaller", directoryHint: .isDirectory)
    var certificateURL: URL { folder.appending(path: "certificate.p12") }
    var profileURL: URL { folder.appending(path: "profile.mobileprovision") }
    var isReady: Bool { profile != nil && certificateName != nil && hasPassword }

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    func importCertificate(_ url: URL) throws {
        try copy(url, to: certificateURL)
        UserDefaults.standard.set(url.lastPathComponent, forKey: "certificateName")
        PasswordStore.delete()
        reload()
    }

    func importProfile(_ url: URL) throws {
        _ = try ProvisioningProfile(contentsOf: url)
        try copy(url, to: profileURL)
        UserDefaults.standard.set(url.lastPathComponent, forKey: "profileName")
        reload()
    }

    /// 先用 OpenSSL 验证密码，正确才保存。
    func savePassword(_ password: String) async throws {
        try await OpenSSL.unpack(certificateURL, password: password)
        try PasswordStore.save(password)
        hasPassword = true
    }

    func forgetPassword() {
        PasswordStore.delete()
        hasPassword = false
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: certificateURL)
        try? FileManager.default.removeItem(at: profileURL)
        PasswordStore.delete()
        reload()
    }

    private func copy(_ source: URL, to destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private func reload() {
        let files = FileManager.default
        certificateName = files.fileExists(atPath: certificateURL.path)
            ? UserDefaults.standard.string(forKey: "certificateName") ?? "certificate.p12" : nil
        if files.fileExists(atPath: profileURL.path) {
            do { profile = try ProvisioningProfile(contentsOf: profileURL); profileIssue = nil }
            catch { profile = nil; profileIssue = error.localizedDescription }
        } else {
            profile = nil
            profileIssue = nil
        }
        hasPassword = certificateName != nil && PasswordStore.load() != nil
    }
}

/// 证书密码存在登录钥匙串里。
nonisolated enum PasswordStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.elsterlee.IPAInstaller",
         kSecAttrAccount as String: "certificate"]
    }

    static func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ password: String) throws {
        delete()
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrLabel as String] = "IPA 安装器证书密码"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppError("无法把密码保存到钥匙串（\(status)）。") }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
