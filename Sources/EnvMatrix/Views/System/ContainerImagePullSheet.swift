import SwiftUI

struct ContainerImagePullSheet: View {
    @ObservedObject var vm: ContainerImagesViewModel
    let onClose: () -> Void

    @State private var reference: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("container.pull.title"))
                    .font(.title3.bold())
                Spacer()
                Button(action: onClose) {
                    Text(L("container.pull.close"))
                }
                .disabled(vm.isBusy)
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                TextField(L("container.pull.placeholder"), text: $reference)
                    .textFieldStyle(.roundedBorder)
                    .disabled(vm.isBusy)

                if vm.isBusy {
                    Button(role: .destructive, action: { vm.cancelPull() }) {
                        Text(L("container.pull.cancel"))
                    }
                } else {
                    Button(action: startPull) {
                        Text(L("container.pull.start"))
                    }
                    .disabled(reference.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(vm.pullLog.enumerated()), id: \.offset) { pair in
                            Text(pair.element)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(pair.offset)
                        }
                    }
                    .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 240)
                .onChange(of: vm.pullLog.count) { newValue in
                    guard newValue > 0 else { return }
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(newValue - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 360)
    }

    private func startPull() {
        let ref = reference.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty else { return }
        Task { await vm.pull(reference: ref) }
    }
}
