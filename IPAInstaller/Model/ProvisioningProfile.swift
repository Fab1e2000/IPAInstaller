import CryptoKit
import Foundation
import Security

/// .mobileprovision 描述文件里签名需要的信息。
struct ProvisioningProfile {
    let name: String
    let teamName: String
    /// 例如 `ABCDE12345.com.example.app`，或通配符 `ABCDE12345.*`。
    let applicationIdentifier: String
    let expirationDate: Date
    /// 允许安装的设备 UDID；企业证书为 nil，表示不限设备。
    let devices: [String]?
    let getTaskAllow: Bool
    /// 描述文件包含的证书 SHA-1，用来核对 .p12 是否配套。
    let certificateHashes: Set<String>

    var teamID: String { String(applicationIdentifier.prefix { $0 != "." }) }

    /// 描述文件绑定的 Bundle ID；通配符返回 nil，安装时保留安装包原来的 ID。
    var bundleID: String? {
        let id = String(applicationIdentifier.dropFirst(teamID.count + 1))
        return id.contains("*") ? nil : id
    }

    var isExpired: Bool { expirationDate < .now }

    var kind: String {
        guard let devices else { return "企业" }
        return (getTaskAllow ? "开发" : "Ad Hoc") + "（\(devices.count) 台设备）"
    }

    func allows(_ device: Device) -> Bool { devices?.contains(device.udid) ?? true }

    init(contentsOf url: URL) throws {
        let plist = try Self.decode(Data(contentsOf: url))
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        guard let identifier = entitlements["application-identifier"] as? String,
              let expiration = plist["ExpirationDate"] as? Date else {
            throw AppError("描述文件缺少 App ID 或到期时间。")
        }
        name = plist["Name"] as? String ?? url.deletingPathExtension().lastPathComponent
        teamName = plist["TeamName"] as? String ?? ""
        applicationIdentifier = identifier
        expirationDate = expiration
        devices = (plist["ProvisionsAllDevices"] as? Bool == true) ? nil : plist["ProvisionedDevices"] as? [String] ?? []
        getTaskAllow = entitlements["get-task-allow"] as? Bool ?? false
        certificateHashes = Set((plist["DeveloperCertificates"] as? [Data] ?? []).map {
            Insecure.SHA1.hash(data: $0).map { String(format: "%02X", $0) }.joined()
        })
    }

    /// 描述文件是 CMS 签名包着的 plist。
    private static func decode(_ data: Data) throws -> [String: Any] {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { throw AppError("无法读取描述文件。") }
        let updated = data.withUnsafeBytes { CMSDecoderUpdateMessage(decoder, $0.baseAddress!, $0.count) }
        var content: CFData?
        guard updated == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess,
              CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content,
              let plist = try PropertyListSerialization.propertyList(from: content as Data, format: nil) as? [String: Any] else {
            throw AppError("这不是有效的 .mobileprovision 描述文件。")
        }
        return plist
    }
}
