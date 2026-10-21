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
    var path: String?
    @ObservedObject var actions: FileActionState
    var onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(FDTheme.hairlineColor)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if state.selectionCount > 1 {
                        multiSelection
                    } else if let result {
                        singleSelection(result)
                    } else {
                        FDEmptyState(symbol: "cursorarrow",
                                     title: "未选择结果",
                                     message: "选择一条结果，查看路径、大小、时间与快捷操作。",
                                     tint: FDTheme.slate)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FDHeaderBackground(accent: FDTheme.slate))
        .tint(FDTheme.primary)
        .accessibilityIdentifier("inspector")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FDTheme.slate)
            Text("检查器")
                .font(.system(size: 12.5, weight: .semibold))
            Spacer()
            FDActionIconButton(symbol: "xmark",
                               label: "隐藏检查器",
                               tint: .secondary,
                               action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func singleSelection(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            hero(result)

            SearchFileActionIconRow(path: path ?? result.path, actions: actions, size: 28)
                .frame(maxWidth: .infinity)

            inspectorCard(title: "位置", symbol: "link", tint: FDTheme.slate) {
                Text(result.path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            inspectorCard(title: "索引记录", symbol: "externaldrive", tint: FDTheme.ochre) {
                metadataRow("索引大小", ByteCountFormatter.string(fromByteCount: Int64(result.indexedSize), countStyle: .file))
                metadataRow("记录时间", Date(timeIntervalSince1970: TimeInterval(result.modifiedAt)).formatted())
                Text("索引记录可能因精度或文件变化与实际不同；实际大小不是磁盘占用。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if state.path == result.path, let details = state.details {
                inspectorCard(title: "实时属性", symbol: "doc.text.magnifyingglass", tint: FDTheme.teal) {
                    metadataRow("类型", details.kind)
                    metadataRow("实际大小", details.size.map {
                        ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                    } ?? "未计算")
                    metadataRow("创建时间", details.created?.formatted() ?? "未知")
                    metadataRow("修改时间", details.modified?.formatted() ?? "未知")
                }
            }

            if !state.message.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: state.details == nil ? "clock" : "info.circle")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(state.details == nil ? FDTheme.ochre : FDTheme.olive)
                    Text(state.message)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func hero(_ result: SearchResult) -> some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: FDTheme.cardRadius, style: .continuous)
                    .fill(FDTheme.slate.opacity(scheme == .dark ? 0.18 : 0.09))
                    .frame(width: 62, height: 62)
                    .overlay(RoundedRectangle(cornerRadius: FDTheme.cardRadius, style: .continuous)
                        .strokeBorder(FDTheme.slate.opacity(0.12), lineWidth: 0.5))
                Image(nsImage: state.path == result.path
                      ? (state.details?.icon ?? NSWorkspace.shared.icon(forFile: result.path))
                      : NSWorkspace.shared.icon(forFile: result.path))
                    .resizable()
                    .frame(width: 38, height: 38)
            }
            Text(URL(fileURLWithPath: result.path).lastPathComponent)
                .font(.system(size: 13.5, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(state.details?.kind ?? "正在读取属性…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var multiSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 7) {
                FDIconTile(symbol: "square.stack.3d.up.fill", tint: FDTheme.sage, size: 46)
                Text("已选择 \(state.selectionCount) 项")
                    .font(.system(size: 13.5, weight: .bold))
                Text("多选模式下不虚构汇总大小")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            inspectorCard(title: "共有位置", symbol: "folder", tint: FDTheme.ochre) {
                Text(state.commonLocation ?? "未知")
                    .font(.system(size: 10.5))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.message.isEmpty {
                FDNoticeBanner(text: state.message, symbol: "info.circle.fill", tint: FDTheme.ochre)
            }
        }
    }

    private func inspectorCard<Content: View>(
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        FDCard(padding: 10, tint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                FDSectionLabel(title: title, symbol: symbol, tint: tint)
                content()
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
