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
            recheckMessage = "已重新读取引擎状态；若刚修改系统授权，请退出并重启应用以重新评估覆盖。"
        } catch {
            recordFailure(error)
        }
    }

    var nameMessage: String {
        guard let status else { return "名称索引状态尚未获取" }
        return status.ready ? "名称索引就绪" : "名称索引初始化中"
    }

    var contentMessage: String {
        guard let status else { return "默认在后台建立受支持文本的内容索引；当前界面仅搜索名称。" }
        if let pending = status.contentPending, pending > 0 {
            return "内容索引后台处理中（待处理 \(pending) 项）；当前界面仅搜索名称。"
        }
        if status.contentPending == 0 {
            return "内容队列暂无待处理项；不代表所有文件正文均可搜索。"
        }
        return "内容索引状态未验证；默认在后台处理受支持文本。"
    }

    var coverageMessage: String {
        guard let status else { return "索引覆盖尚未验证" }
        if status.mode != "engine" { return "仅覆盖指定样本目录，真实权限覆盖未验证。" }
        if status.fullDiskAccess == false { return "索引覆盖受限：部分受保护位置可能未收录。" }
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
