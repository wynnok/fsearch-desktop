import AppKit
import Combine
import FsearchService
import SwiftUI

struct FileDetails: @unchecked Sendable {
    var kind: String
    var size: Int64?
    var created: Date?
    var modified: Date?
    var icon: NSImage?
    var cloudPlaceholder: Bool = false
}

// One serial queue bounds filesystem and icon work, including during rapid selection changes.
private let inspectorQueue = DispatchQueue(label: "fsearch.inspector", qos: .userInitiated)

@MainActor
final class FileInspectorState: ObservableObject {
    typealias Reader = @Sendable (String) async throws -> FileDetails
    @Published private(set) var path: String?
    @Published private(set) var details: FileDetails?
    @Published private(set) var message = "未选择结果"
    @Published private(set) var selectionCount = 0
    @Published private(set) var commonLocation: String?
    private var generation = 0
    private let reader: Reader

    init(reader: @escaping Reader = FileInspectorState.read) { self.reader = reader }

    func select(paths: Set<String>, primary: String?) async {
        selectionCount = paths.count
        commonLocation = nil
        if paths.count > 1 {
            generation += 1
            path = nil
            details = nil
            var common = URL(fileURLWithPath: paths.sorted()[0]).deletingLastPathComponent()
            for path in paths {
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                while common.path != "/" && !(parent == common.path || parent.hasPrefix(common.path + "/")) {
                    common.deleteLastPathComponent()
                }
            }
            commonLocation = common.path
            message = "已选择 \(paths.count) 项；请选择单个结果以查看属性或执行文件动作"
            return
        }
        await select(path: primary ?? paths.first)
    }

    func select(path: String?) async {
        selectionCount = path == nil ? 0 : 1
        commonLocation = nil
        generation += 1
        let request = generation
        self.path = path
        details = nil
        guard let path else { message = "未选择结果"; return }
        message = "正在读取当前属性…"
        do {
            let details = try await reader(path)
            guard request == generation else { return }
            self.details = details
            message = details.cloudPlaceholder ? "云端占位文件；未下载内容" : "当前文件属性"
        } catch {
            guard request == generation else { return }
            message = "属性不可读：文件可能已移动、删除或没有访问权限"
        }
    }

    nonisolated static func read(_ path: String) async throws -> FileDetails {
        try await withCheckedThrowingContinuation { continuation in
            inspectorQueue.async {
                do {
                    let url = URL(fileURLWithPath: path)
                    let attributes = try FileManager.default.attributesOfItem(atPath: path)
                    let type = attributes[.type] as? FileAttributeType
                    let values = try? url.resourceValues(forKeys: [.isPackageKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                    let directory = type == .typeDirectory
                    let kind = type == .typeSymbolicLink ? "符号链接（属性为链接本身）"
                        : values?.isPackage == true ? "应用包 / 文件包（大小未递归计算）"
                        : directory ? "文件夹（大小未递归计算）" : "文件（\(url.pathExtension.isEmpty ? "无扩展名" : url.pathExtension)）"
                    continuation.resume(returning: FileDetails(
                        kind: kind,
                        size: directory ? nil : (attributes[.size] as? NSNumber)?.int64Value,
                        created: attributes[.creationDate] as? Date,
                        modified: attributes[.modificationDate] as? Date,
                        icon: NSWorkspace.shared.icon(forFile: path),
                        cloudPlaceholder: values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current
                    ))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct FileInspectorView: View {
    let result: SearchResult?
    @ObservedObject var state: FileInspectorState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("检查器").font(.headline)
            if state.selectionCount > 1 {
                Text("已选择 \(state.selectionCount) 项").font(.headline)
                row("共有位置", state.commonLocation ?? "未知")
                Text(state.message).font(.caption).foregroundStyle(.secondary)
            } else if let result {
                HStack(alignment: .top) {
                    if state.path == result.path, let icon = state.details?.icon {
                        Image(nsImage: icon).resizable().frame(width: 48, height: 48)
                    }
                    Text(URL(fileURLWithPath: result.path).lastPathComponent)
                        .font(.headline).textSelection(.enabled)
                }
                row("完整路径", result.path)
                row("索引大小", "\(result.indexedSize) 字节")
                Text("索引记录可能因精度或文件变化与实际大小不同；实际大小不是磁盘占用。")
                    .font(.caption).foregroundStyle(.secondary)
                if state.path == result.path, let details = state.details {
                    row("类型", details.kind)
                    row("实际大小", details.size.map { "\($0) 字节" } ?? "未计算（不汇总目录内容）")
                    row("创建时间", details.created?.formatted() ?? "未知")
                    row("修改时间", details.modified?.formatted() ?? "未知")
                } else {
                    row("索引修改时间", Date(timeIntervalSince1970: TimeInterval(result.modifiedAt)).formatted())
                }
                Text(state.message).font(.caption).foregroundStyle(.secondary)
            } else { Text("未选择结果").foregroundStyle(.secondary) }
            Spacer()
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("inspector")
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).textSelection(.enabled)
        }
    }
}
