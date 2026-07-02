// Markdown.swift — lightweight block-level Markdown renderer, no dependencies.
// Handles the subset that appears in Claude Code reviews: ATX headings,
// paragraphs, unordered/ordered lists, fenced code blocks, blockquotes, and
// horizontal rules. Inline formatting (bold / italic / code / links) is
// delegated to AttributedString's inline-only markdown parser within each block.
//
// (Apple's swift-markdown would be more complete, but the app builds with plain
// swiftc and no Package.swift — this keeps that build with zero deps.)

import SwiftUI

struct MarkdownView: View {
    private let blocks: [MDBlock]
    init(_ text: String) { self.blocks = parseMarkdown(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(headingFont(level)).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.ink2.opacity(0.12)))

        case .list(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.marker)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(Theme.ink2)
                        Text(inlineMarkdown(item.text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(item.indent) * 16)
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.ink2.opacity(0.4)).frame(width: 3)
                Text(inlineMarkdown(text))
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .title2
        case 2:  return .title3
        case 3:  return .headline
        default: return .subheadline
        }
    }
}

/// Inline-only markdown -> AttributedString (bold/italic/code/links). Block
/// markers are already stripped by the block parser; never throws out the text.
func inlineMarkdown(_ s: String) -> AttributedString {
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
}

// MARK: - Block model + parser

enum MDBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case codeBlock(String)
    case list([MDListItem])
    case quote(String)
    case rule
}

struct MDListItem {
    let marker: String
    let text: String
    let indent: Int
}

func parseMarkdown(_ input: String) -> [MDBlock] {
    var blocks: [MDBlock] = []
    let lines = input.components(separatedBy: "\n")
    var i = 0

    var paragraph: [String] = []
    func flushParagraph() {
        if !paragraph.isEmpty {
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
    }

    func isFence(_ l: String) -> Bool {
        let t = l.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("```") || t.hasPrefix("~~~")
    }

    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if isFence(line) {                                  // fenced code block
            flushParagraph()
            i += 1
            var code: [String] = []
            while i < lines.count && !isFence(lines[i]) { code.append(lines[i]); i += 1 }
            i += 1                                          // consume closing fence
            blocks.append(.codeBlock(code.joined(separator: "\n")))
            continue
        }

        if trimmed.isEmpty { flushParagraph(); i += 1; continue }

        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            flushParagraph(); blocks.append(.rule); i += 1; continue
        }

        if let h = parseHeading(trimmed) {
            flushParagraph(); blocks.append(.heading(level: h.0, text: h.1)); i += 1; continue
        }

        if listMarker(line) != nil {                        // consecutive list lines
            flushParagraph()
            var items: [MDListItem] = []
            while i < lines.count, let m = listMarker(lines[i]) { items.append(m); i += 1 }
            blocks.append(.list(items))
            continue
        }

        if trimmed.hasPrefix(">") {                         // blockquote
            flushParagraph()
            var quote: [String] = []
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                let q = lines[i].trimmingCharacters(in: .whitespaces)
                quote.append(String(q.dropFirst()).trimmingCharacters(in: .whitespaces))
                i += 1
            }
            blocks.append(.quote(quote.joined(separator: " ")))
            continue
        }

        paragraph.append(trimmed)                           // plain paragraph text
        i += 1
    }
    flushParagraph()
    return blocks
}

private func parseHeading(_ trimmed: String) -> (Int, String)? {
    guard trimmed.hasPrefix("#") else { return nil }
    var level = 0
    for ch in trimmed { if ch == "#" { level += 1 } else { break } }
    guard (1...6).contains(level) else { return nil }
    let rest = trimmed.dropFirst(level)
    guard rest.hasPrefix(" ") else { return nil }           // "#tag" is not a heading
    return (level, rest.trimmingCharacters(in: .whitespaces))
}

/// A list item if the line is a bullet or ordered item, else nil.
private func listMarker(_ line: String) -> MDListItem? {
    let indent = line.prefix { $0 == " " }.count / 2
    let t = line.trimmingCharacters(in: .whitespaces)

    for bullet in ["- ", "* ", "+ "] where t.hasPrefix(bullet) {
        return MDListItem(marker: "•", text: String(t.dropFirst(2)), indent: indent)
    }

    var digits = ""
    for ch in t { if ch.isNumber { digits.append(ch) } else { break } }
    if !digits.isEmpty {
        let after = t.dropFirst(digits.count)
        if after.hasPrefix(". ") || after.hasPrefix(") ") {
            return MDListItem(marker: digits + ".", text: String(after.dropFirst(2)), indent: indent)
        }
    }
    return nil
}
