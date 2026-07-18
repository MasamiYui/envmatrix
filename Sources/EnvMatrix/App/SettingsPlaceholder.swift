import SwiftUI

public struct SettingsPlaceholder: View {
    @StateObject private var localization = LocalizationManager.shared

    public init() {}

    public var body: some View {
        SettingsView()
            .environmentObject(localization)
    }
}
