import SwiftUI
import UniformTypeIdentifiers

@main struct HueviaApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .tint(Color(red: 0.66, green: 0.26, blue: 0.18))
                .onOpenURL { model.addFile($0); model.tab = 0 }
                .onChange(of: scenePhase) { phase in if phase == .background { model.disconnect() } }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabView(selection: $model.tab) {
            PresetsView().tabItem { Label("预设", systemImage: "camera.filters") }.tag(0)
            CameraView().tabItem { Label("相机", systemImage: "camera") }.tag(1)
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .alert(item: Binding(get: { model.importPreset == nil ? model.message : nil }, set: { model.message = $0 })) { m in Alert(title: Text(m.title), message: Text(m.detail), dismissButton: .default(Text("知道了"))) }
        .sheet(item: $model.importPreset) { preset in ImportSheet(preset: preset).environmentObject(model) }
    }
}

struct PresetsView: View {
    @EnvironmentObject var model: AppModel
    @State private var source = 0
    @State private var query = ""
    @State private var choosingFile = false
    private var filtered: [OnlinePreset] {
        model.catalog.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || ($0.category ?? "").localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("预设来源", selection: $source) { Text("在线预设").tag(0); Text("我的预设").tag(1) }
                    .pickerStyle(.segmented).padding()
                if source == 0 { online } else { saved }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("预设")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { choosingFile = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加本地预设") } }
            .searchable(text: $query, prompt: "搜索预设")
            .task { if model.catalog.isEmpty { await model.refreshCatalog() } }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in
                switch result { case .success(let url): model.addFile(url); source = 1; case .failure(let error): model.showError(error) }
            }
        }
    }
    @ViewBuilder private var online: some View {
        if model.catalogBusy && model.catalog.isEmpty {
            Spacer(); ProgressView("正在加载预设…"); Spacer()
        } else if let error = model.catalogError, model.catalog.isEmpty {
            Spacer(); VStack(spacing: 16) { Image(systemName: "wifi.exclamationmark").font(.largeTitle); Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center); Button("重试") { Task { await model.refreshCatalog() } }.buttonStyle(.borderedProminent) }.padding(32); Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 20) {
                    ForEach(filtered) { preset in
                        NavigationLink { PresetDetail(preset: preset) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(preset.sample).resizable().scaledToFill().frame(height: 192).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(preset.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                Text([preset.category ?? "", preset.format].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding()
                if filtered.isEmpty { Text("没有找到匹配的预设").foregroundStyle(.secondary).padding(32) }
            }.refreshable { await model.refreshCatalog() }
        }
    }
    private var saved: some View {
        List {
            if model.local.isEmpty {
                Section { Label("还没有本地预设", systemImage: "tray"); Text("下载在线预设，或点右上角添加 NCP／NP3 文件。连接相机前先完成下载。").foregroundStyle(.secondary) }
            }
            ForEach(model.local.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { preset in
                Section {
                    VStack(alignment: .leading, spacing: 6) { Text(preset.name).font(.headline); Text(preset.format).font(.caption).foregroundStyle(.secondary) }
                    ShareLink(item: preset.url) { Label("分享文件", systemImage: "square.and.arrow.up") }
                    Button { model.requestImport(preset) } label: { Label("导入相机", systemImage: "camera") }
                }
            }
        }.listStyle(.insetGrouped).onAppear { model.reloadLocal() }
    }
}

struct PresetDetail: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let preset: OnlinePreset
    @State private var local: LocalPreset?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(preset.sample).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) {
                    Text(preset.name).font(.title2.bold())
                    Text(preset.description ?? "").foregroundStyle(.secondary)
                    Text("摄影参考样片，不代表该预设的相机实拍效果。").font(.caption).foregroundStyle(.secondary)
                }
                if let local {
                    Button { dismiss(); model.requestImport(local) } label: { Label("导入相机", systemImage: "camera").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent)
                    ShareLink(item: local.url) { Label("分享预设文件", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.bordered)
                } else {
                    Button { Task { local = await model.download(preset) } } label: {
                        HStack { if model.downloadID == preset.id { ProgressView() } else { Image(systemName: "arrow.down") }; Text(model.downloadID == preset.id ? "正在下载…" : "下载预设") }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(model.downloadID != nil)
                }
            }.padding()
        }.navigationTitle("预设详情").navigationBarTitleDisplayMode(.inline)
    }
}

