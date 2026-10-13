import Combine
import FsearchService

struct SearchConfiguration: Equatable {
    var query = "report"
    var nameMode: NameMatchMode = .contains
    var sortPreference: NameSort?

    var sort: NameSort {
        get { sortPreference ?? nameMode.defaultSort }
        set { sortPreference = newValue }
    }

    var hasQueryInput: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
final class SearchSelectionState: ObservableObject {
    @Published var selectedPath: String?
    @Published var isInspectorVisible = true

    func toggleInspector() {
        isInspectorVisible.toggle()
    }
}
