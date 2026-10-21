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
    let engineVersion: String
    let onRecheck: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(FDTheme.hairlineColor)
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    if let failure = state.failureMessage {
                        FDNoticeBanner(text: failure,
                                       symbol: "exclamationmark.triangle.fill",
                                       tint: FDTheme.clay)
                    }
                    if state.needsRestart {
                        FDNoticeBanner(text: "授权已变化，请退出并重新打开应用，让索引按新权限扫描。",
                                       symbol: "arrow.clockwise.circle.fill",
                                       tint: FDTheme.ochre)
                    } else if let message = state.recheckMessage {
                        FDNoticeBanner(text: message,
                                       symbol: "info.circle.fill",
                                       tint: FDTheme.sage)
                    }

                    capabilities

                    permissionCard

                    FDCard(padding: 11, tint: FDTheme.teal) {
                        VStack(alignment: .leading, spacing: 5) {
                            FDSectionLabel(title: "搜索边界", symbol: "icloud", tint: FDTheme.teal)
                            Text("云端尚未下载的文件正文可能不可用；应用不会为搜索主动下载它们。PDF、Office、OCR 与压缩包正文不在支持范围内。")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 440)
            Divider().overlay(FDTheme.hairlineColor)
            footer
        }
        .font(.system(size: 12))
        .frame(width: 548)
        .background(FDTheme.canvas)
        .tint(FDTheme.primary)
        .accessibilityIdentifier("permission-index-status")
    }

    private var header: some View {
        HStack(spacing: 11) {
            FDIconTile(symbol: "lock.shield.fill", tint: FDTheme.sage, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("权限与索引")
                    .font(.system(size: 16, weight: .bold))
                Text("了解当前搜索能力，管理受保护位置的访问权限。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FDHeaderBackground(accent: FDTheme.sage))
    }

    private var capabilities: some View {
        FDCard(padding: 12, tint: FDTheme.slate) {
            VStack(alignment: .leading, spacing: 9) {
                FDSectionLabel(title: "当前搜索能力", symbol: "square.stack.3d.up", tint: FDTheme.slate)
                capabilityRow(title: "文件名搜索",
                              symbol: "doc.text.magnifyingglass",
                              tint: FDTheme.slate,
                              message: state.nameMessage,
                              badge: nameBadge)
                Divider().overlay(FDTheme.hairlineColor)
                capabilityRow(title: "文本内容搜索",
                              symbol: "text.magnifyingglass",
                              tint: FDTheme.teal,
                              message: state.contentMessage,
                              badge: contentBadge)
            }
        }
    }

    private func capabilityRow(
        title: String,
        symbol: String,
        tint: Color,
        message: String,
        badge: (text: String, symbol: String, tint: Color)
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            FDIconTile(symbol: symbol, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                    FDStatusPill(text: badge.text, symbol: badge.symbol, tint: badge.tint)
                    Spacer(minLength: 0)
                }
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nameBadge: (text: String, symbol: String, tint: Color) {
        if let status = state.status {
            return status.ready
                ? ("就绪", "checkmark.circle.fill", FDTheme.olive)
                : ("初始化", "clock.fill", FDTheme.ochre)
        }
        return ("未知", "questionmark.circle", .secondary)
    }

    private var contentBadge: (text: String, symbol: String, tint: Color) {
        guard let status = state.status else {
            return ("未知", "questionmark.circle", .secondary)
        }
        if status.mode != "engine" {
            return ("样本模式", "testtube.2", .secondary)
        }
        if let pending = status.contentPending, pending > 0 {
            return ("处理中", "clock.fill", FDTheme.ochre)
        }
        if status.contentPending == 0 {
            return ("已索引", "checkmark.circle.fill", FDTheme.olive)
        }
        return ("未验证", "questionmark.circle", FDTheme.ochre)
    }

    private var permissionCard: some View {
        FDCard(padding: 12, tint: FDTheme.sage) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    FDSectionLabel(title: "完全磁盘访问", symbol: "externaldrive.badge.checkmark", tint: FDTheme.sage)
                    Spacer()
                    Button {
                        state.openPermissionSettings()
                    } label: {
                        Label("打开设置", systemImage: "gearshape.fill")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(FDPrimaryButtonStyle())
                    .controlSize(.small)
                }
                Text(state.coverageMessage)
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                if state.status?.mode == "engine", state.status?.fullDiskAccess == true {
                    DisclosureGroup {
                        permissionInstructions.padding(.top, 8)
                    } label: {
                        Label("权限设置与授权说明", systemImage: "gearshape.2")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    permissionInstructions
                }

                if state.showOnboarding {
                    Button {
                        state.skipOnboarding()
                    } label: {
                        Label("跳过，先搜索已有覆盖", systemImage: "forward.fill")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FDTheme.primary)
                    .accessibilityIdentifier("skip-permission-onboarding")
                }
            }
        }
    }

    private var permissionInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("如需搜索受保护位置，请按以下步骤授权：")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                permissionStep(1, "打开系统设置 → 隐私与安全性 → 完全磁盘访问。")
                permissionStep(2, "添加并启用 FsearchDesktop。")
                permissionStep(3, "返回这里重新检查；若提示授权变化，退出并重新打开应用。")
            }
            Text("应用不会自动修改系统权限。")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
    }

    private func permissionStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(FDTheme.sage)
                .frame(width: 17, height: 17)
                .background(Capsule()
                    .fill(FDTheme.sage.opacity(0.12)))
            Text(text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FDTheme.slate)
            Text("引擎 \(engineVersion.components(separatedBy: " / ")[0])")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button(action: onRecheck) {
                Label(state.isChecking ? "正在检查…" : "重新检查", systemImage: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(FDPrimaryButtonStyle())
            .disabled(state.isChecking)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct IndexStatusSummary: View {
    @ObservedObject var state: PermissionStatusModel

    var body: some View {
        FDStatusPill(text: text, symbol: symbol, tint: tint)
            .help(state.failureMessage ?? state.coverageMessage)
            .accessibilityIdentifier("index-status-summary")
    }

    private var text: String {
        if state.failureMessage != nil { return "状态检查失败" }
        if let status = state.status { return status.ready ? "名称索引就绪" : "名称索引初始化" }
        return "索引状态待检查"
    }

    private var symbol: String {
        if state.failureMessage != nil { return "exclamationmark.triangle.fill" }
        return state.status?.ready == true ? "checkmark.circle.fill" : "clock.fill"
    }

    private var tint: Color {
        if state.failureMessage != nil { return FDTheme.clay }
        return state.status?.ready == true ? FDTheme.olive : FDTheme.ochre
    }
}

struct PermissionOnboardingBanner: View {
    @ObservedObject var state: PermissionStatusModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if state.showOnboarding {
            HStack(spacing: 9) {
                FDIconTile(symbol: "lock.shield.fill", tint: FDTheme.sage, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("让搜索覆盖更多位置")
                        .font(.system(size: 11, weight: .semibold))
                    Text("完全磁盘访问可改善受保护位置的索引覆盖。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    state.openPermissionSettings()
                } label: {
                    Label("打开设置", systemImage: "gearshape.fill")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(FDSecondaryButtonStyle())

                Button {
                    state.skipOnboarding()
                } label: {
                    Label("稍后", systemImage: "xmark")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("skip-permission-onboarding")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
                    .fill(FDTheme.sage.opacity(scheme == .dark ? 0.14 : 0.07))
            }
            .clipShape(RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FDTheme.controlRadius, style: .continuous)
                    .strokeBorder(FDTheme.sage.opacity(0.18), lineWidth: 0.5)
            }
        }
    }
}
