import SwiftUI
import AppKit

struct ContainerInspectSheet: View {
    let title: String
    let content: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                Button(action: copyContent) {
                    Label(L("container.inspect.copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                Button(action: onClose) {
                    Text(L("container.inspect.close"))
                }
                .keyboardShortcut(.cancelAction)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 400)
    }

    private func copyContent() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }
}
