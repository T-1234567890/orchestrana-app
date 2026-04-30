import SwiftUI

struct TaskMarkdownView: View {
    let markdown: String
    var lineLimit: Int?

    init(markdown: String, lineLimit: Int? = nil) {
        self.markdown = markdown
        self.lineLimit = lineLimit
    }

    var body: some View {
        if let rendered = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(rendered)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
        } else {
            Text(markdown)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
        }
    }
}
