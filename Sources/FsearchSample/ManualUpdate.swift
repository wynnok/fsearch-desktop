import AppKit
import Combine
import Foundation
import SwiftUI

enum UpdatePhase: Equatable {
    case idle, checking, current, noRelease
    case available(String)
    case failed(String)
}

@MainActor
final class ManualUpdateState: ObservableObject {
    static let releasesURL = URL(string: "https://github.com/wynnok/fsearch-desktop/releases")!
    static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
    @Published private(set) var phase: UpdatePhase = .idle
    let currentVersion: String
    private let fetch: @Sendable () async throws -> Data?

    init(currentVersion: String = ManualUpdateState.clientVersion,
         fetch: @escaping @Sendable () async throws -> Data? = ManualUpdateState.fetchLatest) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    func check() async {
        guard phase != .checking else { return }
        phase = .checking
        do {
            guard let data = try await fetch() else { phase = .noRelease; return }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let prefix = Self.releasesURL.absoluteString + "/tag/"
            guard !release.draft, !release.prerelease,
                  release.html_url.hasPrefix(prefix),
                  let version = Self.version(release.tag_name),
                  let current = Self.version(currentVersion) else {
                throw URLError(.cannotParseResponse)
            }
            phase = current.lexicographicallyPrecedes(version)
                ? .available(version.map(String.init).joined(separator: ".")) : .current
        } catch {
            phase = .failed("检查失败，请稍后重试，或前往下载页面查看版本。")
        }
    }

    var message: String {
        switch phase {
        case .idle: "更新需从 GitHub 下载后手动安装。"
        case .checking: "正在检查更新…"
        case .current: "未发现比当前版本更新的正式版本。"
        case .noRelease: "暂无正式版本，可前往下载页面查看预发布版本。"
        case .available(let version): "发现新版本 \(version)，请下载后手动安装。"
        case .failed(let message): message
        }
    }

    func openDownloads() { NSWorkspace.shared.open(Self.releasesURL) }

    private static func version(_ value: String) -> [Int]? {
        let stripped = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = stripped.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }

    nonisolated private static func fetchLatest() async throws -> Data? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/wynnok/fsearch-desktop/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool
        let prerelease: Bool
    }
}

struct UpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: ManualUpdateState
    let engineVersion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(FDTheme.hairlineColor).padding(.top, 14)

            VStack(alignment: .leading, spacing: 11) {
                engineCard
                updateCard
            }
            .padding(.top, 12)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Text("更新由你从 GitHub 下载后手动安装，不会自动替换应用。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Label("关闭", systemImage: "xmark")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(FDSecondaryButtonStyle())
            }
            .padding(.top, 16)
        }
        .padding(22)
        .frame(width: 468)
        .background(FDTheme.canvas)
        .tint(FDTheme.primary)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(FDTheme.softFillColor)
                    .frame(width: 76, height: 76)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(FDTheme.hairlineColor, lineWidth: 1))
                FDBrandMark(size: 56)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("FsearchDesktop")
                        .font(.system(size: 21, weight: .bold))
                    FDCountBadge(text: "v\(state.currentVersion)", tint: FDTheme.ochre)
                }
                Text("快速查找 Mac 上的文件与文本内容。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    featureChip("文件名搜索", symbol: "doc.text.magnifyingglass", tint: FDTheme.slate)
                    featureChip("文本内容", symbol: "text.magnifyingglass", tint: FDTheme.plum)
                    featureChip("完全本地", symbol: "lock.shield", tint: FDTheme.olive)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    private func featureChip(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(tint.opacity(0.16), lineWidth: 1))
    }

    private var engineCard: some View {
        FDCard(padding: 12, tint: FDTheme.ochre) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    FDSectionLabel(title: "搜索引擎", symbol: "cpu", tint: FDTheme.ochre)
                    Spacer()
                    Text("Fsearch \(engineVersion.components(separatedBy: " / ")[0])")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                DisclosureGroup {
                    Text(engineVersion)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 5)
                } label: {
                    Label("引擎构建信息", systemImage: "info.circle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var updateCard: some View {
        FDCard(padding: 12, tint: FDTheme.plum) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 9) {
                    FDIconTile(symbol: "arrow.triangle.2.circlepath", tint: FDTheme.plum, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("软件更新")
                                .font(.system(size: 11.5, weight: .semibold))
                            FDStatusPill(text: updateBadge.text,
                                         symbol: updateBadge.symbol,
                                         tint: updateBadge.tint,
                                         showsProgress: state.phase == .checking)
                            Spacer(minLength: 0)
                        }
                        Text(state.message)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        Task { await state.check() }
                    } label: {
                        Label("检查更新", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(FDPrimaryButtonStyle())
                    .disabled(state.phase == .checking)

                    Button {
                        state.openDownloads()
                    } label: {
                        Label("前往下载", systemImage: "arrow.up.forward.square")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(FDSecondaryButtonStyle())
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var updateBadge: (text: String, symbol: String, tint: Color) {
        switch state.phase {
        case .idle:
            return ("待检查", "clock", .secondary)
        case .checking:
            return ("检查中", "arrow.clockwise", FDTheme.slate)
        case .current:
            return ("已是最新", "checkmark.circle.fill", FDTheme.olive)
        case .noRelease:
            return ("暂无正式版", "questionmark.circle", FDTheme.ochre)
        case .available:
            return ("有新版本", "arrow.down.circle.fill", FDTheme.plum)
        case .failed:
            return ("检查失败", "exclamationmark.triangle.fill", FDTheme.clay)
        }
    }
}
