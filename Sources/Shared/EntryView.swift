import SwiftUI

/// The first screen. While the session opens: a white page with the Queep motion small in the
/// middle. Then the way in, from the Figma "Login": the form beside a dark panel of clouds and the
/// places people save from. iPhone stacks the panel above the form.
struct EntryView: View {
    let loading: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// iPhone stacks; wider windows show the split card.
    private var split: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            if loading {
                QueepLoadingScreen()
                    .transition(.opacity)
            } else if split {
                SplitSignIn()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                StackedSignIn()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: loading)
    }
}

/// Mac and iPad: one card, 53pt corners, the form on the left and the art panel on the right.
private struct SplitSignIn: View {
    var body: some View {
        GeometryReader { geo in
            let width = min(1006, geo.size.width - 64)
            let height = min(698, geo.size.height - 48)
            HStack(spacing: 0) {
                ViewThatFits(in: .vertical) {
                    form
                    ScrollView { form }
                        .scrollIndicators(.hidden)
                }
                .frame(width: width / 2)
                .frame(maxHeight: .infinity)
                .background(Theme.surface)
                SignInArtPanel()
                    .frame(width: width / 2)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 53, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 53, style: .continuous)
                    .strokeBorder(Theme.lineStrong, lineWidth: 1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var form: some View {
        SignInView()
            .frame(maxWidth: 360)
            .padding(.horizontal, 40)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// iPhone: the art panel as a rounded hero, then the form.
private struct StackedSignIn: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SignInArtPanel(compact: true)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .padding(.horizontal, 8)
                SignInView()
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Dark panel: the headline, the networks Queep saves from, and the clouds rising from below.
private struct SignInArtPanel: View {
    var compact = false

    private let networks = [
        ["ri-instagram-fill", "ri-youtube-fill", "ri-dribbble-line", "ri-twitter-x-fill"],
        ["ri-facebook-box-fill", "ri-linkedin-fill", "ri-behance-fill", "ri-threads-fill"],
    ]

    var body: some View {
        PromoStage(style: .signIn, anchor: compact ? .bottom : .center)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: compact ? 18 : 28) {
                    Text("Salve tudo o que você vê em")
                        .font(.system(size: compact ? 26 : 35, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: compact ? 12 : 22) {
                        ForEach(networks, id: \.self) { row in
                            HStack(spacing: compact ? 12 : 20) {
                                ForEach(row, id: \.self) { icon in
                                    QueepIcon(icon, size: compact ? 22 : 26.6, color: Theme.lime)
                                        .frame(width: compact ? 44 : 51, height: compact ? 44 : 51)
                                        .background(Theme.lime.opacity(0.1),
                                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Instagram, YouTube, Dribbble, X, Facebook, LinkedIn, Behance e Threads")
                }
                .padding(.horizontal, compact ? 24 : 40)
                .padding(.top, compact ? 28 : 72)
            }
    }
}
