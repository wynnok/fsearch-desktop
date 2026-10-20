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
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FsearchDesktop")
                        .font(.system(size: 22, weight: .semibold))
                    Text("版本 \(state.currentVersion)")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Text("快速查找 Mac 上的文件与文本内容。")
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("搜索引擎").fontWeight(.medium)
                    Spacer()
                    Text("Fsearch \(engineVersion.components(separatedBy: " / ")[0])")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                DisclosureGroup("引擎构建信息") {
                    Text(engineVersion)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .font(.callout)

                Divider()

                HStack(spacing: 8) {
                    Text("软件更新").fontWeight(.medium)
                    if state.phase == .checking {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(state.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("检查更新") { Task { await state.check() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.phase == .checking)
                    Button("前往下载", systemImage: "arrow.up.forward.square") { state.openDownloads() }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 20)

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 20)
        }
        .font(.system(size: 13))
        .padding(24)
        .frame(width: 440)
    }
}
