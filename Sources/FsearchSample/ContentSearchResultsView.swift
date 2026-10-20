import AppKit
import FsearchService
import SwiftUI

struct ContentSearchResultsView: View {
    let files: [ContentFile]
    @Binding var selection: String?
    @ObservedObject var actions: FileActionState

    var body: some View {
        HStack(spacing: 0) {
            fileList
                .frame(width: 284)
            Rectangle()
                .fill(FDTheme.hairlineColor)
                .frame(width: 1)
            matchDetails
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FDTheme.surfaceFill)
        .tint(FDTheme.primary)
        .accessibilityIdentifier("content-results")
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                FDSectionLabel(title: "匹配文件", symbol: "doc.on.doc", tint: FDTheme.plum)
                Spacer()
                FDCountBadge(text: "\(files.count)", tint: FDTheme.plum)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().overlay(FDTheme.hairlineColor)

            List(selection: $selection) {
                ForEach(files) { file in
                    row(for: file)
                        .tag(file.path)
                        .listRowInsets(EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 7))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            SearchFileActionButtons(path: file.path, actions: actions)
                        }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(FDTheme.canvas)
            .accessibilityLabel("匹配文件")
            .accessibilityIdentifier("content-file-list")
            .overlay {
                if files.isEmpty {
                    VStack(spacing: 8) {
                        FDIconTile(symbol: "text.magnifyingglass", tint: FDTheme.plum, size: 38)
                        Text("暂无匹配文件")
                            .font(.system(size: 12, weight: .semibold))
                        Text("输入正文内容后按 Return")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .background(FDTheme.canvas)
    }

    private func row(for file: ContentFile) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Rectangle()
                .fill(selection == file.path ? FDTheme.plum : Color.clear)
                .frame(width: 2, height: 52)

            Image(nsImage: fileIcon(file.path))
                .resizable()
                .frame(width: 19, height: 19)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    FDCountBadge(text: "\(file.lines.count) 行", tint: FDTheme.plum)
                }
                Text((file.path as NSString).deletingLastPathComponent)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let line = file.lines.first {
                    Text(AttributedString(highlightedContent(line)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(height: 60, alignment: .top)
        .help(file.path)
    }

    @ViewBuilder
    private var matchDetails: some View {
        if let file = files.first(where: { $0.path == selection }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(nsImage: fileIcon(file.path))
                        .resizable()
                        .frame(width: 27, height: 27)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(URL(fileURLWithPath: file.path).lastPathComponent)
                            .font(.system(size: 12.5, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text((file.path as NSString).deletingLastPathComponent)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    FDCountBadge(text: "\(file.lines.count) 处匹配", tint: FDTheme.plum)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .help(file.path)
                Divider().overlay(FDTheme.hairlineColor)
                ContentMatchesView(file: file)
                    .id(file.path)
            }
        } else {
            VStack(spacing: 9) {
                FDIconTile(symbol: "text.alignleft", tint: FDTheme.plum, size: 46)
                Text("选择文件查看内容匹配")
                    .font(.system(size: 13, weight: .semibold))
                Text("左侧选择文件，右侧独立滚动展示行号与高亮片段。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fileIcon(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 19, height: 19)
        return icon
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
        textView.backgroundColor = FDTheme.surfaceNSColor
        textView.setAccessibilityLabel("文件内容匹配")
        textView.setAccessibilityIdentifier("content-match-details")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        let digits = String(file.lines.map(\.line).max() ?? 1).count
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 10
        paragraph.headIndent = CGFloat(digits + 2) * ("0" as NSString).size(withAttributes: [.font: font]).width
        let content = NSMutableAttributedString(string: "")
        for line in file.lines {
            let number = String(line.line)
            let prefix = String(repeating: " ", count: max(0, digits - number.count)) + number + "  "
            content.append(NSAttributedString(string: prefix, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: font
            ]))
            content.append(highlightedContent(line, foreground: .labelColor))
            content.append(NSAttributedString(string: "\n"))
        }
        content.addAttributes([.font: font, .paragraphStyle: paragraph],
                              range: NSRange(location: 0, length: content.length))
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
        text.addAttributes([
            .backgroundColor: FDTheme.highlightNSColor,
            .foregroundColor: NSColor.labelColor
        ], range: NSRange(range, in: line.text))
    }
    return text
}
