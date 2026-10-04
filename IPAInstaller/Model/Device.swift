import Foundation

/// 已与这台 Mac 配对的 iPhone / iPad。
struct Device: Identifiable, Hashable {
    /// devicectl 用的标识。
    let id: String
    /// 描述文件里登记的 UDID。
    let udid: String
    let name: String
    let model: String
    let osVersion: String
    let isAvailable: Bool

    var summary: String {
        [name, model, osVersion.isEmpty ? nil : "iOS \(osVersion)"].compactMap { $0 }.joined(separator: " · ")
    }

    static func paired() async throws -> [Device] {
        let file = FileManager.default.temporaryDirectory.appending(path: "IPAInstaller-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try await Shell.run("/usr/bin/xcrun", ["devicectl", "list", "devices", "--json-output", file.path])
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let items = (root?["result"] as? [String: Any])?["devices"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            let hardware = item["hardwareProperties"] as? [String: Any] ?? [:]
            let properties = item["deviceProperties"] as? [String: Any] ?? [:]
            let connection = item["connectionProperties"] as? [String: Any] ?? [:]
            guard hardware["platform"] as? String == "iOS", hardware["reality"] as? String == "physical",
                  connection["pairingState"] as? String == "paired",
                  let id = item["identifier"] as? String, let udid = hardware["udid"] as? String else { return nil }
            return Device(id: id, udid: udid,
                          name: properties["name"] as? String ?? "iPhone",
                          model: hardware["marketingName"] as? String ?? "",
                          osVersion: properties["osVersionNumber"] as? String ?? "",
                          isAvailable: connection["tunnelState"] as? String != "unavailable")
        }
    }
}
