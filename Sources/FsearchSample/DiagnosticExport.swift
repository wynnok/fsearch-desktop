import AppKit
import Foundation
import FsearchService
import UniformTypeIdentifiers

// An allowlist prevents arbitrary upstream text, paths and document bodies from
// entering the report; stderr is deliberately discarded rather than regex-masked.
struct DiagnosticReport: Encodable {
    let clientVersion: String
    let engineVersion: String
    let architecture: String
    let systemVersion: String
    let errorCategory: String
    let errorExplanation: String
    let nameIndexReady: Bool?
    let contentPending: Int?
    let coverageSignal: String

    init(status: ServiceStatus?, error: Error? = nil, stderr: String? = nil) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        clientVersion = Self.safeVersion(version)
        engineVersion = Self.safeVersion(status?.upstreamVersion ?? "")
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        systemVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        nameIndexReady = status?.ready
        contentPending = status?.contentPending
        coverageSignal = status?.fullDiskAccess.map { $0 ? "engine-reports-access; coverage-unverified" : "restricted" } ?? "unknown"
        if let error = error as? FsearchError {
            switch error {
            case .initialization:
                errorCategory = "initialization"
                errorExplanation = "引擎初始化失败；检查独立索引目录与权限后重试。"
            case .query:
                errorCategory = "query"
                errorExplanation = "查询失败；检查搜索条件后重试。"
            case .bridge:
                errorCategory = "bridge"
                errorExplanation = "引擎桥接或服务操作失败；重新检查状态，必要时重启。"
            }
        } else {
            errorCategory = error == nil ? "none" : "other"
            errorExplanation = error == nil ? "未记录服务错误。" : "操作失败；可重新检查状态并重试。"
        }
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    private static func safeVersion(_ value: String) -> String {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return "unknown" }
        return value
    }
}

@MainActor
enum DiagnosticExporter {
    static func present(status: ServiceStatus?, error: Error? = nil) -> String? {
        let panel = NSSavePanel()
        panel.title = "导出诊断报告"
        panel.message = "报告只包含应用/引擎版本、架构、系统版本、索引状态和错误类别。不会包含完整文件路径、文件正文、查询历史或原始 stderr；不会自动上传。"
        panel.nameFieldStringValue = "Fsearch-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try DiagnosticReport(status: status, error: error).write(to: url)
            return "诊断报告已保存。"
        } catch {
            return "无法保存诊断报告，请检查目标位置权限后重试。"
        }
    }
}
