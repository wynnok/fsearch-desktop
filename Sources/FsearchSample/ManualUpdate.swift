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
            phase = .failed("无法检查更新，请稍后重试或打开项目 Releases。")
        }
    }

    var message: String {
        switch phase {
        case .idle: "由你从 Releases 下载并手动安装更新。"
        case .checking: "正在检查正式版本…"
        case .current: "未发现比当前版本更新的正式版本。"
        case .noRelease: "项目尚无可用的正式 Release。"
        case .available(let version): "可下载新版本 \(version)，请手动安装。"
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
        VStack(alignment: .leading, spacing: 14) {
            Text("FsearchDesktop \(state.currentVersion)").font(.headline)
            Text("固定引擎：\(engineVersion)").textSelection(.enabled)
            Text(state.message)
            HStack {
                Button("检查更新") { Task { await state.check() } }.disabled(state.phase == .checking)
                Button("打开 Releases 下载") { state.openDownloads() }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}
