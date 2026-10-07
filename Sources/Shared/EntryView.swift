import SwiftUI

/// The first screen: a ticker of the kind of things people save, then a wait or the way in.
/// Loading and sign-in share the ticker, so one turns into the other without a cut.
struct EntryView: View {
    let loading: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// iPhone raises a sheet from the bottom edge. Wider windows float a card over the ticker.
    private var floating: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            // Ignores the keyboard too, so typing an e-mail never lays the lanes out again.
            ReferenceTicker(gap: floating ? 14 : 10)
                .overlay { if floating { floatingVeil } else { sheetVeil } }
                .ignoresSafeArea()
            if floating { floatingStage } else { sheetStage }
        }
        .animation(.spring(duration: 0.55, bounce: 0.14), value: loading)
    }

    /// Keeps the status bar readable at the top and dissolves the lanes into the page below.
    private var sheetVeil: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0.44),
                    .init(color: .white.opacity(0.82), location: 0.59),
                    .init(color: .white, location: 0.70),
                    .init(color: .white, location: 1)
                ],
                startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
        }
    }

    private var floatingVeil: some View {
        ZStack {
            Color.white.opacity(0.3)
            RadialGradient(colors: [.white.opacity(0.92), .white.opacity(0)],
                           center: .center, startRadius: 140, endRadius: 560)
        }
    }

    private var sheetStage: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            // The keyboard counts as bottom inset, so this stays the height of the screen.
            let screen = proxy.size.height + insets.top + insets.bottom
            ZStack(alignment: .bottom) {
                if loading {
                    EntryLoadingMark()
                        .padding(.bottom, max(0, screen * 0.12 - insets.bottom))
                        .transition(.opacity)
                } else {
                    // Rises to about 62% of the screen. With the keyboard up it hugs its content.
                    SignInView()
                        .padding(.horizontal, 24)
                        .padding(.top, 54)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, minHeight: max(0, screen * 0.62 - insets.bottom),
                               alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36,
                                                   style: .continuous)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.1), radius: 28, y: -6)
                                .ignoresSafeArea(.container, edges: .bottom)
                        }
                        .overlay(alignment: .top) { LogoChip().offset(y: -LogoChip.defaultSize / 2) }
                        .transition(.offset(y: screen * 0.8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var floatingStage: some View {
        ZStack {
            if loading {
                EntryLoadingMark().transition(.opacity)
            } else {
                SignInView()
                    .padding(.horizontal, 28)
                    .padding(.top, 56)
                    .padding(.bottom, 24)
                    .frame(width: 400)
                    .frame(minHeight: 430, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.homeLine)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 40, y: 18)
                    .overlay(alignment: .top) { LogoChip().offset(y: -LogoChip.defaultSize / 2) }
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The mark on a white disc. It sits on the edge between the ticker and what comes after it.
struct LogoChip: View {
    static let defaultSize: CGFloat = 68
    var size: CGFloat = LogoChip.defaultSize

    var body: some View {
        QueepLogo(size: size * 0.46)
            .frame(width: size, height: size)
            .background(Color.white, in: Circle())
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
            .accessibilityHidden(true)
    }
}

private struct EntryLoadingMark: View {
    var body: some View {
        VStack(spacing: 0) {
            LogoChip(size: 76)
            Text("Queep")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.89)
                .foregroundStyle(Theme.homeInk)
                .padding(.top, 18)
            Text("Abrindo sua biblioteca…")
                .font(.system(size: 15))
                .foregroundStyle(Theme.homePreview)
                .padding(.top, 6)
            EntryLoadingBar()
                .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Abrindo sua biblioteca…")
        .accessibilityIdentifier("entry.loading")
    }
}

/// A short stroke sweeping a track: there is no measurable progress while the session opens.
private struct EntryLoadingBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let track: CGFloat = 132
    private let stroke: CGFloat = 46

    var body: some View {
        if reduceMotion {
            ProgressView().controlSize(.small)
        } else {
            Capsule()
                .fill(Theme.homeLine)
                .frame(width: track, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.queepThingsInk)
                        .frame(width: stroke, height: 4)
                        .phaseAnimator([false, true]) { view, moved in
                            view.offset(x: moved ? track - stroke : 0)
                        } animation: { _ in .easeInOut(duration: 0.9) }
                }
                .clipShape(Capsule())
        }
    }
}
