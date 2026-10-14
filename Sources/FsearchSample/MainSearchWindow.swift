import AppKit
import Quartz
import FsearchService
import SwiftUI
import UniformTypeIdentifiers

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
            Button("文本内容搜索…") { model.showsContentSearch = true }
                .disabled(!model.canSearchContent)
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
    @State private var showsIndexDetails = false
    @ObservedObject var model: SearchModel
    @ObservedObject var selectionState: SearchSelectionState

    var body: some View {
        VStack(spacing: 0) {
            configuration
            Divider()
            HSplitView {
                resultsPane
                    .frame(minWidth: 640, idealWidth: 780)
                if selectionState.isInspectorVisible {
                    FileInspectorView(result: model.selectedResult, state: inspector)
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
                }
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
        }
        .frame(minWidth: 960, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    selectionState.toggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(selectionState.isInspectorVisible ? "隐藏检查器" : "显示检查器")
                .accessibilityLabel(selectionState.isInspectorVisible ? "隐藏检查器" : "显示检查器")
            }
        }
        .task {
            actions.onFileMutation = model.fileDidChange
            await model.runSmokeIfRequested()
        }
        .task(id: InspectorRequestID(snapshot: model.inspectorRefreshID, paths: selectionState.selectedPaths, primary: selectionState.selectedPath)) {
            actions.updatePreview(path: selectionState.selectedPaths.count == 1 ? selectionState.selectedPath : nil)
            await inspector.select(paths: selectionState.selectedPaths, primary: selectionState.selectedPath)
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("文件名搜索").font(.headline)
                Spacer()
                if !model.canSearchContent {
                    Text("当前模式仅支持文件名搜索")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button { model.showsContentSearch = true } label: {
                    Label("文本内容搜索…", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(!model.canSearchContent)
                .help(model.canSearchContent ? "使用独立输入框搜索文件中的文本" : "样本名称模式不支持正文搜索")
                .accessibilityIdentifier("content-search")
            }

            HStack(spacing: 10) {
                SearchQueryEditor(
                    text: $model.configuration.query,
                    focusRequest: model.focusRequest,
                    onSubmit: model.submit
                )
                    .frame(minWidth: 280, minHeight: 40, maxHeight: 40)
                    .overlay(alignment: .topLeading) {
                        if model.configuration.query.isEmpty {
                            Text("输入文件名或名称片段…")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 4).padding(.top, 9)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }

                Button { model.submit() } label: {
                    Label("查询文件名", systemImage: "magnifyingglass")
                }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.large)
                    .frame(minHeight: 40, maxHeight: 40)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("执行文件名搜索")
                    .accessibilityIdentifier("submit-search")
                if model.busy {
                    Button("取消") { model.cancel() }
                }
            }

            Text("仅搜索文件名，不搜索正文。Return 查询；Shift+Return 输入文件名中的换行。")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("name-search-explanation")

            HStack(spacing: 12) {
                Picker("名称匹配方式", selection: $model.configuration.nameMode) {
                    Text("包含").tag(NameMatchMode.contains)
                    Text("模糊").tag(NameMatchMode.fuzzy)
                    Text("前缀").tag(NameMatchMode.prefix)
                    Text("后缀").tag(NameMatchMode.suffix)
                    Text("完整").tag(NameMatchMode.wholeName)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                .accessibilityLabel("名称匹配方式")
                .accessibilityIdentifier("name-mode")
                SearchFiltersView(configuration: $model.configuration)
            }

            HStack(spacing: 8) {
                Text(model.isEngineMode ? "独立索引" : "样本验证 · 仅覆盖样本目录")
                    .foregroundStyle(.secondary)
                IndexStatusSummary(state: model.permissionStatus)
                Spacer()
                Button("权限与索引…") { showsIndexDetails = true }
                    .popover(isPresented: $showsIndexDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("权限与索引").font(.headline)
                            PermissionStatusView(state: model.permissionStatus, onRecheck: model.recheckPermissions)
                            Text("引擎 \(model.engineVersion)").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16).frame(width: 440)
                    }
            }
            .font(.caption)

            PermissionOnboardingBanner(state: model.permissionStatus)
            if let message = model.applicationMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if model.busy {
                    ProgressView().controlSize(.small)
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
            .frame(minHeight: 250, maxHeight: .infinity)
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
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NameQueryTextView()
        textView.onSubmit = onSubmit
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 4, height: 9)
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
        guard let textView = scrollView.documentView as? NameQueryTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
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

private final class NameQueryTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .command, .control, .option])
        if [36, 76].contains(event.keyCode), !hasMarkedText() {
            if modifiers.isEmpty || modifiers == .command {
                onSubmit?()
                return
            }
            if modifiers == .shift {
                insertNewlineIgnoringFieldEditor(nil)
                return
            }
        }
        super.keyDown(with: event)
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
        table.autoresizingMask = [.width]
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openSelection)
        table.openSelection = { context.coordinator.openSelection() }
        table.previewSelection = { context.coordinator.previewSelection() }
        table.previewController = actions
        actions.movePreviewSelection = { [weak table] delta in table?.moveSelection(by: delta) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        context.coordinator.table = table
        context.coordinator.menuNeedsUpdate(menu)
        table.menu = menu
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.setAccessibilityLabel("搜索结果")
        table.setAccessibilityIdentifier("results-table")

        addColumn(
            to: table,
            identifier: "name",
            title: "名称",
            width: 260,
            minWidth: 150,
            sortKey: SearchSortColumn.name.rawValue
        )
        addColumn(
            to: table,
            identifier: "location",
            title: "位置",
            width: 420,
            minWidth: 180,
            sortKey: nil
        )
        addColumn(
            to: table,
            identifier: "size",
            title: "索引大小",
            width: 110,
            minWidth: 80,
            sortKey: SearchSortColumn.size.rawValue
        )
        addColumn(
            to: table,
            identifier: "modified",
            title: "修改时间",
            width: 180,
            minWidth: 130,
            sortKey: SearchSortColumn.modified.rawValue
        )

        let scrollView = NSScrollView()
        scrollView.documentView = table
        table.sizeToFit()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
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

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: ResultsTableView
        weak var table: NSTableView?
        var isUpdatingSelection = false
        var renderedSelection: Set<String> = []
        var renderedPrimary: String?

        init(parent: ResultsTableView) {
            self.parent = parent
        }

        private struct OpenWithTarget {
            let file: URL
            let application: URL
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let path = parent.selectionState.selectedPaths.count == 1 ? parent.selectionState.selectedPath : nil
            let url = path.map { URL(fileURLWithPath: $0) }
            func add(_ title: String, _ symbol: String, _ selector: Selector) -> NSMenuItem {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                item.target = self
                item.representedObject = url
                item.isEnabled = url != nil && !parent.actions.isMutating
                menu.addItem(item)
                return item
            }
            _ = add(url.map { "打开“\($0.lastPathComponent)”" } ?? "打开", "arrow.up.forward.square", #selector(openSelection(_:)))
            let openWith = add("打开方式", "arrow.up.forward.square", #selector(openSelection(_:)))
            let applications = NSMenu()
            applications.autoenablesItems = false
            if let url {
                let workspace = NSWorkspace.shared
                let defaultApplication = workspace.urlForApplication(toOpen: url)
                for application in workspace.urlsForApplications(toOpen: url) {
                    let name = FileManager.default.displayName(atPath: application.path)
                    let item = NSMenuItem(title: name + (application == defaultApplication ? "（默认）" : ""),
                                          action: #selector(openWithApplication(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = OpenWithTarget(file: url, application: application)
                    item.image = workspace.icon(forFile: application.path).copy() as? NSImage
                    item.image?.size = NSSize(width: 16, height: 16)
                    applications.addItem(item)
                }
                if !applications.items.isEmpty { applications.addItem(.separator()) }
                let other = NSMenuItem(title: "其他…", action: #selector(chooseApplication(_:)), keyEquivalent: "")
                other.target = self
                other.representedObject = url
                applications.addItem(other)
            }
            openWith.submenu = applications
            menu.addItem(.separator())
            _ = add("在 Finder 中显示", "folder", #selector(revealSelection(_:)))
            _ = add("显示简介", "info.circle", #selector(infoSelection(_:)))
            _ = add("快速查看", "eye", #selector(previewSelection(_:)))
            _ = add("重命名…", "pencil", #selector(renameSelection(_:)))
            _ = add("复制路径", "terminal", #selector(copySelection(_:)))
            menu.addItem(.separator())
            _ = add("移到废纸篓", "trash", #selector(trashSelection(_:)))
            _ = add("永久删除…", "trash.slash", #selector(deleteSelection(_:)))
        }

        private func singleSelection(_ sender: Any? = nil) -> String? {
            if let item = sender as? NSMenuItem { return (item.representedObject as? URL)?.path }
            guard parent.selectionState.selectedPaths.count == 1 else {
                parent.actions.requireSingleSelection()
                return nil
            }
            return parent.selectionState.selectedPath
        }

        @objc func openSelection(_ sender: Any? = nil) {
            guard let path = singleSelection(sender) else { return }
            parent.actions.open(path: path)
        }
        @objc func revealSelection(_ sender: Any? = nil) {
            guard let path = singleSelection(sender) else { return }
            parent.actions.reveal(path: path)
        }
        @objc func copySelection(_ sender: Any? = nil) {
            guard let path = singleSelection(sender) else { return }
            parent.actions.copy(path: path)
        }
        @objc func previewSelection(_ sender: Any? = nil) {
            guard let path = singleSelection(sender) else { return }
            parent.actions.togglePreview(path: path)
        }

        @objc func openWithApplication(_ sender: NSMenuItem) {
            guard let target = sender.representedObject as? OpenWithTarget else { return }
            parent.actions.open(path: target.file.path, with: target.application)
        }

        @objc func chooseApplication(_ sender: NSMenuItem) {
            guard let path = singleSelection(sender), let window = table?.window else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowsMultipleSelection = false
            panel.prompt = "打开"
            panel.beginSheetModal(for: window) { [self] response in
                guard response == .OK, let application = panel.url else { return }
                parent.actions.open(path: path, with: application)
            }
        }

        @objc func infoSelection(_ sender: NSMenuItem) {
            guard let path = singleSelection(sender) else { return }
            parent.actions.showInfo(path: path)
        }

        @objc func renameSelection(_ sender: NSMenuItem) {
            guard let path = singleSelection(sender) else { return }
            parent.actions.requestRename(path: path, in: table?.window)
        }

        @objc func trashSelection(_ sender: NSMenuItem) {
            guard let path = singleSelection(sender) else { return }
            Task { await parent.actions.moveToTrash(path: path) }
        }

        @objc func deleteSelection(_ sender: NSMenuItem) {
            guard let path = singleSelection(sender) else { return }
            let window = table?.window
            Task { await parent.actions.permanentlyDelete(path: path, in: window) }
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
