import SwiftUI

public struct LocalAppsView: View {
    @StateObject private var vm: LocalAppsViewModel
    @EnvironmentObject private var localization: LocalizationManager
    @State private var showUninstallConfirm = false

    public init() {
        let probe = DefaultBrewCaskProbe()
        let scanner = DefaultLocalAppsScanner(probe: probe)
        let service = DefaultLocalAppsService()
        _vm = StateObject(wrappedValue: LocalAppsViewModel(scanner: scanner, service: service))
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbarBar
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(L("localApps.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.refresh()
                } label: {
                    Label(L("localApps.refresh"), systemImage: "arrow.clockwise")
                }
            }
        }
        .task { vm.refresh() }
        .alert(
            L("localApps.uninstall.title"),
            isPresented: Binding(
                get: { vm.pendingUninstall != nil },
                set: { if !$0 { vm.cancelUninstall() } }
            )
        ) {
            Button(L("localApps.uninstall.confirm"), role: .destructive) {
                vm.confirmUninstall()
            }
            Button(L("localApps.uninstall.cancel"), role: .cancel) {
                vm.cancelUninstall()
            }
        } message: {
            Text(L("localApps.uninstall.message"))
        }
        .alert(
            L("localApps.error.moveToTrashFailed"),
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )
        ) {
            Button(L("localApps.uninstall.cancel"), role: .cancel) {
                vm.errorMessage = nil
            }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: { !vm.pendingLeftovers.isEmpty },
                set: { if !$0 { vm.dismissLeftovers() } }
            )
        ) {
            LocalAppLeftoversSheet(
                leftovers: vm.pendingLeftovers,
                onConfirm: { selection in
                    vm.confirmLeftoverTrash(selection: selection)
                },
                onCancel: {
                    vm.dismissLeftovers()
                }
            )
        }
    }

    private var toolbarBar: some View {
        HStack(spacing: 12) {
            TextField(L("localApps.searchPlaceholder"), text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200, maxWidth: 320)

            Picker(L("localApps.source.label"), selection: $vm.sourceFilter) {
                Text(L("localApps.source.all")).tag(LocalAppSourceFilter.all)
                Text(L("localApps.source.appStore")).tag(LocalAppSourceFilter.appStore)
                Text(L("localApps.source.brew")).tag(LocalAppSourceFilter.brewCask)
                Text(L("localApps.source.other")).tag(LocalAppSourceFilter.other)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Picker(L("localApps.sort.label"), selection: $vm.sortKey) {
                Text(L("localApps.sort.name")).tag(LocalAppSortKey.name)
                Text(L("localApps.sort.size")).tag(LocalAppSortKey.size)
                Text(L("localApps.sort.source")).tag(LocalAppSortKey.source)
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            if vm.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var mainArea: some View {
        if vm.filteredApps.isEmpty && !vm.isBusy {
            emptyPlaceholder
        } else {
            List(vm.filteredApps) { app in
                LocalAppRow(
                    app: app,
                    isProtected: vm.isProtected(app),
                    onOpen: { vm.open(app) },
                    onReveal: { vm.reveal(app) },
                    onUninstall: {
                        vm.requestUninstall(app)
                        showUninstallConfirm = true
                    }
                )
            }
            .listStyle(.inset)
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.badge.checkmark.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L("localApps.empty"))
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
