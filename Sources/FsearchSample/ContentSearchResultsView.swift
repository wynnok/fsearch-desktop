import AppKit
import FsearchService
import SwiftUI

struct ContentSearchResultsView: View {
    let files: [ContentFile]
    @Binding var selection: String?
    @ObservedObject var actions: FileActionState

    var body: some View {
        HSplitView {
            fileList
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 320)
            matchDetails
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("content-results")
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("匹配文件").font(.headline)
                Spacer()
                Text("已载入 \(files.count) 个").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Divider()
            List(selection: $selection) {
                ForEach(files) { file in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            Text("\(file.lines.count) 行")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                        }
                        Text((file.path as NSString).deletingLastPathComponent)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        if let line = file.lines.first {
                            Text(AttributedString(highlightedContent(line)))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .frame(height: 64)
                    .help(file.path)
                    .tag(file.path)
                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                    .contextMenu {
                        SearchFileActionButtons(path: file.path, actions: actions)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .accessibilityLabel("匹配文件")
            .accessibilityIdentifier("content-file-list")
            .overlay {
                if files.isEmpty {
                    Text("暂无匹配文件").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var matchDetails: some View {
        if let file = files.first(where: { $0.path == selection }) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("内容匹配").font(.headline)
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text("已载入 \(file.lines.count) 个匹配行 · 可选择并复制文本")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(12)
                .help(file.path)
                Divider()
                ContentMatchesView(file: file)
                    .id(file.path)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "text.alignleft").font(.system(size: 28))
                Text("选择文件查看内容匹配").font(.headline)
                Text("选择左侧文件，查看行号和高亮片段。")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ContentMatchesView: NSViewRepresentable {
    let file: ContentFile

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = .textBackgroundColor
        textView.setAccessibilityLabel("文件内容匹配")
        textView.setAccessibilityIdentifier("content-match-details")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let digits = String(file.lines.map(\.line).max() ?? 1).count
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 10
        paragraph.headIndent = CGFloat(digits + 2) * ("0" as NSString).size(withAttributes: [.font: font]).width
        let content = NSMutableAttributedString(string: "")
        for line in file.lines {
            let number = String(line.line)
            let prefix = String(repeating: " ", count: max(0, digits - number.count)) + number + "  "
            content.append(NSAttributedString(string: prefix, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            content.append(highlightedContent(line, foreground: .labelColor))
            content.append(NSAttributedString(string: "\n"))
        }
        content.addAttributes([.font: font, .paragraphStyle: paragraph], range: NSRange(location: 0, length: content.length))
        if textView.textStorage?.isEqual(to: content) == false {
            textView.textStorage?.setAttributedString(content)
        }
    }
}

private func highlightedContent(_ line: ContentLine, foreground: NSColor? = nil) -> NSAttributedString {
    let text = NSMutableAttributedString(string: line.text)
    if let foreground {
        text.addAttribute(.foregroundColor, value: foreground, range: NSRange(location: 0, length: text.length))
    }
    for range in line.nativeRanges {
        text.addAttributes([.backgroundColor: NSColor.systemYellow, .foregroundColor: NSColor.black],
                           range: NSRange(range, in: line.text))
    }
    return text
}
