import Foundation

/// 拖进来的 .ipa，只读取 Info.plist，不解压整个包。
struct IPAPackage {
    let url: URL
    let name: String
    let version: String
    let bundleID: String

    static func load(_ url: URL) async throws -> IPAPackage {
        let entries = try await Shell.text("/usr/bin/unzip", ["-Z1", url.path])
        guard let path = entries.split(separator: "\n").map(String.init)
            .first(where: { $0.wholeMatch(of: #/Payload/[^/]+\.app/Info\.plist/#) != nil }) else {
            throw AppError("这不是有效的 .ipa 安装包。")
        }
        let data = try await Shell.run("/usr/bin/unzip", ["-p", url.path, path])
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String else {
            throw AppError("安装包的 Info.plist 无法读取。")
        }
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        let short = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        let version = build.isEmpty || build == short ? short : "\(short)（\(build)）"
        return IPAPackage(url: url, name: name, version: version, bundleID: bundleID)
    }
}
