import QueepCore
import SwiftUI

/// Ajustes pieces. Rows follow the paywall's benefit list: a 46pt icon well and the label,
/// grouped in an outlined 22pt container with a 6pt inset.

/// A titled group of rows.
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .sectionLabel()
                    .padding(.leading, 14)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 2) { content }
                .padding(Theme.chromeInset)
                .surface(.outline, radius: Theme.radius)
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }
        }
    }
}

/// Icon, title, an optional value and a chevron. Put it inside a `NavigationLink`, `Link` or
/// `Button` styled with `SettingsRowStyle`.
struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var chevron = true
    var tint: Color = Theme.ink

    var body: some View {
        HStack(spacing: 12) {
            IconTile(asset: icon, color: tint)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if chevron {
                QueepIcon("ri-arrow-right-s-line", size: 20, color: Theme.inkFaint)
            }
        }
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Pressed and hovered rows take a pale fill.
struct SettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsRowBody(configuration: configuration)
    }
}

private struct SettingsRowBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.fill : hovered ? Theme.fill.opacity(0.6) : .clear)
            }
            .opacity(enabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }
    }
}

/// A row with a switch on the right.
struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var identifier: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                IconTile(asset: icon)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.forest)
        .accessibilityIdentifier(identifier ?? "")
        .padding(.trailing, 8)
    }
}

/// A pushed Ajustes page: big title, an optional line under it, and the content in one column.
/// The close button in the bar dismisses the whole sheet.
struct SettingsPage<Content: View>: View {
    let title: String
    var subtitle: String?
    var titleIdentifier: String?
    var closeIdentifier = "account.close"
    var closeDisabled = false
    let close: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(titleIdentifier ?? "")
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                SettingsCloseButton(identifier: closeIdentifier, action: close)
                    .disabled(closeDisabled)
            }
        }
    }
}

/// Round close in the top corner of Ajustes.
struct SettingsCloseButton: View {
    var identifier = "account.close"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QueepIcon("ri-close-line", size: 22, color: Theme.ink)
                .frame(width: 40, height: 40)
                .background(Theme.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Fechar")
        .accessibilityIdentifier(identifier)
    }
}

/// A short status line under a form: green for done, red for a failure.
struct SettingsNotice: View {
    let text: String
    var failure = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            QueepIcon(failure ? "ri-error-warning-line" : "ri-checkbox-circle-fill", size: 18,
                      color: failure ? Theme.danger : Theme.forest)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(failure ? Theme.danger : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .surface(.fill, radius: Theme.controlRadius)
    }
}
