import SwiftUI

struct FirstUseView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var showActions = true
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content }.background(Color.white) }
            else { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text(showActions ? "Salve sua primeira referência" : "Como usar o Queep")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(GalleryStyle.ink)
                    .accessibilityIdentifier("onboarding.title")
                Text("Guarde o que vale lembrar. Suas referências aparecem no Mac e no iPhone, na mesma conta.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(GalleryStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showActions {
                MasonryLayout(spacing: GalleryStyle.gap, forceColumns: typeSize.isAccessibilitySize ? 1 : 2) {
                    actionTile(
                        "Posts",
                        detail: "X, Instagram, Dribbble, Behance ou Medium",
                        identifier: "onboarding.capture.link"
                    ) {
                        HomeGlyph(asset: "HomeHashtag", size: 22)
                    } action: {
                        store.startCapture(kind: "link", intent: "post")
                    }
                    actionTile(
                        "Galeria",
                        detail: "Uma foto da sua biblioteca",
                        identifier: "onboarding.capture.image"
                    ) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.homePreview)
                            .frame(width: 22, height: 22)
                    } action: {
                        store.openPhotoLibrary = true
                    }
                    #if os(macOS)
                    actionTile(
                        "Arquivos",
                        detail: "Imagem, áudio ou vídeo do computador",
                        identifier: "onboarding.capture.arquivo"
                    ) {
                        Image(systemName: "folder")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.homePreview)
                            .frame(width: 22, height: 22)
                    } action: {
                        store.openFileImporter = true
                    }
                    #endif
                    actionTile(
                        "Sites",
                        detail: "Uma página pública para o Queep ler",
                        identifier: "onboarding.capture.site"
                    ) {
                        HomeGlyph(asset: "HomeLink", size: 22)
                    } action: {
                        store.startCapture(kind: "link", intent: "site")
                    }
                    actionTile(
                        "Notes",
                        detail: "Títulos, listas e tarefas",
                        identifier: "onboarding.capture.note"
                    ) {
                        HomeGlyph(asset: "HomeFile", size: 22)
                    } action: {
                        store.startCapture(kind: "note")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                tip("Salve e continue", symbol: "checkmark.circle",
                    text: "Você não precisa escolher pastas ou etiquetas. Depois de salvar, a interpretação acontece em segundo plano.")
                Divider().overlay(GalleryStyle.ring).padding(.vertical, 14)
                tip("Encontre pelo que você lembra", symbol: "sparkles",
                    text: "Na busca da biblioteca, descreva o assunto, o nome ou a aparência. Por exemplo: interfaces claras de CRM. Os resultados vêm das suas referências salvas.")
                Divider().overlay(GalleryStyle.ring).padding(.vertical, 14)
                #if os(macOS)
                tip("Capture de qualquer lugar", symbol: "keyboard",
                    text: "⌘⇧Espaço abre a captura rápida. ⌘⇧7 recorta a tela. O pin do Queep fica na tela: arraste para onde quiser e passe o mouse para colar, capturar ou abrir a biblioteca. Essas ações também estão no menu da barra superior.")
                #else
                tip("Salve sem sair de outro app", symbol: "square.and.arrow.up",
                    text: "Toque em Compartilhar e escolha Queep para enviar um link, texto, imagem, áudio ou vídeo. Entre na sua conta no Queep antes do primeiro envio.")
                #endif
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GalleryStyle.fill)
            .galleryTile()
        }
        .padding(28)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func actionTile<Glyph: View>(
        _ title: String,
        detail: String,
        identifier: String,
        @ViewBuilder glyph: () -> Glyph,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                glyph().accessibilityHidden(true)
                Text(title)
                    .font(.system(size: GalleryStyle.tileTitle, weight: .medium))
                    .foregroundStyle(GalleryStyle.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GalleryStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(GalleryStyle.fill)
            .galleryTile()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private func tip(_ title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(GalleryStyle.ink)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(GalleryStyle.ink)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GalleryStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FirstUseView(showActions: false)
                .background(Color.white)
                .navigationTitle("Primeiros passos")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { GalleryPill(title: "Fechar", leading: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("onboarding.close")
                    }
                }
        }
        .environment(\.colorScheme, .light)
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 560, minHeight: 500, idealHeight: 660)
        #endif
    }
}
