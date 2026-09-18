import SwiftUI

/// Confirmation + result sheet for the one-click mirror presets.
struct MirrorPresetSheet: View {
    let profile: MirrorPresetProfile
    let onDone: () -> Void

    @EnvironmentObject private var localization: LocalizationManager
    @State private var isApplying = false
    @State private var results: [MirrorPresetResult]? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: profile == .chinaMainland ? "bolt.horizontal.circle.fill" : "globe")
                    .font(.title)
                    .foregroundStyle(profile == .chinaMainland ? Color.orange : Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("mirrorPreset.\(profile.rawValue).title")).font(.title2.bold())
                    Text(L("mirrorPreset.\(profile.rawValue).subtitle")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            if let results {
                resultList(results)
            } else {
                previewList
            }

            Divider()

            HStack {
                if results == nil {
                    Text(L("mirrorPreset.backupNote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if results == nil {
                    Button(L("common.cancel"), action: onDone)
                        .keyboardShortcut(.cancelAction)
                    Button {
                        Task { await apply() }
                    } label: {
                        if isApplying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L("mirrorPreset.apply"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("mirrorPreset.done"), action: onDone)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private var previewList: some View {
        let v = profile.values
        let rows: [(MirrorPresetResult.Ecosystem, String)] = [
            (.npm, v.npmRegistry), (.pnpm, v.pnpmRegistry), (.pip, v.pipIndex), (.uv, v.uvIndex),
            (.go, v.goProxy), (.cargo, v.cargoRegistry), (.gem, v.gemSource),
            (.composer, v.composerRepository), (.nuget, v.nugetSource.url),
            (.maven, v.mavenMirror?.url ?? L("mirrorPreset.maven.remove")),
            (.nodeDownload, v.nodeDownload), (.goDownload, v.goDownload)
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { eco, value in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(label(eco))
                            .font(.callout.weight(.medium))
                            .frame(width: 130, alignment: .leading)
                        Text(value)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func resultList(_ results: [MirrorPresetResult]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(results) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        icon(for: r.status)
                        Text(label(r.ecosystem))
                            .font(.callout.weight(.medium))
                            .frame(width: 130, alignment: .leading)
                        Text(detail(for: r.status))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func icon(for status: MirrorPresetResult.Status) -> some View {
        switch status {
        case .applied: return Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
        case .skipped: return Image(systemName: "minus.circle").foregroundStyle(Color.secondary)
        case .failed: return Image(systemName: "xmark.octagon.fill").foregroundStyle(Color.red)
        }
    }

    private func detail(for status: MirrorPresetResult.Status) -> String {
        switch status {
        case .applied(let v): return v
        case .skipped(let why): return "\(L("mirrorPreset.skipped")) · \(why)"
        case .failed(let err): return "\(L("mirrorPreset.failed")) · \(err)"
        }
    }

    private func label(_ eco: MirrorPresetResult.Ecosystem) -> String {
        L("mirrorPreset.eco.\(eco.rawValue)")
    }

    private func apply() async {
        isApplying = true
        let applier = MirrorPresetApplier()
        let outcome = await applier.apply(profile)
        results = outcome
        isApplying = false
        let applied = outcome.filter { $0.isApplied }.count
        OperationLog.shared.record(
            .registry,
            title: String(format: L("history.op.mirrorPreset"), L("mirrorPreset.\(profile.rawValue).title")),
            detail: String(format: L("mirrorPreset.summary"), applied, outcome.count)
        )
        SystemNotifier.shared.notify(
            title: L("mirrorPreset.\(profile.rawValue).title"),
            body: String(format: L("mirrorPreset.summary"), applied, outcome.count)
        )
    }
}
