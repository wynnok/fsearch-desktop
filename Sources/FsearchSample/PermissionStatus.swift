import AppKit
import Combine
import Foundation
import FsearchService
import SwiftUI

@MainActor
final class PermissionStatusModel: ObservableObject {
    @Published private(set) var showOnboarding: Bool
    @Published private(set) var status: ServiceStatus?
    @Published private(set) var failureMessage: String?
    @Published private(set) var recheckMessage: String?
    @Published private(set) var isChecking = false
    private let onDismiss: () -> Void

    init(onboardingDismissed: Bool = false, onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
        showOnboarding = !onboardingDismissed
    }

    func skipOnboarding() {
        onDismiss()
        showOnboarding = false
    }

    func apply(_ status: ServiceStatus) {
        self.status = status
        failureMessage = nil
    }

    func recordFailure(_ error: Error) {
        failureMessage = "服务状态检查失败，可重新检查并重试。"
    }

    func recheck(load: () async throws -> ServiceStatus) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            apply(try await load())
            recheckMessage = needsRestart
                ? "已识别授权变化，请退出并重新打开 FsearchDesktop，让索引按新权限扫描。"
                : "已重新检查完全磁盘访问权限和索引状态。"
        } catch {
            recordFailure(error)
        }
    }

    var nameMessage: String {
        guard let status else { return "名称索引状态尚未获取" }
        return status.ready ? "名称索引就绪" : "名称索引初始化中"
    }

    var contentMessage: String {
        guard let status else { return "正在获取文本内容索引状态。" }
        if status.mode != "engine" { return "样本模式不提供文本内容搜索。" }
        if let pending = status.contentPending, pending > 0 {
            return "文本内容索引后台处理中（待处理 \(pending) 项）；可通过“文本内容搜索”查询。"
        }
        if status.contentPending == 0 {
            return "已索引 \(status.contentDocs ?? 0) 个文本文件；可通过“文本内容搜索”查询。"
        }
        return "内容索引状态未验证；默认在后台处理受支持文本。"
    }

    var needsRestart: Bool {
        guard let current = status?.fullDiskAccess, let startup = status?.fullDiskAccessAtStartup else { return false }
        return current != startup
    }

    var coverageMessage: String {
        guard let status else { return "索引覆盖尚未验证" }
        if status.mode != "engine" { return "仅覆盖指定样本目录，真实权限覆盖未验证。" }
        if needsRestart { return "已识别完全磁盘访问授权变化；请退出并重新打开应用以更新索引覆盖。" }
        if status.fullDiskAccess == false { return "索引覆盖受限：部分受保护位置可能未收录。" }
        if status.fullDiskAccess == true {
            return status.ready
                ? "完全磁盘访问已授权；名称索引就绪，可搜索已收录文件。"
                : "完全磁盘访问已授权；正在建立全盘名称索引。"
        }
        return "索引覆盖未验证：名称就绪和引擎权限信号不能证明所有位置可读。"
    }

    func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}

struct PermissionStatusView: View {
    @ObservedObject var state: PermissionStatusModel
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.showOnboarding {
                Text("完全磁盘访问可改善受保护位置的索引覆盖。你可以先跳过，搜索已有覆盖；应用不会自动修改系统权限。")
                Button("跳过，先搜索已有覆盖") { state.skipOnboarding() }
                    .accessibilityIdentifier("skip-permission-onboarding")
            }
            Text(state.nameMessage)
            Text(state.contentMessage)
            Text(state.coverageMessage)
            Text("云端尚未下载的文件正文可能不可用；应用不会为搜索主动下载它们。")
            if let failure = state.failureMessage { Text(failure).foregroundStyle(.red) }
            if let message = state.recheckMessage { Text(message) }
            HStack {
                Button("打开完全磁盘访问设置") { state.openPermissionSettings() }
                Button("重新检查") { onRecheck() }.disabled(state.isChecking)
            }
            Text("在系统设置 → 隐私与安全性 → 完全磁盘访问中添加并启用本应用，然后重新检查；授权变化可能需要退出并重启。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("permission-index-status")
    }
}

struct IndexStatusSummary: View {
    @ObservedObject var state: PermissionStatusModel

    var body: some View {
        Label(state.failureMessage ?? "\(state.nameMessage) · \(state.coverageMessage)",
              systemImage: state.failureMessage == nil ? "info.circle" : "exclamationmark.triangle")
            .foregroundStyle(state.failureMessage == nil ? Color.secondary : Color.red)
            .lineLimit(1)
            .help(state.failureMessage ?? state.coverageMessage)
            .accessibilityIdentifier("index-status-summary")
    }
}

struct PermissionOnboardingBanner: View {
    @ObservedObject var state: PermissionStatusModel

    var body: some View {
        if state.showOnboarding {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                Text("完全磁盘访问可改善受保护位置的索引覆盖。可在“权限与索引”中查看说明，或先搜索已有覆盖。")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("先搜索已有覆盖") { state.skipOnboarding() }
                    .accessibilityIdentifier("skip-permission-onboarding")
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