struct CameraView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(model.cameraStatus, systemImage: model.snapshot == nil ? "wifi" : "checkmark.circle")
                    if let info = model.snapshot?.info { LabeledContent("相机", value: info.model); LabeledContent("固件", value: info.firmware) }
                }
                if model.snapshot == nil {
                    Section("连接相机") {
                        Text("先在相机打开“连接至电脑”无线连接，再到 iPhone 设置加入相机 Wi‑Fi；返回后点连接。首次连接需允许本地网络访问。").foregroundStyle(.secondary)
                        TextField("相机 IP", text: $model.host).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.cameraBusy)
                        TextField("端口", text: $model.port).keyboardType(.numberPad).disabled(model.cameraBusy)
                        Button { Task { await model.connect() } } label: { HStack { if model.cameraBusy { ProgressView() }; Text(model.cameraBusy ? "连接中…" : "连接并读取槽位") } }.disabled(model.cameraBusy)
                        if model.cameraBusy { Button("取消连接", role: .cancel) { model.disconnect() } }
                    }
                    Section { Text("iOS 首版仅针对 Nikon Z6II 的 Wi‑Fi 预设导入做适配，实际兼容性仍需相机验证。请先下载预设，再加入相机 Wi‑Fi。").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    if let preset = model.pendingPreset {
                        Section { Button { model.importPreset = preset } label: { Label("继续导入“\(preset.name)”", systemImage: "arrow.turn.up.right") } }
                    }
                    Section("相机槽位") {
                        ForEach(model.snapshot!.slots) { slot in HStack { Text(slot.label).font(.headline); Spacer(); Text(slot.isEmpty ? "空槽位" : slot.name).foregroundStyle(.secondary) } }
                        Button("刷新槽位") { Task { await model.refreshSlots() } }.disabled(model.cameraBusy)
                    }
                    Section { Button("断开连接", role: .destructive) { model.disconnect() } }
                }
            }.navigationTitle("相机")
        }
    }
}

struct ImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let preset: LocalPreset
    @State private var selected: UInt32?
    @State private var confirmation = false
    @State private var frozen: CameraSnapshot?
    private var slot: CameraSlot? { frozen?.slots.first { $0.id == selected } }
    var body: some View {
        NavigationStack {
            List {
                Section { Text(preset.name).font(.headline); Text("兼容导入会沿用相机标准模式的中等范围锐化和清晰度。原预设文件会保留。").font(.footnote).foregroundStyle(.secondary) }
                Section("选择相机槽位") {
                    if let frozen {
                        ForEach(frozen.slots) { item in
                            Button { selected = item.id } label: { HStack { Text(item.label).foregroundStyle(.primary); Text(item.isEmpty ? "空槽位" : item.name).foregroundStyle(.secondary); Spacer(); if selected == item.id { Image(systemName: "checkmark") } }.frame(minHeight: 44) }.disabled(model.cameraBusy)
                        }
                    } else { Text("连接已断开，请关闭后重新连接。").foregroundStyle(.secondary) }
                }
                if let slot {
                    Section {
                        Button { confirmation = true } label: { HStack { if model.cameraBusy { ProgressView() }; Text(model.cameraBusy ? "正在导入并核对…" : "导入 " + slot.label) }.frame(maxWidth: .infinity) }.disabled(model.cameraBusy)
                    } footer: { if !slot.isEmpty { Text("此槽位已有“\(slot.name)”，继续会覆盖该槽位。") } }
                }
            }
            .navigationTitle("导入相机").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(model.cameraBusy) } }
            .onAppear { frozen = model.snapshot }
            .interactiveDismissDisabled(model.cameraBusy)
            .alert(item: $model.message) { m in Alert(title: Text(m.title), message: Text(m.detail), dismissButton: .default(Text("知道了"))) }
            .confirmationDialog(slot.map { $0.isEmpty ? "确认导入 " + $0.label + "？" : "确认覆盖 " + $0.label + "？" } ?? "确认导入？", isPresented: $confirmation, titleVisibility: .visible) {
                if let slot, let frozen { Button("确认导入", role: slot.isEmpty ? nil : .destructive) { Task { await model.confirmImport(preset, slot: slot, confirmed: frozen) } } }
                Button("取消", role: .cancel) { }
            } message: { Text("将“\(preset.name)”写入所选槽位，并从相机读回核对。请勿在导入过程中切换 Wi‑Fi 或关闭相机。") }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section { LabeledContent("Huevia", value: "iOS 0.1.0 · 体验版"); Text("让照片，有自己的色彩。").foregroundStyle(.secondary) }
                Section("当前功能") { Label("在线预设与文件下载", systemImage: "square.grid.2x2"); Label("本地 NCP／NP3 文件与分享", systemImage: "folder"); Label("Z6II Wi‑Fi 槽位读取与兼容导入", systemImage: "camera") }
                Section { Text("相机导入首版仅支持已适配的 NCP 0100 子集，NP3 可保存和分享。相机连接和导入仍需实体 iPhone 与相机复测。").font(.footnote).foregroundStyle(.secondary); Link("产品官网", destination: URL(string: "https://huevia.cc/")!) }
                Section("样片来源") { Text("摄影参考沿用 Huevia 已选用的十张 Pexels 摄影素材；完整来源随安装包的摄影清单提供。").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("设置")
        }
    }
}
