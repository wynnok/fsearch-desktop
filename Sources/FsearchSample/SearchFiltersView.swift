import AppKit
import FsearchService
import SwiftUI

// MARK: - Scope

struct SearchScopeMenu: View {
    @Binding var configuration: SearchConfiguration

    var body: some View {
        Menu {
            Button("所有已覆盖内置位置", systemImage: "externaldrive.fill") {
                configuration.scope = .allIndexed
            }
            Button("个人目录", systemImage: "house.fill") {
                configuration.scope = .home
            }
            Divider()
            Button("选择文件夹…", systemImage: "folder.badge.plus", action: chooseFolder)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scopeSymbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(FDTheme.ochre)
                    .symbolRenderingMode(.hierarchical)
                Text(scopeLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 148, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .modifier(FDGlassSurface())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("搜索范围")
        .help(scopeHelp)
    }

    private var scopeLabel: String {
        switch configuration.scope {
        case .allIndexed: "全部位置"
        case .home: "个人目录"
        case .folder(let path): URL(fileURLWithPath: path).lastPathComponent
        }
    }

    private var scopeSymbol: String {
        switch configuration.scope {
        case .allIndexed: "externaldrive.fill"
        case .home: "house.fill"
        case .folder: "folder.fill"
        }
    }

    private var scopeHelp: String {
        switch configuration.scope {
        case .allIndexed: "搜索所有已覆盖内置位置"
        case .home: "仅筛选现有索引中的个人目录，不会建立索引或取得权限。"
        case .folder(let path): "文件夹：\(path)\n仅筛选现有索引，不会建立索引或取得权限。"
        }
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

struct SearchHiddenToggle: View {
    @Binding var configuration: SearchConfiguration

    var body: some View {
        Toggle(isOn: $configuration.showsHidden) {
            Label("隐藏项", systemImage: configuration.showsHidden ? "eye" : "eye.slash")
                .font(.system(size: 11.5, weight: .medium))
        }
        .toggleStyle(.checkbox)
        .fixedSize()
        .help(configuration.showsHidden ? "当前显示隐藏文件；点击隐藏" : "当前隐藏隐藏文件；点击显示")
    }
}

// MARK: - Attribute filters

struct SearchFiltersView: View {
    @Binding var configuration: SearchConfiguration
    @State private var isExpanded = false

    var body: some View {
        Button { isExpanded.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: filterButtonIcon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(FDTheme.ochre)
                    .symbolRenderingMode(.hierarchical)
                Text("属性筛选")
                    .font(.system(size: 11.5, weight: .medium))
                if configuration.activeFilterCount > 0 {
                    FDCountBadge(text: "\(configuration.activeFilterCount)", tint: FDTheme.ochre)
                }
            }
        }
        .buttonStyle(FDSecondaryButtonStyle())
        .accessibilityIdentifier("attribute-filter")
        .help(configuration.activeFilterCount == 0 ? "按类型、扩展名、大小或时间缩小结果" : "已启用 \(configuration.activeFilterCount) 项属性条件")
        .popover(isPresented: $isExpanded) {
            FilterPopover(configuration: $configuration)
        }
    }

    private var filterButtonIcon: String {
        configuration.activeFilterCount == 0
            ? "line.3.horizontal.decrease"
            : "line.3.horizontal.decrease.circle.fill"
    }
}

private struct FilterPopover: View {
    @Binding var configuration: SearchConfiguration

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(FDTheme.hairlineColor)
            ScrollView {
                VStack(spacing: 10) {
                    filterCard(
                        title: "文件类型",
                        symbol: "doc.on.doc",
                        tint: FDTheme.slate,
                        resetHelp: "重置文件类型",
                        resetDisabled: configuration.filters.kind == nil
                    ) {
                        configuration.filters.kind = nil
                    } content: {
                        FDSegmentedPicker(
                            options: [
                                .init(value: SearchItemKind?.none, title: "全部", symbol: "square.grid.2x2", tint: FDTheme.slate),
                                .init(value: SearchItemKind?.some(.file), title: "文件", symbol: "doc", tint: FDTheme.slate),
                                .init(value: SearchItemKind?.some(.directory), title: "文件夹", symbol: "folder", tint: FDTheme.slate)
                            ],
                            selection: $configuration.filters.kind,
                            accessibilityLabel: "文件类型"
                        )
                    }

                    filterCard(
                        title: "扩展名",
                        symbol: "tag",
                        tint: FDTheme.teal,
                        resetHelp: "清除扩展名",
                        resetDisabled: configuration.filters.extensions.isEmpty
                    ) {
                        configuration.filters.extensions = []
                    } content: {
                        VStack(alignment: .leading, spacing: 5) {
                            TextField("例如 txt, md", text: extensionBinding)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("扩展名")
                            Text("多个扩展名用逗号分隔")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    filterCard(
                        title: "文件大小",
                        symbol: "externaldrive",
                        tint: FDTheme.ochre,
                        resetHelp: "清除文件大小",
                        resetDisabled: configuration.filters.minimumSize == nil
                            && configuration.filters.maximumSize == nil
                    ) {
                        configuration.filters.minimumSize = nil
                        configuration.filters.maximumSize = nil
                    } content: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                TextField("最小", value: $configuration.filters.minimumSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 104)
                                    .accessibilityLabel("最小文件大小")
                                Text("至").foregroundStyle(.secondary)
                                TextField("最大", value: $configuration.filters.maximumSize, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 104)
                                    .accessibilityLabel("最大文件大小")
                                Text("字节").foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                            Text("按索引记录筛选，起止值包含边界；较大文件可能有精度差异")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    filterCard(
                        title: "修改时间",
                        symbol: "clock",
                        tint: FDTheme.rose,
                        resetHelp: "清除修改时间",
                        resetDisabled: configuration.filters.modifiedAfter == nil
                            && configuration.filters.modifiedBefore == nil
                    ) {
                        configuration.filters.modifiedAfter = nil
                        configuration.filters.modifiedBefore = nil
                    } content: {
                        VStack(alignment: .leading, spacing: 7) {
                            timeRow(title: "从",
                                    key: \.modifiedAfter,
                                    accessibilityLabel: "修改时间开始")
                            timeRow(title: "到",
                                    key: \.modifiedBefore,
                                    accessibilityLabel: "修改时间结束")
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 430)
            Divider().overlay(FDTheme.hairlineColor)
            footer
        }
        .frame(width: 548)
        .background(FDTheme.canvas)
        .tint(FDTheme.primary)
    }

    private var header: some View {
        HStack(spacing: 11) {
            FDIconTile(symbol: "line.3.horizontal.decrease", tint: FDTheme.ochre, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("属性筛选")
                    .font(.system(size: 15, weight: .bold))
                Text(configuration.activeFilterCount == 0
                     ? "缩小范围，快速找到目标文件"
                     : "已启用 \(configuration.activeFilterCount) 项条件")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                configuration.clearFilters()
            } label: {
                Label("全部清除", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(FDSecondaryButtonStyle())
            .disabled(configuration.activeFilterCount == 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FDHeaderBackground(accent: FDTheme.ochre))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text("筛选只缩小现有索引，不建立新索引，也不授予访问权限。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func filterCard<Content: View>(
        title: String,
        symbol: String,
        tint: Color,
        resetHelp: String,
        resetDisabled: Bool,
        reset: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        FDCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    FDSectionLabel(title: title, symbol: symbol, tint: tint)
                    Spacer()
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(resetDisabled ? Color.secondary.opacity(0.4) : tint)
                    .disabled(resetDisabled)
                    .help(resetHelp)
                    .accessibilityLabel(resetHelp)
                }
                content()
            }
        }
    }

    private func timeRow(
        title: String,
        key: WritableKeyPath<NameSearchFilters, UInt32?>,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Toggle("", isOn: enabledBinding(key))
                .labelsHidden()
                .toggleStyle(.checkbox)
            if configuration.filters[keyPath: key] == nil {
                Text("未设置")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DatePicker("", selection: dateBinding(key), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .frame(maxWidth: 200, alignment: .leading)
                    .accessibilityLabel(accessibilityLabel)
                Spacer(minLength: 0)
            }
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
}
