import Foundation

public extension ContentLine {
    var nativeRanges: [Range<String.Index>] {
        Self.nativeRanges(for: ranges, in: text)
    }

    static func nativeRanges(for byteRanges: [[Int]], in text: String) -> [Range<String.Index>] {
        let byteCount = text.utf8.count
        var result: [Range<String.Index>] = []

        for pair in byteRanges {
            guard pair.count == 2 else { continue }
            let lower = max(0, min(pair[0], byteCount))
            let upper = max(lower, min(pair[1], byteCount))
            guard lower < upper,
                  let start = lowerIndex(atUTF8Offset: lower, in: text),
                  let end = upperIndex(atUTF8Offset: upper, in: text),
                  start < end else { continue }

            if let last = result.last, last.upperBound >= start {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, end)
            } else {
                result.append(start..<end)
            }
        }
        return result
    }

    private static func lowerIndex(atUTF8Offset offset: Int, in text: String) -> String.Index? {
        let utf8 = text.utf8
        var index = utf8.index(utf8.startIndex, offsetBy: offset)
        while index > utf8.startIndex {
            if let stringIndex = index.samePosition(in: text) {
                return stringIndex
            }
            index = utf8.index(before: index)
        }
        return utf8.startIndex.samePosition(in: text)
    }

    private static func upperIndex(atUTF8Offset offset: Int, in text: String) -> String.Index? {
        let utf8 = text.utf8
        var index = utf8.index(utf8.startIndex, offsetBy: offset)
        while index < utf8.endIndex {
            if let stringIndex = index.samePosition(in: text) {
                return stringIndex
            }
            index = utf8.index(after: index)
        }
        return text.endIndex
    }
}
