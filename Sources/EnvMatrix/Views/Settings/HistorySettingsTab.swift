import SwiftUI
import AppKit

/// Settings › History: a timeline of what EnvMatrix changed, with rollback
/// for config writes that have a backup.
struct HistorySettingsTab: View {
    @ObservedObject private var log = OperationLog.shared
    @EnvironmentObject private var localization: LocalizationManager
    @State private var pendingRollback: OperationEntry?
    @State private var errorMessage: String?
    @State private var filter: OperationEntry.Category?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 8)
            if let errorMessage {
                StatusBanner(.error, errorMessage, onDismiss: { self.errorMessage = nil }, showsDiagnosticsLink: false)
            }
            if visibleEntries.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: L("history.empty.title"),
                    subtitle: L("history.empty.subtitle"),
                    compact: true
                )
            } else {
                list
            }
        }
        .padding()
        .alert(
            String(format: L("history.rollback.confirmTitle"), pendingRollback?.title ?? ""),
            isPresented: Binding(get: { pendingRollback != nil }, set: { if !$0 { pendingRollback = nil } }),
            presenting: pendingRollback
        ) { entry in
            Button(L("history.rollback"), role: .destructive) {
                pendingRollback = nil
                do {
                    try log.rollback(entry)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button(L("common.cancel"), role: .cancel) { pendingRollback = nil }
        } message: { entry in
            Text(String(format: L("history.rollback.confirmMessage"),
                        entry.backupPath ?? "", entry.targetPath ?? ""))
        }
    }

    private var visibleEntries: [OperationEntry] {
        guard let filter else { return log.entries }
        return log.entries.filter { $0.category == filter }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("history.title")).font(.headline)
                Text(L("history.subtitle")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $filter) {
                Text(L("history.filter.all")).tag(OperationEntry.Category?.none)
                ForEach(OperationEntry.Category.allCases, id: \.self) { cat in
                    Label(L("history.category.\(cat.rawValue)"), systemImage: cat.systemImage)
                        .tag(OperationEntry.Category?.some(cat))
                }
            }
            .labelsHidden()
            .frame(width: 160)
            Button(role: .destructive) {
                log.clear()
            } label: {
                Label(L("history.clear"), systemImage: "trash")
            }
            .disabled(log.entries.isEmpty)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(groupedByDay, id: \.day) { group in
                    Text(group.day)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    ForEach(group.entries) { entry in
                        row(entry)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var groupedByDay: [(day: String, entries: [OperationEntry])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        var order: [String] = []
        var buckets: [String: [OperationEntry]] = [:]
        for entry in visibleEntries {
            let key = formatter.string(from: entry.date)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private func row(_ entry: OperationEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.succeeded ? entry.category.systemImage : "xmark.octagon.fill")
                .foregroundStyle(entry.succeeded ? Color.accentColor : Color.red)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title).font(.body)
                    if entry.rolledBackAt != nil {
                        Text(L("history.rolledBack"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.chipFill, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            if let backup = entry.backupPath, FileManager.default.fileExists(atPath: backup) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backup)])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(L("history.revealBackup"))
            }
            if log.canRollback(entry) {
                Button(L("history.rollback")) { pendingRollback = entry }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
