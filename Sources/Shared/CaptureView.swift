import SwiftUI
import QueepCore

struct CaptureView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let reference: Reference?
    @State private var kind: String
    @State private var title: String
    @State private var text: String
    @State private var url: String
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var requestID = UUID()
    @State private var attempted = false
    @State private var image: ImportedImage?
    @State private var preparing = false

    init(reference: Reference?) {
        self.reference = reference
        _kind = State(initialValue: reference?.kind ?? "note")
        _title = State(initialValue: reference?.title ?? "")
        _text = State(initialValue: reference?.text ?? "")
        _url = State(initialValue: reference?.url ?? "")
    }

    private var capture: Capture {
        Capture(kind: kind, title: title, text: text, url: kind == "link" ? url : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if reference == nil {
                    Picker("Tipo", selection: $kind) {
                        Text("Nota").tag("note"); Text("Link").tag("link"); Text("Imagem").tag("image")
                    }
                        .pickerStyle(.segmented)
                        .disabled(busy || attempted || preparing)
                }
                TextField("Título (opcional)", text: $title).disabled(busy || attempted)
                    .accessibilityIdentifier("capture.title")
                if kind == "link" {
                    TextField("https://…", text: $url).autocorrectionDisabled()
                        .accessibilityLabel("Endereço do link")
                        .accessibilityIdentifier("capture.url")
                        .disabled(busy || attempted)
                    if let source = reference?.url, let destination = URL(string: source) {
                        Button("Abrir site original") { openURL(destination) }
                    }
                }
                if kind == "image" {
                    ImagePickerSection(image: $image, preparing: $preparing, disabled: busy || attempted)
                } else { Section(kind == "note" ? "Sua nota" : "Contexto (opcional)") {
                    TextEditor(text: $text).frame(minHeight: 220).accessibilityLabel("Texto da referência")
                        .disabled(busy || attempted)
                        .accessibilityIdentifier("capture.text")
                } }
                if let reference { Section("Sobre esta referência") { AnalysisView(reference: reference) } }
                if busy && reference == nil { Text(kind == "image" ? "Enviando imagem…" : "Salvando…").font(.caption) }
                if let error { Text(error).foregroundStyle(.red) }
                if attempted {
                    Text("Envio não confirmado. Tente novamente com o mesmo conteúdo para evitar duplicação.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if reference != nil {
                    Button("Excluir referência", role: .destructive) { confirmDelete = true }.disabled(busy)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(reference == nil ? "Adicionar referência" : "Referência")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }.disabled(busy || preparing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if busy { ProgressView().controlSize(.small) }
                        else { Text(error == nil ? "Salvar" : "Tentar novamente") }
                    }.disabled(busy || preparing || (kind == "image" ? image == nil || title.count > 200 : !capture.isValid))
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("capture.save")
                }
            }
            .confirmationDialog("Excluir esta referência dos seus dispositivos?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { Task { await remove() } }
            }
        }
        .interactiveDismissDisabled(busy || preparing)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 580, minHeight: 500)
        #endif
    }

    private func save() async {
        guard let api = session.client(), let uid = session.userID else { return }
        busy = true
        defer { busy = false }
        do {
            if let reference { _ = try await api.edit(reference, capture: capture, mutationID: requestID) }
            else if kind == "image", let image {
                _ = try await api.uploadImage(id: requestID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), data: image.data)
            } else { _ = try await api.create(id: requestID, capture: capture) }
            guard session.userID == uid else { return }
            if let reference { store.discardSearchReference(reference.id) }
            await store.refresh(api, account: uid)
            dismiss()
        } catch { self.error = error.localizedDescription; attempted = true }
    }

    private func remove() async {
        guard let reference, let api = session.client(), let uid = session.userID else { return }
        busy = true
        defer { busy = false }
        do {
            try await api.delete(reference)
            guard session.userID == uid else { return }
            store.discardSearchReference(reference.id)
            await store.refresh(api, account: uid)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
