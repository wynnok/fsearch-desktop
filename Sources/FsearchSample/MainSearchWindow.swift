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

enum SearchFooterLayout {
    // NSPathControl's standard style draws its content inside the control frame.
    static let pathContentLeadingInset: CGFloat = 10

    static func textLeadingInset(alignsWithPathContent: Bool) -> CGFloat {
        alignsWithPathContent ? pathContentLeadingInset : 0
    }
}

struct SearchCommands: Commands {
    @ObservedObject var model: SearchModel
    @ObservedObject var selectionState: SearchSelectionState

    var body: some Commands {
        CommandMenu("搜索") {
            Button("聚焦搜索", systemImage: "magnifyingglass") { model.requestSearchFocus() }
                .keyboardShortcut("f", modifiers: .command)
            Button("查询", systemImage: "text.magnifyingglass") { model.submit() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("刷新", systemImage: "arrow.clockwise") { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
            Button("权限与索引重新检查", systemImage: "lock.shield") { model.recheckPermissions() }
            Button("导出诊断报告…", systemImage: "square.and.arrow.up") { model.exportDiagnostics() }
            Button("文本内容搜索…", systemImage: "text.magnifyingglass") { model.showsContentSearch = true }
                .disabled(!model.canSearchContent)
            Button("取消", systemImage: "xmark.circle") { model.cancel() }
                .keyboardShortcut(.cancelAction)
                .disabled(!model.busy)
            Divider()
            Button(selectionState.isInspectorVisible ? "隐藏检查器" : "显示检查器",
                   systemImage: "sidebar.right") {
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
            header
            Divider().overlay(FDTheme.hairlineColor)
            HSplitView {
                resultsPane
                    .frame(minWidth: 620, idealWidth: 780)
                if selectionState.isInspectorVisible {
                    FileInspectorView(result: model.selectedResult,
                                      state: inspector,
                                      path: singleSelectedPath,
                                      actions: actions,
                                      onClose: selectionState.toggleInspector)
                        .frame(minWidth: 252, idealWidth: 292, maxWidth: 336)
                }
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
        }
        .frame(minWidth: 960, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
        .background { FDAuroraBackground() }
        .tint(FDTheme.primary)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    selectionState.toggleInspector()
                } label: {
                    Image(systemName: selectionState.isInspectorVisible ? "sidebar.right" : "sidebar.left")
                }
                .help(selectionState.isInspectorVisible ? "隐藏检查器" : "显示检查器")
                .accessibilityLabel(selectionState.isInspectorVisible ? "隐藏检查器" : "显示检查器")
                .tint(FDTheme.primary)
            }
        }
        .task {
            actions.onFileMutation = model.fileDidChange
            await model.runSmokeIfRequested()
        }
        .task(id: InspectorRequestID(snapshot: model.inspectorRefreshID,
                                     paths: selectionState.selectedPaths,
                                     primary: selectionState.selectedPath)) {
            actions.updatePreview(path: selectionState.selectedPaths.count == 1 ? selectionState.selectedPath : nil)
            await inspector.select(paths: selectionState.selectedPaths, primary: selectionState.selectedPath)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FDBrandMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fsearch")
                        .font(.system(size: 19, weight: .semibold))
                    Text(model.isEngineMode ? "本机文件搜索" : "样本验证 · 仅受控样本")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)

                IndexStatusSummary(state: model.permissionStatus)

                Button {
                    showsIndexDetails = true
                } label: {
                    Label("权限与索引", systemImage: "lock.shield")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(FDSecondaryButtonStyle())
                .accessibilityIdentifier("permission-index-details")
                .popover(isPresented: $showsIndexDetails) {
                    PermissionStatusView(state: model.permissionStatus,
                                         engineVersion: model.engineVersion,
                                         onRecheck: model.recheckPermissions)
                }

                Button {
                    model.showsContentSearch = true
                } label: {
                    Label("文本内容搜索", systemImage: "text.magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(FDSecondaryButtonStyle())
                .disabled(!model.canSearchContent)
                .help(model.canSearchContent ? "在文件正文中搜索文本" : "样本名称模式不支持正文搜索")
                .accessibilityIdentifier("content-search")
            }

            HStack(spacing: 10) {
                SearchQueryField(
                    symbol: "magnifyingglass",
                    tint: FDTheme.slate,
                    onClear: model.configuration.query.isEmpty
                        ? nil : { model.configuration.query = "" }
                ) {
                    SearchQueryEditor(
                        text: $model.configuration.query,
                        focusRequest: model.focusRequest,
                        placeholder: "输入文件名或名称片段…",
                        onSubmit: model.submit
                    )
                }

                if model.busy {
                    Button {
                        model.cancel()
                    } label: {
                        Label("取消", systemImage: "xmark")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(FDSecondaryButtonStyle())
                    .help("取消当前查询")
                }

                SearchSubmitButton(title: "查询文件名",
                                   width: SearchControlsLayout.actionWidth,
                                   action: model.submit)
                    .help("执行文件名搜索")
                    .accessibilityIdentifier("submit-search")
            }

            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("仅搜索文件名，不搜索正文。Return 查询；Shift+Return 输入文件名中的换行。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("name-search-explanation")

            controlBar

            if model.permissionStatus.showOnboarding {
                PermissionOnboardingBanner(state: model.permissionStatus)
            }
            if let message = model.applicationMessage {
                FDNoticeBanner(text: message, symbol: "exclamationmark.circle.fill", tint: FDTheme.clay)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(FDHeaderBackground(accent: FDTheme.slate))
    }

    private var controlBar: some View {
        HStack(spacing: 9) {
            SearchScopeMenu(configuration: $model.configuration)

            controlDivider

            FDSegmentedPicker(
                options: matchModeOptions,
                selection: $model.configuration.nameMode,
                accessibilityLabel: "名称匹配方式"
            )
            .accessibilityIdentifier("name-mode")

            controlDivider

            SearchHiddenToggle(configuration: $model.configuration)

            Spacer(minLength: 8)

            SearchFiltersView(configuration: $model.configuration)
        }
    }

    private var controlDivider: some View {
        Rectangle()
            .fill(FDTheme.hairlineColor)
            .frame(width: 1, height: 17)
    }

    private var matchModeOptions: [FDSegmentedOption<NameMatchMode>] {
        [
            .init(value: .contains, title: "包含", symbol: "text.magnifyingglass", tint: FDTheme.slate),
            .init(value: .fuzzy, title: "模糊", symbol: "shuffle", tint: FDTheme.slate),
            .init(value: .prefix, title: "前缀", symbol: "arrow.right.to.line", tint: FDTheme.slate),
            .init(value: .suffix, title: "后缀", symbol: "arrow.left.to.line", tint: FDTheme.slate),
            .init(value: .wholeName, title: "完整", symbol: "equal.circle", tint: FDTheme.slate)
        ]
    }

    // MARK: Results

    private var resultsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            resultsHeader
            if let message = model.selectionMessage {
                FDNoticeBanner(text: message,
                               symbol: "exclamationmark.circle.fill",
                               tint: FDTheme.ochre)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            ZStack {
                ResultsTableView(
                    results: model.results,
                    selectionState: selectionState,
                    sort: model.sort,
                    onSort: model.sortBy,
                    actions: actions
                )
                .frame(minHeight: 250, maxHeight: .infinity)

                if model.results.isEmpty {
                    resultsPlaceholder
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FDTheme.surfaceFill)
                        .allowsHitTesting(false)
                }
            }
            Divider().overlay(FDTheme.hairlineColor)
            resultsFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FDTheme.surfaceFill)
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(FDTheme.slate)
                    .font(.system(size: 12, weight: .medium))
                Text("搜索结果")
                    .font(.system(size: 12.5, weight: .semibold))
                if !model.results.isEmpty {
                    FDCountBadge(text: "\(model.results.count)", tint: FDTheme.slate)
                }
                Spacer(minLength: 8)
                sortChip
            }
            HStack(alignment: .top, spacing: 6) {
                if model.busy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(statusColor)
                        .padding(.top, 1)
                } else {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.top, 1)
                }
                Text(model.message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityLabel("搜索状态")
                    .accessibilityValue(model.message)
                    .accessibilityIdentifier("query-status")
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var resultsPlaceholder: some View {
        if model.busy {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(FDTheme.primary)
                Text(model.activity == .sorting ? "正在整理排序…" : "正在搜索…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        } else {
            switch model.statusKind {
            case .error:
                FDEmptyState(symbol: "exclamationmark.triangle.fill",
                             title: "查询失败",
                             message: "修正条件后再试一次；旧结果不代表当前筛选。",
                             tint: FDTheme.clay)
            case .noMatch:
                FDEmptyState(symbol: "magnifyingglass",
                             title: "没有找到匹配文件",
                             message: "试试缩短关键词、切换匹配方式，或放宽属性筛选。",
                             tint: FDTheme.ochre,
                             hints: [("Return", "重新查询"), ("⌘F", "聚焦搜索")])
            case .cancelled:
                FDEmptyState(symbol: "pause.circle",
                             title: "查询已取消",
                             message: "可以调整关键词后重新查询。",
                             tint: FDTheme.stone)
            default:
                FDEmptyState(symbol: "doc.text.magnifyingglass",
                             title: "从一次搜索开始",
                             message: "输入文件名后按 Return，结果会出现在这里。",
                             tint: FDTheme.primary,
                             hints: [("⌘F", "聚焦搜索"), ("⌘R", "刷新")])
            }
        }
    }

    private var sortChip: some View {
        HStack(spacing: 5) {
            Image(systemName: model.sort == .relevance ? "text.magnifyingglass" : "arrow.up.arrow.down")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(FDTheme.ochre)
            Text(model.sortTitle)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
            Image(systemName: sortDirectionSymbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(FDTheme.softFillColor.opacity(0.65)))
        .help("点击结果列标题可切换排序")
        .accessibilityIdentifier("current-sort")
    }

    private var sortDirectionSymbol: String {
        switch model.sort {
        case .ascending, .sizeAscending, .modifiedAscending: "arrow.up"
        case .relevance: "text.magnifyingglass"
        default: "arrow.down"
        }
    }

    private var resultsFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                PathNavigationView(path: singleSelectedPath, actions: actions)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SearchFileActionIconRow(path: singleSelectedPath, actions: actions, size: 24)

                Rectangle()
                    .fill(FDTheme.hairlineColor)
                    .frame(width: 1, height: 16)

                Button {
                    model.loadMore()
                } label: {
                    Label("载入更多", systemImage: "arrow.down.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .disabled(model.nextCursor == nil || model.busy)
                .accessibilityIdentifier("load-more")
                .buttonStyle(FDSecondaryButtonStyle())
            }
            if let pagination = model.paginationMessage {
                Text(pagination)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, footerTextLeadingInset)
            }
            if let message = actions.message {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, footerTextLeadingInset)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 62, alignment: .top)
        .background(FDHeaderBackground())
    }

    private var footerTextLeadingInset: CGFloat {
        SearchFooterLayout.textLeadingInset(alignsWithPathContent: singleSelectedPath != nil)
    }

    private var singleSelectedPath: String? {
        selectionState.selectedPaths.count == 1 ? selectionState.selectedPath : nil
    }

    private var statusColor: Color {
        switch model.statusKind {
        case .error:
            return FDTheme.clay
        case .partial, .sorting:
            return FDTheme.ochre
        case .querying:
            return FDTheme.slate
        case .complete:
            return FDTheme.olive
        case .prompt, .cancelled, .noMatch:
            return .secondary
        }
    }

    private var statusSymbol: String {
        switch model.statusKind {
        case .error: "exclamationmark.triangle.fill"
        case .partial: "circle.lefthalf.filled"
        case .sorting: "arrow.up.arrow.down"
        case .querying: "magnifyingglass"
        case .complete: "checkmark.circle.fill"
        case .noMatch: "questionmark.circle"
        case .cancelled: "pause.circle"
        case .prompt: "info.circle"
        }
    }
}

private struct SearchQueryEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NameQueryTextView()
        textView.onSubmit = onSubmit
        textView.placeholder = placeholder
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.allowsUndo = true
        let font = NSFont.preferredFont(forTextStyle: .body)
        textView.font = font
        textView.insertionPointColor = FDTheme.primaryNSColor
        textView.selectedTextAttributes = [.backgroundColor: FDTheme.selectionNSColor]
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: font) ?? 16
        textView.textContainerInset = NSSize(width: 4, height: (SearchControlsLayout.queryHeight - lineHeight) / 2)
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
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NameQueryTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.placeholder = placeholder
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
    var placeholder = ""

    private var isShowingPlaceholder: Bool {
        string.isEmpty && window?.firstResponder !== self
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isShowingPlaceholder, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let size = (placeholder as NSString).size(withAttributes: attributes)
        let linePadding = textContainer?.lineFragmentPadding ?? 0
        let rect = NSRect(x: textContainerInset.width + linePadding,
                          y: max(0, (bounds.height - size.height) / 2),
                          width: max(0, bounds.width - textContainerInset.width * 2 - linePadding * 2),
                          height: size.height)
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

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

final class FDTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        FDTheme.selectionNSColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
}

final class FDTableHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        FDTheme.headerNSColor.setFill()
        cellFrame.fill()
        FDTheme.hairlineNSColor.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 0.5, width: cellFrame.width, height: 0.5).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
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
        table.style = .inset
        table.backgroundColor = FDTheme.surfaceNSColor
        table.rowHeight = 32
        table.intercellSpacing = NSSize(width: 0, height: 3)
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
        scrollView.drawsBackground = true
        scrollView.backgroundColor = FDTheme.surfaceNSColor
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
        let resultsChanged = coordinator.renderedResults != results
        coordinator.isUpdatingSelection = true
        coordinator.parent = self
        if resultsChanged { table.reloadData() }

        let desiredDescriptors = sortDescriptors
        if table.sortDescriptors.first?.key != desiredDescriptors.first?.key
            || table.sortDescriptors.first?.ascending != desiredDescriptors.first?.ascending {
            table.sortDescriptors = desiredDescriptors
        }
        let rows = IndexSet(results.indices.filter { selectionState.selectedPaths.contains(results[$0].path) })
        if resultsChanged || selectionChanged { table.selectRowIndexes(rows, byExtendingSelection: false) }
        if resultsChanged, let anchor, let row = results.firstIndex(where: { $0.path == anchor }) {
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
        coordinator.renderedResults = results
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
        let header = FDTableHeaderCell(textCell: title)
        header.alignment = .left
        header.font = .systemFont(ofSize: 10.5, weight: .semibold)
        header.textColor = .secondaryLabelColor
        column.headerCell = header
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
        var renderedResults: [SearchResult]?

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
            _ = add(SearchFileAction.open.title, SearchFileAction.open.symbol, #selector(openSelection(_:)))
            _ = add(SearchFileAction.preview.title, SearchFileAction.preview.symbol, #selector(previewSelection(_:)))
            _ = add(SearchFileAction.reveal.title, SearchFileAction.reveal.symbol, #selector(revealSelection(_:)))
            _ = add(SearchFileAction.copy.title, SearchFileAction.copy.symbol, #selector(copySelection(_:)))
            menu.addItem(.separator())
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
            _ = add("显示简介", "info.circle", #selector(infoSelection(_:)))
            _ = add("重命名…", "pencil", #selector(renameSelection(_:)))
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

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            FDTableRowView()
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard row >= 0, row < parent.results.count, let tableColumn else { return nil }
            let result = parent.results[row]
            let isName = tableColumn.identifier.rawValue == "name"
            let identifier = NSUserInterfaceItemIdentifier(isName ? "result-name-cell" : "result-text-cell")
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
                textField.font = isName
                    ? .systemFont(ofSize: 12.5, weight: .medium)
                    : .systemFont(ofSize: 11.5)
                cell.addSubview(textField)
                cell.textField = textField

                if isName {
                    let imageView = NSImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    imageView.imageScaling = .scaleProportionallyDown
                    cell.addSubview(imageView)
                    cell.imageView = imageView
                    NSLayoutConstraint.activate([
                        imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
                        imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                        imageView.widthAnchor.constraint(equalToConstant: 17),
                        imageView.heightAnchor.constraint(equalToConstant: 17),
                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
                        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                    ])
                } else {
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
                        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                    ])
                }
            }

            switch tableColumn.identifier.rawValue {
            case "location":
                cell.textField?.stringValue = (result.path as NSString).deletingLastPathComponent
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
                cell.textField?.stringValue = (result.path as NSString).lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: result.path)
                icon.size = NSSize(width: 17, height: 17)
                cell.imageView?.image = icon
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
