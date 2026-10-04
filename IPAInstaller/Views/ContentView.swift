import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        @Bindable var model = model
        Form {
            CertificateSection()
            PackageSection()
            DeviceSection()
            if !model.log.isEmpty { LogSection() }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { InstallBar() }
        .overlay { if isTargeted { DropHighlight() } }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .fileImporter(isPresented: $model.isChoosingFiles, allowedContentTypes: Self.fileTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.add(urls) }
        }
        .frame(minWidth: 500, minHeight: 600)
        .task { await model.refreshDevices() }
    }

    private static let fileTypes: [UTType] = ["p12", "pfx", "mobileprovision", "ipa"].compactMap { UTType(filenameExtension: $0) }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 12))
            .overlay {
                Label("松开即可添加", systemImage: "arrow.down.doc")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: .capsule)
            }
            .padding(10)
            .allowsHitTesting(false)
    }
}

// MARK: - 证书

private struct CertificateSection: View {
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var isSaving = false

    var body: some View {
        let signing = model.signing
        Section {
            LabeledContent("证书") {
                FileName(signing.certificateName, placeholder: "拖入 .p12 文件")
            }
            if signing.certificateName != nil {
                LabeledContent("密码") {
                    if signing.hasPassword {
                        HStack {
                            Label("已保存在钥匙串", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Button("修改") { signing.forgetPassword() }
                                .buttonStyle(.link)
                        }
                    } else {
                        HStack {
                            SecureField("证书密码", text: $password, prompt: Text("证书密码"))
                                .labelsHidden()
                                .frame(maxWidth: 180)
                                .onSubmit(save)
                            if isSaving { ProgressView().controlSize(.small) }
                            Button("保存", action: save)
                                .disabled(password.isEmpty || isSaving)
                        }
                    }
                }
            }
            LabeledContent("描述文件") {
                FileName(signing.profile?.name, placeholder: "拖入 .mobileprovision 文件")
            }
            if let profile = signing.profile {
                LabeledContent("类型", value: profile.kind)
                LabeledContent("团队") {
                    Text(profile.teamName.isEmpty ? profile.teamID : "\(profile.teamName)（\(profile.teamID)）")
                        .textSelection(.enabled)
                }
                LabeledContent("Bundle ID") {
                    Text(profile.bundleID ?? "通配符，沿用安装包的 ID").textSelection(.enabled)
                }
                LabeledContent("到期") {
                    Text(profile.expirationDate, format: .dateTime.year().month().day())
                        .foregroundStyle(profile.isExpired ? .red : .primary)
                    if profile.isExpired { Text("已过期").foregroundStyle(.red) }
                }
            }
            if let issue = signing.profileIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        } header: {
            HStack {
                Text("签名证书")
                Spacer()
                if signing.certificateName != nil || signing.profile != nil {
                    Button("移除", role: .destructive) { signing.removeAll() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                Button("选择文件…") { model.isChoosingFiles = true }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        } footer: {
            Text("证书和描述文件只需添加一次，会保存在这台 Mac 上。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard !password.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            await model.savePassword(password)
            if model.signing.hasPassword { password = "" }
            isSaving = false
        }
    }
}

private struct FileName: View {
    let name: String?
    let placeholder: String
    init(_ name: String?, placeholder: String) { self.name = name; self.placeholder = placeholder }

    var body: some View {
        if let name {
            Text(name).lineLimit(1).truncationMode(.middle)
        } else {
            Text(placeholder).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 安装包

private struct PackageSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            if let package = model.package {
                LabeledContent("应用") {
                    Text(package.version.isEmpty ? package.name : "\(package.name) \(package.version)")
                }
                LabeledContent("文件") {
                    Text(package.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                }
                LabeledContent("原 Bundle ID") { Text(package.bundleID).textSelection(.enabled) }
                if let target = model.targetBundleID, target != package.bundleID {
                    LabeledContent("安装后") {
                        Text(target).foregroundStyle(Color.accentColor).textSelection(.enabled)
                    }
                }
            } else {
                Text("把 .ipa 安装包拖进窗口").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("安装包")
                Spacer()
                Button(model.package == nil ? "选择文件…" : "更换…") { model.isChoosingFiles = true }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - 设备

private struct DeviceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            if model.devices.isEmpty {
                Text(model.deviceIssue ?? "没有找到已配对的设备。用数据线连接 iPhone，解锁并点“信任此电脑”。")
                    .foregroundStyle(.secondary)
            } else {
                Picker("设备", selection: $model.selectedDeviceID) {
                    ForEach(model.devices) { device in
                        Text(device.isAvailable ? device.summary : "\(device.summary)（未连接）")
                            .tag(Optional(device.id))
                    }
                }
                if let device = model.selectedDevice, let profile = model.signing.profile, !profile.allows(device) {
                    Label("描述文件里没有这台设备（UDID \(device.udid)），装上也打不开。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            HStack {
                Text("设备")
                Spacer()
                if model.isLoadingDevices { ProgressView().controlSize(.mini) }
                Button("刷新") { Task { await model.refreshDevices() } }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(model.isLoadingDevices)
            }
        }
    }
}

// MARK: - 日志

private struct LogSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("日志") {
            Text(model.log.joined(separator: "\n"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 底部

private struct InstallBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            status
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await model.install() }
            } label: {
                Text("安装").frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.blocker != nil || model.phase.isWorking)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var status: some View {
        if let notice = model.notice {
            Label(notice, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else {
            switch model.phase {
            case .working(let step):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(step)
                }
            case .succeeded(let message):
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(2)
            case .idle:
                if let blocker = model.blocker {
                    Text("下一步：\(blocker)").foregroundStyle(.secondary)
                } else {
                    Text("准备就绪").foregroundStyle(.secondary)
                }
            }
        }
    }
}
