import AppKit
import Quartz
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
            Button("权限与索引重新检查") { model.recheckPermissions() }
            Button("导出诊断报告…") { model.exportDiagnostics() }
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

private struct InspectorRequestID: Hashable {
    let snapshot: UUID?
    let paths: Set<String>
    let primary: String?
}

struct SearchView: View {
    @StateObject private var inspector = FileInspectorState()
    @StateObject private var actions = FileActionState()
    @ObservedObject var model: SearchModel
    @ObservedObject var selectionState: SearchSelectionState

    var body: some View {
        VStack(spacing: 0) {
            configuration
            Divider()
            HSplitView {
                resultsPane
                    .frame(minWidth: 520, idealWidth: 700)
                if selectionState.isInspectorVisible {
                    FileInspectorView(result: model.selectedResult, state: inspector)
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
        .task { await model.runSmokeIfRequested() }
        .task(id: InspectorRequestID(snapshot: model.inspectorRefreshID, paths: selectionState.selectedPaths, primary: selectionState.selectedPath)) {
            actions.updatePreview(path: selectionState.selectedPaths.count == 1 ? selectionState.selectedPath : nil)
            await inspector.select(paths: selectionState.selectedPaths, primary: selectionState.selectedPath)
        }
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
                Text("引擎 \(model.engineVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SearchFiltersView(configuration: $model.configuration)
            PermissionStatusView(state: model.permissionStatus, onRecheck: model.recheckPermissions)
            if let message = model.applicationMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                SearchQueryEditor(
                    text: $model.configuration.query,
                    focusRequest: model.focusRequest
                )
                    .frame(minWidth: 280, minHeight: 48, maxHeight: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.35))
                    }

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
            if let message = model.selectionMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            ResultsTableView(
                results: model.results,
                selectionState: selectionState,
                sort: model.sort,
                onSort: model.sortBy,
                actions: actions
            )
            Divider()
            PathNavigationView(path: selectionState.selectedPaths.count == 1 ? selectionState.selectedPath : nil, actions: actions)
            if let message = actions.message {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
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

private struct SearchQueryEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text
        textView.setAccessibilityLabel("文件名")
        textView.setAccessibilityIdentifier("main-query")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SearchQueryEditor
        var lastFocusRequest: Int

        init(parent: SearchQueryEditor) {
            self.parent = parent
            self.lastFocusRequest = parent.focusRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

final class NonAnimatingTableView: NSTableView {
    var openSelection: (() -> Void)?
    var previewSelection: (() -> Void)?
    var previewController: FileActionState?
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = previewController
            panel.delegate = previewController
        }
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.shift, .command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 76:
            openSelection?()
        case 49:
            previewSelection?()
        case 125:
            moveSelection(by: 1)
        case 126:
            moveSelection(by: -1)
        default:
            super.keyDown(with: event)
        }
    }

    override func scrollRowToVisible(_ row: Int) {
        guard row >= 0, row < numberOfRows,
              let clipView = enclosingScrollView?.contentView else {
            return
        }
        var target = clipView.bounds
        let rowRect = rect(ofRow: row)
        if rowRect.minY < target.minY {
            target.origin.y = rowRect.minY
        } else if rowRect.maxY > target.maxY {
            target.origin.y = min(rowRect.maxY - target.height, max(0, bounds.height - target.height))
        }
        clipView.scroll(to: target.origin)
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    func moveSelection(by delta: Int) {
        guard numberOfRows > 0 else { return }
        let current = selectedRow >= 0 ? selectedRow : 0
        let next = max(0, min(numberOfRows - 1, current + delta))
        selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        scrollRowToVisible(next)
    }
}

private struct ResultsTableView: NSViewRepresentable {
    let results: [SearchResult]
    @ObservedObject var selectionState: SearchSelectionState
    let sort: NameSort
    let onSort: (SearchSortColumn) -> Void
    let actions: FileActionState

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NonAnimatingTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openSelection)
        table.openSelection = { context.coordinator.openSelection() }
        table.previewSelection = { context.coordinator.previewSelection() }
        table.previewController = actions
        actions.movePreviewSelection = { [weak table] delta in table?.moveSelection(by: delta) }
        let menu = NSMenu()
        for (title, selector) in [("打开", #selector(Coordinator.openSelection)),
                                  ("在 Finder 显示所选项目", #selector(Coordinator.revealSelection)),
                                  ("复制完整路径", #selector(Coordinator.copySelection)),
                                  ("Quick Look", #selector(Coordinator.previewSelection))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = context.coordinator
            menu.addItem(item)
        }
        table.menu = menu
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
        let coordinator = context.coordinator
        let origin = scrollView.contentView.bounds.origin
        let firstVisible = table.row(at: NSPoint(x: 0, y: origin.y))
        let anchor = firstVisible >= 0 && firstVisible < coordinator.parent.results.count
            ? coordinator.parent.results[firstVisible].path : nil
        let offset = firstVisible >= 0 ? origin.y - table.rect(ofRow: firstVisible).minY : 0
        let selectionChanged = coordinator.renderedSelection != selectionState.selectedPaths
            || coordinator.renderedPrimary != selectionState.selectedPath
        coordinator.isUpdatingSelection = true
        coordinator.parent = self
        table.reloadData()

        let desiredDescriptors = sortDescriptors
        if table.sortDescriptors.first?.key != desiredDescriptors.first?.key
            || table.sortDescriptors.first?.ascending != desiredDescriptors.first?.ascending {
            table.sortDescriptors = desiredDescriptors
        }
        let rows = IndexSet(results.indices.filter { selectionState.selectedPaths.contains(results[$0].path) })
        table.selectRowIndexes(rows, byExtendingSelection: false)
        if let anchor, let row = results.firstIndex(where: { $0.path == anchor }) {
            let y = table.rect(ofRow: row).minY + offset
            scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: max(0, min(y, table.bounds.height - scrollView.contentView.bounds.height))))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        if selectionChanged, let primary = selectionState.selectedPath,
           let row = results.firstIndex(where: { $0.path == primary }) {
            table.scrollRowToVisible(row)
        }
        coordinator.renderedSelection = selectionState.selectedPaths
        coordinator.renderedPrimary = selectionState.selectedPath
        coordinator.isUpdatingSelection = false
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
        var renderedSelection: Set<String> = []
        var renderedPrimary: String?

        init(parent: ResultsTableView) {
            self.parent = parent
        }

        @MainActor private func singleSelection() -> String? {
            guard parent.selectionState.selectedPaths.count == 1 else {
                parent.actions.requireSingleSelection()
                return nil
            }
            return parent.selectionState.selectedPath
        }

        @MainActor @objc func openSelection() {
            guard let path = singleSelection() else { return }
            parent.actions.open(path: path)
        }
        @MainActor @objc func revealSelection() {
            guard let path = singleSelection() else { return }
            parent.actions.reveal(path: path)
        }
        @MainActor @objc func copySelection() {
            guard let path = singleSelection() else { return }
            parent.actions.copy(path: path)
        }
        @MainActor @objc func previewSelection() {
            guard let path = singleSelection() else { return }
            parent.actions.togglePreview(path: path)
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
            let paths = Set(tableView.selectedRowIndexes.compactMap { index in
                index < parent.results.count ? parent.results[index].path : nil
            })
            parent.selectionState.select(paths: paths, primary: row >= 0 && row < parent.results.count ? parent.results[row].path : nil)
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
