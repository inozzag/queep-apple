import SwiftUI

struct FirstUseView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var showActions = true
    var scrolls = true

    var body: some View {
        Group {
            if scrolls { ScrollView { content }.background(Color.canvas) }
            else { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.aiGradient.opacity(0.16)).frame(width: 52, height: 52)
                    Image(systemName: "bookmark.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.aiGradient)
                }.accessibilityHidden(true)
                Text(showActions ? "Salve sua primeira referência" : "Como usar o Queep")
                    .font(.largeTitle.bold()).accessibilityIdentifier("onboarding.title")
                Text("Guarde o que vale lembrar. Suas referências aparecem no Mac e no iPhone, na mesma conta.")
                    .font(.title3).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
            if showActions {
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [.init(.flexible())] : [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    captureButton("Anotar uma ideia", detail: "Com títulos, listas e tarefas", symbol: "square.and.pencil", kind: "note")
                    captureButton("Salvar um link", detail: "O Queep lê a página pública", symbol: "link", kind: "link")
                    captureButton("Guardar uma imagem", detail: "Encontre depois pela aparência", symbol: "photo", kind: "image")
                    captureButton("Salvar áudio ou vídeo", detail: "Transcrito e resumido", symbol: "play.rectangle", kind: "media")
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                tip("Salve e continue", symbol: "checkmark.circle",
                    text: "Você não precisa escolher pastas ou etiquetas. Depois de salvar, a interpretação acontece em segundo plano.")
                Divider().padding(.vertical, 14)
                tip("Encontre pelo que você lembra", symbol: "sparkles",
                    text: "Na busca da biblioteca, descreva o assunto, o nome ou a aparência. Por exemplo: interfaces claras de CRM. Os resultados vêm das suas referências salvas.")
                Divider().padding(.vertical, 14)
                #if os(macOS)
                tip("Capture de qualquer lugar", symbol: "keyboard",
                    text: "⌘⇧Espaço abre a captura rápida. ⌘⇧7 recorta a tela. O pin do Queep fica na tela: arraste para onde quiser e passe o mouse para colar, capturar ou abrir a biblioteca. Essas ações também estão no menu da barra superior.")
                #else
                tip("Salve sem sair de outro app", symbol: "square.and.arrow.up",
                    text: "Toque em Compartilhar e escolha Queep para enviar um link, texto, imagem, áudio ou vídeo. Entre na sua conta no Queep antes do primeiro envio.")
                #endif
            }.card(padding: 20, elevated: false)
        }.padding(28).frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func captureButton(_ title: String, detail: String, symbol: String, kind: String) -> some View {
        Button { store.startCapture(kind: kind) } label: {
            HStack(spacing: 12) {
                KindTile(symbol: symbol, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(Color.muted)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier("onboarding.capture.\(kind)")
    }

    private func tip(_ title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(.tint).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HelpView: View {
    /// Pushed inside Ajustes. Back returns to that list; Fechar still dismisses the sheet.
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
    }

    private var detail: some View {
        FirstUseView(showActions: false)
            .navigationTitle("Primeiros passos")
            .toolbar {
                ToolbarItem(placement: pushedInSettings ? .confirmationAction : .cancellationAction) {
                    Button("Fechar") { close() }.accessibilityIdentifier("onboarding.close")
                }
            }
    }

    private func close() {
        if pushedInSettings { library.presentation = nil } else { dismiss() }
    }
}
