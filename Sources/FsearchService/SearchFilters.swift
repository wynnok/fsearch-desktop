import Foundation

public enum SearchItemKind: UInt8, Codable, Sendable, CaseIterable {
    case file = 0
    case directory = 1
}

public struct NameSearchFilters: Codable, Sendable, Equatable {
    public var kind: SearchItemKind?
    public var extensions: [String]
    public var minimumSize: UInt64?
    public var maximumSize: UInt64?
    public var modifiedAfter: UInt32?
    public var modifiedBefore: UInt32?

    public init(kind: SearchItemKind? = nil, extensions: [String] = [],
                minimumSize: UInt64? = nil, maximumSize: UInt64? = nil,
                modifiedAfter: UInt32? = nil, modifiedBefore: UInt32? = nil) {
        self.kind = kind
        self.extensions = extensions
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
    }

    public var isEffective: Bool {
        kind != nil || !extensions.isEmpty || minimumSize != nil || maximumSize != nil
            || modifiedAfter != nil || modifiedBefore != nil
    }

    public func validate() throws {
        if let minimumSize, let maximumSize, minimumSize > maximumSize {
            throw FsearchError.query("索引大小的最小值不能大于最大值")
        }
        if let modifiedAfter, let modifiedBefore, modifiedAfter > modifiedBefore {
            throw FsearchError.query("修改时间的开始日期不能晚于结束日期")
        }
        if extensions.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty
                || $0.contains("/") || $0.utf8.contains(0)
        }) {
            throw FsearchError.query("扩展名不能包含路径分隔符或为空")
        }
    }
}
