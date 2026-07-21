import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings tab that generates a Markdown snapshot of the local package
/// managers and lets the user preview / copy / save it to disk.
struct DiagnosticsSettingsTab: View {
    @State private var report: String = ""
    @State private var isGenerating: Bool = false
    @State private var showCopied: Bool = false
    @State private var saveError: String?

    private let service = DiagnosticReportService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            preview
            footer
        }
        .padding()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("settings.diagnostics.title"))
                    .font(.headline)
                Text(L("settings.diagnostics.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("settings.diagnostics.generate"), systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
        }
    }

    @ViewBuilder
    private var preview: some View {
        ScrollView {
            Text(report.isEmpty ? L("settings.diagnostics.emptyHint") : report)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(report.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack {
            if showCopied {
                Label(L("settings.diagnostics.copied"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .transition(.opacity)
            }
            if let err = saveError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Spacer()
            Button {
                copyToClipboard()
            } label: {
                Label(L("settings.diagnostics.copy"), systemImage: "doc.on.doc")
            }
            .disabled(report.isEmpty)

            Button {
                saveToFile()
            } label: {
                Label(L("settings.diagnostics.save"), systemImage: "square.and.arrow.down")
            }
            .disabled(report.isEmpty)
        }
    }

    // MARK: - Actions

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        let text = await service.makeReport()
        await MainActor.run {
            self.report = text
            self.saveError = nil
        }
    }

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "envmatrix-diagnostics-\(stamp).md"
        panel.title = L("settings.diagnostics.save")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                saveError = nil
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
