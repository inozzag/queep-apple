import SwiftUI

struct FirstUseView: View {
    @Environment(LibraryStore.self) private var store
    var showActions = true
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content } }
            else { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "bookmark.square.fill").font(.system(size: 40))
                    .foregroundStyle(.tint).accessibilityHidden(true)
                Text(showActions ? "Salve sua primeira referência" : "Como usar o Queep")
                    .font(.largeTitle.bold()).accessibilityIdentifier("onboarding.title")
                Text("Guarde o que vale lembrar. Suas referências aparecem no Mac e no iPhone, na mesma conta.")
                    .font(.title3).foregroundStyle(Color.primary.opacity(0.8))
            }
            if showActions {
                VStack(spacing: 12) {
                    captureButton("Anotar uma ideia", symbol: "square.and.pencil", kind: "note")
                    captureButton("Salvar um link", symbol: "link", kind: "link")
                    captureButton("Guardar uma imagem", symbol: "photo", kind: "image")
                    captureButton("Salvar áudio ou vídeo", symbol: "play.rectangle", kind: "media")
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                tip("Salve e continue", symbol: "checkmark.circle",
                    text: "Você não precisa escolher pastas ou etiquetas. Depois de salvar, a interpretação acontece em segundo plano.")
                tip("Encontre pelo que você lembra", symbol: "magnifyingglass",
                    text: "Na busca da biblioteca, descreva o assunto, o nome ou a aparência. Por exemplo: interfaces claras de CRM. Os resultados vêm das suas referências salvas.")
                #if os(macOS)
                tip("Capture de qualquer lugar", symbol: "keyboard",
                    text: "⌘⇧Espaço abre a captura rápida. ⌘⇧7 recorta a tela. Essas ações também estão no menu do Queep, na barra superior do Mac.")
                #else
                tip("Salve sem sair de outro app", symbol: "square.and.arrow.up",
                    text: "Toque em Compartilhar e escolha Queep para enviar um link, texto, imagem, áudio ou vídeo. Entre na sua conta no Queep antes do primeiro envio.")
                #endif
            }
        }.padding(28).frame(maxWidth: 560)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func captureButton(_ title: String, symbol: String, kind: String) -> some View {
        Button { store.startCapture(kind: kind) } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("onboarding.capture.\(kind)")
    }

    private func tip(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            Text(text).foregroundStyle(Color.primary.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            FirstUseView(showActions: false)
                .navigationTitle("Primeiros passos")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fechar") { dismiss() }.accessibilityIdentifier("onboarding.close")
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 550, minHeight: 500, idealHeight: 650)
        #endif
    }
}
