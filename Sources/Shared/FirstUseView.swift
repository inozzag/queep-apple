import SwiftUI

/// The empty library: what Queep things can save, as tiles, and how Queep works.
struct FirstUseView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var showActions = true
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content }.background(Theme.surface) }
            else { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text(showActions ? "Salve sua primeira referência" : "Como usar o Queep")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("onboarding.title")
                Text("Guarde o que vale lembrar. Suas referências aparecem no Mac e no iPhone, na mesma conta.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showActions {
                MasonryLayout(spacing: Theme.gap, forceColumns: typeSize.isAccessibilitySize ? 1 : 2) {
                    actionTile("Posts", detail: "X, Instagram, Dribbble, Behance ou Medium",
                               icon: "ri-hashtag", identifier: "onboarding.capture.link") {
                        store.startCapture(kind: "link", intent: "post")
                    }
                    actionTile("Galeria", detail: "Uma foto da sua biblioteca",
                               icon: "ri-image-line", identifier: "onboarding.capture.image") {
                        store.openPhotoLibrary = true
                    }
                    #if os(macOS)
                    actionTile("Arquivos", detail: "Imagem, áudio ou vídeo do computador",
                               icon: "ri-folder-line", identifier: "onboarding.capture.arquivo") {
                        store.openFileImporter = true
                    }
                    #endif
                    actionTile("Sites", detail: "Uma página pública para o Queep ler",
                               icon: "ri-link", identifier: "onboarding.capture.site") {
                        store.startCapture(kind: "link", intent: "site")
                    }
                    actionTile("Notes", detail: "Títulos, listas e tarefas",
                               icon: "ri-sticky-note-line", identifier: "onboarding.capture.note") {
                        store.startCapture(kind: "note")
                    }
                }
            }
            FirstUseTips()
        }
        .padding(.vertical, 28)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func actionTile(_ title: String, detail: String, icon: String, identifier: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                IconTile(asset: icon, fill: Theme.surface)
                Spacer(minLength: 6)
                Text(title)
                    .font(.system(size: Theme.tileTitle, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .surface(.fill, radius: Theme.radius)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// How Queep works, in three short tips.
struct FirstUseTips: View {
    var body: some View {
        VStack(spacing: 6) {
            tip("Salve e continue", icon: "ri-checkbox-circle-fill",
                text: "Você não precisa escolher pastas ou etiquetas. Depois de salvar, a interpretação acontece em segundo plano.")
            tip("Encontre pelo que você lembra", icon: "ri-search-ai-line",
                text: "Na busca da biblioteca, descreva o assunto, o nome ou a aparência. Por exemplo: interfaces claras de CRM. Os resultados vêm das suas referências salvas.")
            #if os(macOS)
            tip("Capture de qualquer lugar", icon: "ri-keyboard-line",
                text: "⌘⇧Espaço abre a captura rápida. ⌘⇧7 recorta a tela. O pin do Queep fica na tela: arraste para onde quiser e passe o mouse para colar, capturar ou abrir a biblioteca. Essas ações também estão no menu da barra superior.")
            #else
            tip("Salve sem sair de outro app", icon: "ri-share-2-line",
                text: "Toque em Compartilhar e escolha Queep para enviar um link, texto, imagem, áudio ou vídeo. Entre na sua conta no Queep antes do primeiro envio.")
            #endif
        }
        .padding(Theme.chromeInset)
        .surface(.outline, radius: Theme.radius)
    }

    private func tip(_ title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(asset: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(.trailing, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct HelpView: View {
    /// Pushed inside Ajustes. Back returns to that list; the close button still dismisses the sheet.
    var pushedInSettings = false
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library

    var body: some View {
        Group {
            if pushedInSettings {
                detail
            } else {
                NavigationStack { detail }
                    #if os(macOS)
                    .frame(minWidth: 440, idealWidth: 560, minHeight: 500, idealHeight: 660)
                    #endif
            }
        }
        .environment(\.colorScheme, .light)
    }

    private var detail: some View {
        SettingsPage(title: "Como usar o Queep",
                     subtitle: "Guarde o que vale lembrar. Suas referências aparecem no Mac e no iPhone, na mesma conta.",
                     titleIdentifier: "onboarding.title",
                     closeIdentifier: "onboarding.close",
                     close: close) {
            FirstUseTips()
        }
    }

    private func close() {
        if pushedInSettings { library.presentation = nil } else { dismiss() }
    }
}
