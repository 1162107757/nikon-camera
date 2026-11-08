import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct OnlinePreset: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let category: String?
    let fileUrl: String
    let sha256: String
    let byteLength: Int
    let fileFormat: String?
    var format: String { (fileFormat ?? (URL(string: fileUrl)?.pathExtension ?? "ncp")).uppercased() }
    var sample: String {
        let names = ["alpine-lake", "breakfast", "city-skyline", "coastal-water", "neon-street", "pink-tulips", "portrait-man", "portrait-smile", "rainy-tokyo", "sunlit-forest"]
        return names[(Int(sha256.prefix(4), radix: 16) ?? 0) % names.count]
    }
}
struct LocalPreset: Identifiable {
    let id: String
    let name: String
    let url: URL
    var format: String { url.pathExtension.uppercased() }
}
struct AppMessage: Identifiable { let id = UUID(); let title: String; let detail: String }

@MainActor final class AppModel: ObservableObject {
    @Published var tab = 0
    @Published var catalog = [OnlinePreset]()
    @Published var local = [LocalPreset]()
    @Published var catalogBusy = false
    @Published var catalogError: String?
    @Published var downloadID: String?
    @Published var cameraBusy = false
    @Published var cameraStatus = "尚未连接相机"
    @Published var snapshot: CameraSnapshot?
    @Published var pendingPreset: LocalPreset?
    @Published var importPreset: LocalPreset?
    @Published var message: AppMessage?
    @Published var host = UserDefaults.standard.string(forKey: "camera.host") ?? "192.168.1.1" { didSet { UserDefaults.standard.set(host, forKey: "camera.host") } }
    @Published var port = UserDefaults.standard.string(forKey: "camera.port") ?? "15740" { didSet { UserDefaults.standard.set(port, forKey: "camera.port") } }
    private let camera = NikonCamera()
    private var healthTask: Task<Void, Never>?
    private var generation = 0
    private let endpoint = URL(string: "https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library/")!
    private var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Presets", isDirectory: true) }
    init() {
        reloadLocal()
        // Launch verification only chooses a real screen; it never substitutes camera or catalog data.
        if ProcessInfo.processInfo.arguments.contains("--qa-camera") { tab = 1 }
        if ProcessInfo.processInfo.arguments.contains("--qa-settings") { tab = 2 }
        if ProcessInfo.processInfo.arguments.contains("--qa-image-audit") {
            let names = ["alpine-lake", "breakfast", "city-skyline", "coastal-water", "neon-street", "pink-tulips", "portrait-man", "portrait-smile", "rainy-tokyo", "sunlit-forest"]
            let checks: [[String: Any]] = names.map { name in
                let image = UIImage(named: name, in: .main, compatibleWith: nil)
                return ["name": name, "decoded": image?.cgImage != nil, "width": image?.cgImage?.width ?? 0, "height": image?.cgImage?.height ?? 0]
            }
            if let data = try? JSONSerialization.data(withJSONObject: checks, options: .prettyPrinted) {
                try? data.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("qa-image-audit.json"), options: .atomic)
            }
        }
    }
    func showError(_ error: Error) { message = AppMessage(title: "操作未完成", detail: error.localizedDescription) }
    func refreshCatalog() async {
        guard !catalogBusy else { return }; catalogBusy = true; defer { catalogBusy = false }
        do {
            let bytes = try await fetch(endpoint.appendingPathComponent("catalog.json"), limit: 4 * 1024 * 1024)
            struct Catalog: Decodable { let presets: [OnlinePreset] }
            let result = try JSONDecoder().decode(Catalog.self, from: bytes)
            guard result.presets.count <= 2000 else { throw HueviaError("预设库数据超过上限。") }
            catalog = result.presets; catalogError = nil
        } catch { catalogError = error.localizedDescription }
    }
    private func fetch(_ url: URL, limit: Int) async throws -> Data {
        guard url.scheme == "https", url.host == endpoint.host, url.path.hasPrefix(endpoint.path) else { throw HueviaError("下载地址不属于官方预设库。") }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == endpoint.host else { throw HueviaError("预设库暂时不可用，请检查网络后重试。") }
        return try Self.readBounded(temporary, limit: limit)
    }
    static func readBounded(_ url: URL, limit: Int = 1_048_576) throws -> Data {
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        let bytes = try input.read(upToCount: limit + 1) ?? Data()
        guard !bytes.isEmpty, bytes.count <= limit else { throw HueviaError("文件为空或超过允许大小。") }
        return bytes
    }
    func download(_ preset: OnlinePreset) async -> LocalPreset? {
        guard downloadID == nil else { return nil }; downloadID = preset.id; defer { downloadID = nil }
        do {
            guard let url = URL(string: preset.fileUrl), (8...1_048_576).contains(preset.byteLength),
                  preset.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw HueviaError("预设信息不完整。") }
            let bytes = try await fetch(url, limit: 1_048_576)
            guard bytes.count == preset.byteLength, NCPConverter.sha256(bytes) == preset.sha256 else { throw HueviaError("下载文件校验失败，未保存。") }
            return try save(bytes, name: preset.name, ext: url.pathExtension)
        } catch { showError(error); return nil }
    }
    func addFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { _ = try save(Self.readBounded(url), name: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension) }
        catch { showError(error) }
    }
    private func save(_ bytes: Data, name: String, ext: String) throws -> LocalPreset {
        let ext = ext.lowercased()
        guard ["ncp", "np3"].contains(ext), bytes.count <= 1_048_576, bytes.count >= 8 else { throw HueviaError("请选择 NCP 或 NP3 预设文件。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hash = NCPConverter.sha256(bytes), url = directory.appendingPathComponent(hash + "." + ext)
        try bytes.write(to: url, options: .atomic)
        UserDefaults.standard.set(name, forKey: "preset.name." + hash); reloadLocal()
        return LocalPreset(id: hash, name: name, url: url)
    }
    func reloadLocal() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        local = files.filter { ["ncp", "np3"].contains($0.pathExtension.lowercased()) }.compactMap { url in
            let hash = url.deletingPathExtension().lastPathComponent
            guard hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
            return LocalPreset(id: hash, name: UserDefaults.standard.string(forKey: "preset.name." + hash) ?? hash.prefix(12).description, url: url)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func requestImport(_ preset: LocalPreset) {
        do {
            let bytes = try Self.readBounded(preset.url)
            guard NCPConverter.sha256(bytes) == preset.id else { throw HueviaError("预设文件内容已变化，请重新添加。") }
            _ = try NCPConverter.convert(bytes)
            if snapshot == nil { pendingPreset = preset; tab = 1 }
            else { importPreset = preset }
        } catch { showError(error) }
    }
    func connect() async {
        guard !cameraBusy else { return }
        guard let portValue = UInt16(port), portValue > 0 else { showError(HueviaError("相机端口填写不正确。")); return }
        cameraBusy = true; cameraStatus = "正在连接并读取槽位…"; generation += 1
        let current = generation; defer { if current == generation { cameraBusy = false } }
        var guid = UserDefaults.standard.data(forKey: "camera.guid")
        if guid?.count != 16 { var uuid = UUID().uuid; guid = withUnsafeBytes(of: &uuid) { Data($0) }; UserDefaults.standard.set(guid!, forKey: "camera.guid") }
        do {
            let result = try await camera.connect(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: portValue, guid: guid!)
            guard current == generation else { return }; snapshot = result; cameraStatus = "已连接 " + result.info.model
            healthTask?.cancel(); healthTask = Task { [weak self, camera] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { break }
                    if !(await camera.isConnected()) {
                        guard let self, self.generation == current else { return }
                        self.snapshot = nil; self.cameraStatus = "相机连接已断开，请重新连接。"; return
                    }
                }
            }
        } catch { if current == generation { snapshot = nil; cameraStatus = error.localizedDescription } }
    }
    func disconnect() {
        generation += 1; let current = generation; healthTask?.cancel(); healthTask = nil; cameraBusy = true; snapshot = nil; cameraStatus = "正在断开连接…"
        Task { await camera.disconnect(); if generation == current { cameraBusy = false; cameraStatus = "尚未连接相机" } }
    }
    func refreshSlots() async {
        guard !cameraBusy else { return }; cameraBusy = true; defer { cameraBusy = false }
        do { snapshot = try await camera.refresh(); cameraStatus = "槽位已更新" }
        catch { snapshot = nil; cameraStatus = error.localizedDescription }
    }
    func confirmImport(_ preset: LocalPreset, slot: CameraSlot, confirmed: CameraSnapshot) async {
        guard !cameraBusy else { return }; cameraBusy = true; defer { cameraBusy = false }
        do {
            let bytes = try Self.readBounded(preset.url)
            guard NCPConverter.sha256(bytes) == preset.id else { throw HueviaError("预设内容已变化，请重新添加。") }
            snapshot = try await camera.importPreset(bytes, to: slot, snapshot: confirmed)
            importPreset = nil; pendingPreset = nil
            message = AppMessage(title: "已导入 " + slot.label, detail: "已从相机读回并核对预设内容。请在相机照片菜单中选择该优化校准。")
            cameraStatus = "导入已核对；继续导入前请刷新槽位。"
        } catch { if !(await camera.isConnected()) { snapshot = nil }; showError(error) }
    }
}
