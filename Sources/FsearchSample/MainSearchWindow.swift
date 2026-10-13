import AppKit
import FsearchService
import SwiftUI

enum SearchActivity {
    case idle
    case querying
    case sorting
}

enum SearchStatusKind {
    case prompt
    case querying
    case sorting
    case cancelled
    case error
    case noMatch
    case partial
    case complete
}

enum SearchSortColumn: String {
    case name
    case size
    case modified
}

struct SearchCommands: Commands {
    @ObservedObject var model: SearchModel
    @ObservedObject var selectionState: SearchSelectionState

    var body: some Commands {
        CommandMenu("搜索") {
            Button("聚焦搜索") { model.requestSearchFocus() }
                .keyboardShortcut("f", modifiers: .command)
            Button("查询") { model.submit() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("刷新") { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
            Button("取消") { model.cancel() }
                .keyboardShortcut(.cancelAction)
                .disabled(!model.busy)
            Divider()
            Button(selectionState.isInspectorVisible ? "隐藏检查器" : "显示检查器") {
                selectionState.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var selectionState: SearchSelectionState
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            configuration
            Divider()
            HSplitView {
                resultsPane
                    .frame(minWidth: 520, idealWidth: 700)
                if selectionState.isInspectorVisible {
                    InspectorView(result: model.selectedResult)
                        .frame(minWidth: 240, idealWidth: 300)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.requestSearchFocus()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("聚焦搜索")
                .accessibilityLabel("聚焦搜索")

                Button {
                    selectionState.toggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(selectionState.isInspectorVisible ? "隐藏检查器" : "显示检查器")
                .accessibilityLabel(selectionState.isInspectorVisible ? "隐藏检查器" : "显示检查器")
            }
        }
        .onChange(of: model.focusRequest) { _ in
            queryFocused = true
        }
        .task { await model.runSmokeIfRequested() }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.isEngineMode ? "真实 Engine" : "样本验证")
                    .font(.headline)
                Text(model.isEngineMode
                     ? "独立索引；就绪不代表全盘覆盖"
                     : "仅查询指定样本目录；未启动真实 Engine")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Fsearch 0.2.1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                TextEditor(text: $model.configuration.query)
                    .font(.body)
                    .frame(minWidth: 280, minHeight: 48, maxHeight: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.35))
                    }
                    .focused($queryFocused)
                    .accessibilityLabel("文件名")
                    .accessibilityIdentifier("main-query")

                Picker("名称匹配方式", selection: $model.configuration.nameMode) {
                    Text("包含").tag(NameMatchMode.contains)
                    Text("模糊").tag(NameMatchMode.fuzzy)
                    Text("前缀").tag(NameMatchMode.prefix)
                    Text("后缀").tag(NameMatchMode.suffix)
                    Text("完整").tag(NameMatchMode.wholeName)
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                .accessibilityIdentifier("name-mode")

                Button("查询") { model.submit() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("submit-search")
                Button("刷新") { model.refresh() }
                    .disabled(model.busy)
                if model.busy {
                    Button("取消") { model.cancel() }
                }
            }

            HStack(spacing: 8) {
                if model.busy {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.message)
                    .foregroundStyle(statusColor)
                    .textSelection(.enabled)
                    .accessibilityLabel("搜索状态")
                    .accessibilityValue(model.message)
                    .accessibilityIdentifier("query-status")
                Spacer()
                Text("排序：\(model.sortTitle)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("current-sort")
            }
            .font(.caption)
        }
        .padding(12)
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            ResultsTableView(
                results: model.results,
                selection: $selectionState.selectedPath,
                sort: model.sort,
                onSort: model.sortBy
            )
            Divider()
            HStack {
                if let pagination = model.paginationMessage {
                    Text(pagination)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("载入更多") { model.loadMore() }
                    .disabled(model.nextCursor == nil || model.busy)
                    .accessibilityIdentifier("load-more")
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
    }

    private var statusColor: Color {
        switch model.statusKind {
        case .error:
            return .red
        case .partial, .sorting:
            return .orange
        case .querying:
            return .blue
        case .complete:
            return .primary
        case .prompt, .cancelled, .noMatch:
            return .secondary
        }
    }
}

private struct InspectorView: View {
    let result: SearchResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("检查器")
                .font(.headline)
            if let result {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: result.path))
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(fileURLWithPath: result.path).lastPathComponent)
                            .font(.headline)
                            .lineLimit(3)
                            .textSelection(.enabled)
                        Text(kindName(result.kind))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                inspectorRow("位置", URL(fileURLWithPath: result.path).deletingLastPathComponent().path)
                inspectorRow("索引大小", "\(result.indexedSize) 字节")
                inspectorRow(
                    "修改时间",
                    Date(timeIntervalSince1970: TimeInterval(result.modifiedAt)).formatted()
                )
                inspectorRow("关联性分数", String(result.score))
            } else {
                Spacer()
                Text("未选择结果")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("inspector")
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func kindName(_ kind: UInt8) -> String {
        switch kind {
        case 0: "文件"
        case 1: "文件夹"
        case 2: "链接"
        default: "其他"
        }
    }
}

private struct ResultsTableView: NSViewRepresentable {
    let results: [SearchResult]
    @Binding var selection: String?
    let sort: NameSort
    let onSort: (SearchSortColumn) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.setAccessibilityLabel("搜索结果")
        table.setAccessibilityIdentifier("results-table")

        addColumn(
            to: table,
            identifier: "name",
            title: "名称",
            width: 260,
            minWidth: 170,
            sortKey: SearchSortColumn.name.rawValue
        )
        addColumn(
            to: table,
            identifier: "location",
            title: "位置",
            width: 420,
            minWidth: 220,
            sortKey: nil
        )
        addColumn(
            to: table,
            identifier: "size",
            title: "索引大小",
            width: 110,
            minWidth: 90,
            sortKey: SearchSortColumn.size.rawValue
        )
        addColumn(
            to: table,
            identifier: "modified",
            title: "修改时间",
            width: 180,
            minWidth: 150,
            sortKey: SearchSortColumn.modified.rawValue
        )

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let table = scrollView.documentView as? NSTableView else { return }
        context.coordinator.parent = self
        table.reloadData()

        let desiredDescriptors = sortDescriptors
        if table.sortDescriptors.first?.key != desiredDescriptors.first?.key
            || table.sortDescriptors.first?.ascending != desiredDescriptors.first?.ascending {
            table.sortDescriptors = desiredDescriptors
        }

        context.coordinator.isUpdatingSelection = true
        if let selection, let row = results.firstIndex(where: { $0.id == selection }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
        context.coordinator.isUpdatingSelection = false
    }

    private var sortDescriptors: [NSSortDescriptor] {
        switch sort {
        case .relevance:
            return []
        case .ascending:
            return [NSSortDescriptor(key: SearchSortColumn.name.rawValue, ascending: true)]
        case .descending:
            return [NSSortDescriptor(key: SearchSortColumn.name.rawValue, ascending: false)]
        case .sizeAscending:
            return [NSSortDescriptor(key: SearchSortColumn.size.rawValue, ascending: true)]
        case .sizeDescending:
            return [NSSortDescriptor(key: SearchSortColumn.size.rawValue, ascending: false)]
        case .modifiedAscending:
            return [NSSortDescriptor(key: SearchSortColumn.modified.rawValue, ascending: true)]
        case .modifiedDescending:
            return [NSSortDescriptor(key: SearchSortColumn.modified.rawValue, ascending: false)]
        }
    }

    private func addColumn(
        to table: NSTableView,
        identifier: String,
        title: String,
        width: CGFloat,
        minWidth: CGFloat,
        sortKey: String?
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = minWidth
        if let sortKey {
            column.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
        }
        table.addTableColumn(column)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ResultsTableView
        var isUpdatingSelection = false

        init(parent: ResultsTableView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.results.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard row >= 0, row < parent.results.count, let tableColumn else { return nil }
            let result = parent.results[row]
            let identifier = NSUserInterfaceItemIdentifier("result-cell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingMiddle
                textField.maximumNumberOfLines = 1
                cell.addSubview(textField)
                cell.textField = textField
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }

            switch tableColumn.identifier.rawValue {
            case "location":
                cell.textField?.stringValue = URL(fileURLWithPath: result.path)
                    .deletingLastPathComponent().path
            case "size":
                cell.textField?.stringValue = ByteCountFormatter.string(
                    fromByteCount: Int64(result.indexedSize),
                    countStyle: .file
                )
            case "modified":
                cell.textField?.stringValue = Date(
                    timeIntervalSince1970: TimeInterval(result.modifiedAt)
                ).formatted()
            default:
                cell.textField?.stringValue = URL(fileURLWithPath: result.path).lastPathComponent
            }
            cell.textField?.toolTip = result.path
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection,
                  let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            parent.selection = row >= 0 && row < parent.results.count
                ? parent.results[row].id
                : nil
        }

        func tableView(
            _ tableView: NSTableView,
            sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  let column = SearchSortColumn(rawValue: key) else { return }
            let current = parent.sort
            let requested: NameSort
            switch (column, descriptor.ascending) {
            case (.name, true): requested = .ascending
            case (.name, false): requested = .descending
            case (.size, true): requested = .sizeAscending
            case (.size, false): requested = .sizeDescending
            case (.modified, true): requested = .modifiedAscending
            case (.modified, false): requested = .modifiedDescending
            }
            if requested != current {
                parent.onSort(column)
            }
        }
    }
}
