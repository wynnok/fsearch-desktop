import Combine
import Foundation
import FsearchService

// Scope restricts a query to existing index coverage; it never starts a new scan.
enum SearchScope: Equatable {
    case allIndexed
    case home
    case folder(String)

    var path: String? {
        switch self {
        case .allIndexed: nil
        case .home: FileManager.default.homeDirectoryForCurrentUser.path
        case .folder(let path): path
        }
    }
}

struct SearchConfiguration: Equatable {
    var query = "report"
    var nameMode: NameMatchMode = .contains
    var sortPreference: NameSort?
    var scope: SearchScope = .allIndexed
    var showsHidden = true
    var filters = NameSearchFilters()

    var sort: NameSort {
        get { sortPreference ?? nameMode.defaultSort }
        set { sortPreference = newValue }
    }

    var hasQueryInput: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasEffectiveQuery: Bool {
        hasQueryInput || filters.isEffective || scope != .allIndexed
    }

    func request() throws -> NameSearchRequest {
        try filters.validate()
        return NameSearchRequest(query: query, mode: nameMode, scopePath: scope.path,
                                 showsHidden: showsHidden, filters: filters)
    }

    mutating func clearFilters() {
        filters = NameSearchFilters()
    }
}

@MainActor
final class SearchSelectionState: ObservableObject {
    @Published private(set) var selectedPaths: Set<String> = []
    @Published var selectedPath: String? {
        didSet {
            guard !isChangingSelection else { return }
            selectedPaths = selectedPath.map { [$0] } ?? []
        }
    }
    private var isChangingSelection = false

    func select(paths: Set<String>, primary: String?) {
        isChangingSelection = true
        selectedPaths = paths
        selectedPath = primary.flatMap { paths.contains($0) ? $0 : nil } ?? paths.sorted().first
        isChangingSelection = false
    }
    @Published var isInspectorVisible = true

    func toggleInspector() {
        isInspectorVisible.toggle()
    }
}
