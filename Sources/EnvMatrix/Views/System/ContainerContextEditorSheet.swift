import SwiftUI

public enum DockerEditorState: Identifiable {
    case create
    case edit(DockerContext)

    public var id: String {
        switch self {
        case .create: return "create"
        case .edit(let c): return "edit-\(c.name)"
        }
    }
}

public enum PodmanEditorState: Identifiable {
    case create
    case edit(PodmanConnection)

    public var id: String {
        switch self {
        case .create: return "create"
        case .edit(let c): return "edit-\(c.name)"
        }
    }
}

enum DockerEndpointScheme: String, CaseIterable, Hashable {
    case unix = "unix://"
    case tcp = "tcp://"
    case ssh = "ssh://"

    var label: String { rawValue }

    static func split(_ endpoint: String) -> (DockerEndpointScheme, String) {
        for scheme in DockerEndpointScheme.allCases {
            if endpoint.hasPrefix(scheme.rawValue) {
                return (scheme, String(endpoint.dropFirst(scheme.rawValue.count)))
            }
        }
        return (.unix, endpoint)
    }
}

enum PodmanURIScheme: String, CaseIterable, Hashable {
    case unix = "unix://"
    case ssh = "ssh://"
    case custom = ""

    var label: String {
        switch self {
        case .unix: return "unix://"
        case .ssh: return "ssh://"
        case .custom: return "custom"
        }
    }

    static func split(_ uri: String) -> (PodmanURIScheme, String) {
        if uri.hasPrefix(PodmanURIScheme.unix.rawValue) {
            return (.unix, String(uri.dropFirst(PodmanURIScheme.unix.rawValue.count)))
        }
        if uri.hasPrefix(PodmanURIScheme.ssh.rawValue) {
            return (.ssh, String(uri.dropFirst(PodmanURIScheme.ssh.rawValue.count)))
        }
        return (.custom, uri)
    }
}

/// Sheet form for creating or editing a Docker CLI context.
public struct DockerEditorSheet: View {
    @ObservedObject var viewModel: ContainerContextsViewModel
    let state: DockerEditorState
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var scheme: DockerEndpointScheme = .unix
    @State private var host: String = ""
    @State private var description: String = ""
    @State private var tlsExpanded: Bool = false
    @State private var caCert: String = ""
    @State private var clientCert: String = ""
    @State private var clientKey: String = ""
    @State private var skipTLSVerify: Bool = false

