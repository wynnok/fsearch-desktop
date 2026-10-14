import AppKit
import FsearchService
import SwiftUI

struct SearchFiltersView: View {
    @Binding var configuration: SearchConfiguration
    @State private var isExpanded = false

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button("所有已覆盖内置位置") { configuration.scope = .allIndexed }
                Button("个人目录") { configuration.scope = .home }
                Button("选择文件夹…", action: chooseFolder)
            } label: {
                Label(scopeLabel, systemImage: "folder")
            }
            .accessibilityLabel("搜索范围")
            .help(scopeHelp)
            .frame(maxWidth: 250, alignment: .leading)

            Toggle("显示隐藏项", isOn: $configuration.showsHidden)
                .toggleStyle(.checkbox)

            Spacer()

            Button { isExpanded.toggle() } label: {
                Label(filterButtonTitle, systemImage: filterButtonIcon)
            }
            .accessibilityIdentifier("attribute-filter")
        }
        .popover(isPresented: $isExpanded) {
            popover
        }
    }

    private var popover: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("属性筛选").font(.headline)
                Spacer()
                Text(configuration.activeFilterCount == 0 ? "未启用条件" : "已启用 \(configuration.activeFilterCount) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                if configuration.scope != .allIndexed {
                    scopeSummary
                }
                fileTypeSection
                Divider()
                extensionSection
                Divider()
                sizeSection
                Divider()
                modifiedTimeSection
            }
            .padding(16)

            Divider()

            HStack {
                Text(configuration.activeFilterCount == 0 ? "未启用筛选" : "已启用 \(configuration.activeFilterCount) 项条件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部清除") { configuration.clearFilters() }
                    .disabled(configuration.activeFilterCount == 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 560)
    }

    private var scopeSummary: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(scopeLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("仅筛选现有索引；不会建立索引或取得权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var fileTypeSection: some View {
        HStack(spacing: 12) {
            sectionLabel("文件类型")
            Picker("文件类型", selection: $configuration.filters.kind) {
                Text("全部").tag(SearchItemKind?.none)
                Text("文件").tag(SearchItemKind?.some(.file))
                Text("文件夹").tag(SearchItemKind?.some(.directory))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            Spacer(minLength: 0)
        }
    }

    private var extensionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                sectionLabel("扩展名")
                TextField("例如 txt, md", text: extensionBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("扩展名")
                resetButton("清除扩展名",
                            disabled: configuration.filters.extensions.isEmpty) {
                    configuration.filters.extensions = []
                }
            }
            Text("多个扩展名用逗号分隔。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 84)
        }
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                sectionLabel("文件大小")
                TextField("最小", value: $configuration.filters.minimumSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .accessibilityLabel("最小文件大小")
                Text("至")
                    .foregroundStyle(.secondary)
                TextField("最大", value: $configuration.filters.maximumSize, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .accessibilityLabel("最大文件大小")
                Text("字节")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                resetButton("清除文件大小",
                            disabled: configuration.filters.minimumSize == nil
                                && configuration.filters.maximumSize == nil) {
                    configuration.filters.minimumSize = nil
                    configuration.filters.maximumSize = nil
                }
            }
            Text("按索引记录筛选；起止值包含边界，较大文件可能有精度差异。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 84)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modifiedTimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                sectionLabel("修改时间")
                Spacer(minLength: 0)
                resetButton("清除修改时间",
                            disabled: configuration.filters.modifiedAfter == nil
                                && configuration.filters.modifiedBefore == nil) {
                    configuration.filters.modifiedAfter = nil
                    configuration.filters.modifiedBefore = nil
                }
            }

            timeRow(title: "从", key: \.modifiedAfter, accessibilityLabel: "修改时间开始")
            timeRow(title: "到", key: \.modifiedBefore, accessibilityLabel: "修改时间结束")
        }
    }

    private func timeRow(title: String,
                         key: WritableKeyPath<NameSearchFilters, UInt32?>,
                         accessibilityLabel: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(.secondary)
            Toggle("", isOn: enabledBinding(key))
                .labelsHidden()
                .toggleStyle(.checkbox)
            if configuration.filters[keyPath: key] == nil {
                Text("未设置")
                    .foregroundStyle(.tertiary)
                    .frame(width: 190, alignment: .leading)
            } else {
                DatePicker("", selection: dateBinding(key), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .frame(width: 190, alignment: .leading)
                    .accessibilityLabel(accessibilityLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 84)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .frame(width: 72, alignment: .leading)
    }

    private func resetButton(_ help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button("重置", action: action)
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundStyle(disabled ? Color.secondary.opacity(0.55) : Color.accentColor)
            .disabled(disabled)
            .help(help)
            .accessibilityLabel(help)
    }

    private var filterButtonTitle: String {
        configuration.activeFilterCount == 0 ? "属性筛选" : "属性筛选 · \(configuration.activeFilterCount)"
    }

    private var filterButtonIcon: String {
        configuration.activeFilterCount == 0
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
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
