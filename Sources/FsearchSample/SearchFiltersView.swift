import AppKit
import FsearchService
import SwiftUI

struct SearchFiltersView: View {
    @Binding var configuration: SearchConfiguration
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Button("所有已覆盖内置位置") { configuration.scope = .allIndexed }
                    Button("个人目录") { configuration.scope = .home }
                    Button("选择文件夹…", action: chooseFolder)
                } label: {
                    Label(scopeLabel, systemImage: "folder")
                }
                .accessibilityLabel("搜索范围")
                .help(scopeHelp)
                .frame(maxWidth: 250)
                Toggle("显示隐藏项", isOn: $configuration.showsHidden)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(configuration.filters.isEffective ? "属性筛选 · 已启用" : "属性筛选") { isExpanded.toggle() }
            }
        }
        .popover(isPresented: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("搜索范围与属性筛选").font(.headline)
                if case .folder(let path) = configuration.scope {
                    Text(path).font(.caption).textSelection(.enabled)
                }
                if configuration.scope != .allIndexed {
                    Text("仅筛选现有索引；选择文件夹不会建立索引或取得权限。外接和网络卷未纳入默认内置磁盘覆盖。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Picker("类型", selection: $configuration.filters.kind) {
                        Text("文件和目录").tag(SearchItemKind?.none)
                        Text("文件").tag(SearchItemKind?.some(.file))
                        Text("目录").tag(SearchItemKind?.some(.directory))
                    }.frame(maxWidth: 230)
                    Button("清除类型") { configuration.filters.kind = nil }
                    TextField("扩展名（逗号分隔，如 txt,pdf）", text: extensionBinding)
                        .accessibilityLabel("扩展名")
                    Button("清除扩展名") { configuration.filters.extensions = [] }
                }
                HStack {
                    Text("索引大小（字节）")
                    TextField("最小值", value: $configuration.filters.minimumSize, format: .number)
                        .accessibilityLabel("最小索引大小")
                    Text("至")
                    TextField("最大值", value: $configuration.filters.maximumSize, format: .number)
                        .accessibilityLabel("最大索引大小")
                    Button("清除大小") {
                        configuration.filters.minimumSize = nil
                        configuration.filters.maximumSize = nil
                    }
                }
                HStack {
                    Toggle("修改时间从", isOn: enabledBinding(\.modifiedAfter))
                    if configuration.filters.modifiedAfter != nil {
                        DatePicker("开始日期", selection: dateBinding(\.modifiedAfter), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().accessibilityLabel("修改时间开始日期")
                    }
                    Spacer()
                }
                .toggleStyle(.checkbox)
                HStack {
                    Toggle("至", isOn: enabledBinding(\.modifiedBefore))
                    if configuration.filters.modifiedBefore != nil {
                        DatePicker("结束日期", selection: dateBinding(\.modifiedBefore), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().accessibilityLabel("修改时间结束日期")
                    }
                    Button("清除时间") {
                        configuration.filters.modifiedAfter = nil
                        configuration.filters.modifiedBefore = nil
                    }
                    Spacer()
                    Button("清除所有属性筛选") { configuration.clearFilters() }
                        .disabled(!configuration.filters.isEffective)
                }
                .toggleStyle(.checkbox)
                Text("大小以索引记录为准，可能存在精度差异；大小和修改时间包含两端边界。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(width: 700)
        }
    }

    private var scopeLabel: String {
        switch configuration.scope {
        case .allIndexed: "所有已覆盖内置位置"
        case .home: "个人目录"
        case .folder(let path): "文件夹：\(URL(fileURLWithPath: path).lastPathComponent)"
        }
    }

    private var scopeHelp: String {
        switch configuration.scope {
        case .allIndexed: "搜索所有已覆盖内置位置"
        case .home: "仅筛选现有索引中的个人目录，不会建立索引或取得权限。"
        case .folder(let path): "\(path)\n仅筛选现有索引，不会建立索引或取得权限。"
        }
    }

    private var extensionBinding: Binding<String> {
        Binding(get: { configuration.filters.extensions.joined(separator: ",") }, set: { text in
            configuration.filters.extensions = text.isEmpty ? []
                : text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        })
    }

    private func enabledBinding(_ key: WritableKeyPath<NameSearchFilters, UInt32?>) -> Binding<Bool> {
        Binding(get: { configuration.filters[keyPath: key] != nil }, set: { enabled in
            configuration.filters[keyPath: key] = enabled ? UInt32(Date().timeIntervalSince1970) : nil
        })
    }

    private func dateBinding(_ key: WritableKeyPath<NameSearchFilters, UInt32?>) -> Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: Double(configuration.filters[keyPath: key] ?? 0)) }, set: { date in
            configuration.filters[keyPath: key] = UInt32(max(0, min(Double(UInt32.max), date.timeIntervalSince1970)))
        })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择搜索范围"
        panel.message = "此选择仅筛选现有索引，不会建立新索引或授予访问权限。"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                configuration.scope = .folder(url.path)
            }
        }
    }
}