    public init(
        viewModel: ContainerContextsViewModel,
        state: DockerEditorState,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.state = state
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Form {
                Section {
                    TextField(L("container.editor.name"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isEditing)

                    HStack(spacing: 6) {
                        Picker(L("container.editor.endpoint"), selection: $scheme) {
                            ForEach(DockerEndpointScheme.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)

                        TextField(L("container.editor.host"), text: $host)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField(L("container.editor.description"), text: $description)
                        .textFieldStyle(.roundedBorder)
                }

                DisclosureGroup(L("container.editor.tls"), isExpanded: $tlsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L("container.editor.caCert"), text: $caCert)
                            .textFieldStyle(.roundedBorder)
                        TextField(L("container.editor.clientCert"), text: $clientCert)
                            .textFieldStyle(.roundedBorder)
                        TextField(L("container.editor.clientKey"), text: $clientKey)
                            .textFieldStyle(.roundedBorder)
                        Toggle(L("container.editor.skipTLSVerify"), isOn: $skipTLSVerify)
                    }
                    .padding(.top, 4)
                }
            }
            .formStyle(.grouped)

            if let msg = viewModel.dockerError {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            HStack {
                Spacer()
                Button(L("container.editor.cancel")) { onDismiss() }
                Button(L("container.editor.save")) {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { hydrate() }
    }

    private var isEditing: Bool {
        if case .edit = state { return true }
        return false
    }

    private var title: String {
        switch state {
        case .create: return L("container.docker.editor.addTitle")
        case .edit: return L("container.docker.editor.editTitle")
        }
    }

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }
        if !isEditing && trimmedHost.isEmpty { return false }
        return true
    }

    private func hydrate() {
        switch state {
        case .create:
            name = ""
            scheme = .unix
            host = ""
            description = ""
            tlsExpanded = false
            caCert = ""
            clientCert = ""
            clientKey = ""
            skipTLSVerify = false
        case .edit(let ctx):
            name = ctx.name
            let parts = DockerEndpointScheme.split(ctx.endpoint)
            scheme = parts.0
            host = parts.1
            description = ctx.description
            tlsExpanded = (ctx.tlsEnabled == true)
            caCert = ""
            clientCert = ""
            clientKey = ""
            skipTLSVerify = ctx.skipTLSVerify ?? false
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullHost = trimmedHost.isEmpty ? "" : "\(scheme.rawValue)\(trimmedHost)"
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let tls = makeTLS()

        switch state {
        case .create:
            await viewModel.createDockerContext(
                name: trimmedName,
                host: fullHost,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                tls: tls
            )
        case .edit:
            await viewModel.updateDockerContext(
                name: trimmedName,
                host: fullHost.isEmpty ? nil : fullHost,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                tls: tls
            )
        }

        if viewModel.dockerError == nil {
            onDismiss()
        }
    }

    private func makeTLS() -> DockerTLSOptions? {
        let ca = caCert.trimmingCharacters(in: .whitespacesAndNewlines)
        let cc = clientCert.trimmingCharacters(in: .whitespacesAndNewlines)
        let ck = clientKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if ca.isEmpty && cc.isEmpty && ck.isEmpty && !skipTLSVerify {
            return nil
        }
        return DockerTLSOptions(
            caCert: ca.isEmpty ? nil : ca,
            clientCert: cc.isEmpty ? nil : cc,
            clientKey: ck.isEmpty ? nil : ck,
            skipVerify: skipTLSVerify
        )
    }
}

/// Sheet form for creating or editing a Podman system connection.
public struct PodmanEditorSheet: View {
    @ObservedObject var viewModel: ContainerContextsViewModel
    let state: PodmanEditorState
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var originalName: String = ""
    @State private var scheme: PodmanURIScheme = .unix
    @State private var uriBody: String = ""
    @State private var identity: String = ""
    @State private var makeDefault: Bool = false

    public init(
        viewModel: ContainerContextsViewModel,
        state: PodmanEditorState,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.state = state
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Form {
                Section {
                    TextField(L("container.editor.name"), text: $name)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 6) {
                        Picker(L("container.editor.uri"), selection: $scheme) {
                            ForEach(PodmanURIScheme.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)

                        TextField(L("container.editor.uri"), text: $uriBody)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField(L("container.editor.identity"), text: $identity)
                        .textFieldStyle(.roundedBorder)

                    Toggle(L("container.editor.makeDefault"), isOn: $makeDefault)
                }
            }
            .formStyle(.grouped)

            if let msg = viewModel.podmanError {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            HStack {
                Spacer()
                Button(L("container.editor.cancel")) { onDismiss() }
                Button(L("container.editor.save")) {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 340)
        .onAppear { hydrate() }
    }

    private var isEditing: Bool {
        if case .edit = state { return true }
        return false
    }

    private var title: String {
        switch state {
        case .create: return L("container.podman.editor.addTitle")
        case .edit: return L("container.podman.editor.editTitle")
        }
    }

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = uriBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }
        if !isEditing && trimmedBody.isEmpty { return false }
        return true
    }

    private var fullURI: String {
        let body = uriBody.trimmingCharacters(in: .whitespacesAndNewlines)
        switch scheme {
        case .custom: return body
        case .unix, .ssh: return body.isEmpty ? "" : "\(scheme.rawValue)\(body)"
        }
    }

    private func hydrate() {
        switch state {
        case .create:
            name = ""
            originalName = ""
            scheme = .unix
            uriBody = ""
            identity = ""
            makeDefault = false
        case .edit(let conn):
            name = conn.name
            originalName = conn.name
            let parts = PodmanURIScheme.split(conn.uri)
            scheme = parts.0
            uriBody = parts.1
            identity = conn.identity
            makeDefault = conn.isDefault
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        let uri = fullURI

        switch state {
        case .create:
            await viewModel.addPodmanConnection(
                name: trimmedName,
                uri: uri,
                identity: trimmedIdentity.isEmpty ? nil : trimmedIdentity,
                makeDefault: makeDefault
            )
        case .edit:
            await viewModel.replacePodmanConnection(
                oldName: originalName,
                newName: trimmedName,
                uri: uri,
                identity: trimmedIdentity.isEmpty ? nil : trimmedIdentity,
                makeDefault: makeDefault
            )
        }

        if viewModel.podmanError == nil {
            onDismiss()
        }
    }
}
