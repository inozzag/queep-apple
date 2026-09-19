import SwiftUI
import QueepCore

/// A reference reads like a document: title, content, then what the AI understood.
struct CaptureView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
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
    @State private var latest: Reference?
    @State private var image: ImportedImage?
    @State private var media: ImportedMedia?
    @State private var preparing = false
    @State private var editor = MarkdownEditorController()
    @FocusState private var titleFocused: Bool
    @State private var titleTouched = false

    init(reference: Reference?, initialKind: String = "note") {
        self.reference = reference
        _kind = State(initialValue: reference?.kind ?? initialKind)
        _title = State(initialValue: reference?.title ?? "")
        _text = State(initialValue: reference?.text ?? "")
        _url = State(initialValue: reference?.url ?? "")
    }

    private var capture: Capture {
        Capture(kind: kind, title: title, text: text, url: kind == "link" ? url : nil)
    }
    private var locked: Bool { busy || attempted }
    private var changed: Bool {
        guard let reference else { return true }
        return reference.title != title.trimmingCharacters(in: .whitespacesAndNewlines) || reference.text != text
            || (kind == "link" && reference.url != url.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private var canSave: Bool {
        !busy && !preparing && title.count <= 200 && changed
            && (kind == "media" ? media != nil : kind == "image" ? image != nil : capture.isValid)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if reference != nil { DocumentActions { moreMenu } }
                    if reference == nil {
                        Group {
                            if typeSize.isAccessibilitySize { kindPicker.pickerStyle(.menu) }
                            else { kindPicker.pickerStyle(.segmented).frame(maxWidth: 440) }
                        }.disabled(locked || preparing)
                    }
                    TextField("Título", text: $title, axis: .vertical)
                        .textFieldStyle(.plain).font(.title.weight(.bold)).lineLimit(1...3)
                        .focused($titleFocused).disabled(locked)
                        .accessibilityLabel("Título (opcional)")
                        .accessibilityIdentifier("capture.title")
                        .onChange(of: title) { _, _ in titleTouched = true }
                    if title.count > 200 {
                        Text("O título tem no máximo 200 caracteres.").font(.caption).foregroundStyle(.orange)
                    }
                    switch kind {
                    case "link": linkFields
                    case "image":
                        ImagePickerSection(image: $image, preparing: $preparing, disabled: locked).card(padding: 16, elevated: false)
                    case "media":
                        MediaPickerSection(media: $media, preparing: $preparing, disabled: locked).card(padding: 16, elevated: false)
                    default: noteEditor
                    }
                    if let live {
                        AnalysisView(reference: live)
                    }
                    if busy && reference == nil {
                        Label(kind == "image" ? "Enviando imagem…" : kind == "media" ? "Enviando mídia…" : "Salvando…", systemImage: "arrow.up.circle")
                            .font(.callout).foregroundStyle(Color.muted)
                    }
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red) }
                    if attempted {
                        Text("Envio não confirmado. Tente novamente com o mesmo conteúdo para evitar duplicação.")
                            .font(.caption).foregroundStyle(Color.muted)
                    }
                }
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Color.card)
            .navigationTitle(reference == nil ? "Nova referência" : reference?.kindLabel ?? "Referência")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }.disabled(busy || preparing)
                        .keyboardShortcut(.cancelAction)
                        #if os(iOS)
                        .labelStyle(.iconOnly)
                        #endif
                }
                #if os(iOS)
                if reference != nil { ToolbarItem(placement: .primaryAction) { moreMenu } }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if busy { ProgressView().controlSize(.small) }
                        else {
                            #if os(iOS)
                            Label(error == nil ? "Salvar" : "Tentar novamente",
                                  systemImage: error == nil ? "checkmark" : "arrow.clockwise")
                                .labelStyle(.iconOnly)
                            #else
                            Text(error == nil ? "Salvar" : "Tentar novamente")
                            #endif
                        }
                    }.disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("capture.save")
                        .accessibilityLabel(busy ? "Salvando referência" : error == nil ? "Salvar" : "Tentar novamente")
                }
            }
            .markdownToolbarBar(editor, shown: kind == "note" || kind == "link", disabled: locked)
            .confirmationDialog("Excluir esta referência dos seus dispositivos?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { Task { await remove() } }
            }
        }
        .interactiveDismissDisabled(busy || preparing)
        .onAppear { if reference == nil { titleFocused = true } }
        .onChange(of: liveTitle) { _, value in
            if !titleTouched, !value.isEmpty { title = value }
        }
        .task(id: reference?.id) {
            guard let reference, let api = session.client() else { return }
            let wantsPhotos = reference.linkSurface?.isPost == true
            var readyPolls = 0
            for _ in 0..<45 {
                if Task.isCancelled { return }
                do {
                    let fresh = try await api.get(id: reference.id)
                    latest = fresh
                    if fresh.status == "error" { return }
                    if fresh.status == "ready" {
                        readyPolls += 1
                        if !wantsPhotos || !fresh.gallery.isEmpty || readyPolls >= 15 { return }
                    }
                } catch is CancellationError { return }
                catch { }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 680, minHeight: 520, idealHeight: 640)
        #endif
    }

    @ViewBuilder private var moreMenu: some View {
        if let reference {
            Menu {
                if let source = reference.url, let destination = URL(string: source) {
                    Button(reference.linkSurface?.isPost == true ? "Abrir post original" : "Abrir site original",
                           systemImage: "safari") { openURL(destination) }
                    Button("Copiar link", systemImage: "link") { Clipboard.copy(source) }
                }
                if !reference.text.isEmpty {
                    Button("Copiar texto", systemImage: "doc.on.doc") { Clipboard.copy(reference.text) }
                }
                Divider()
                Button("Excluir referência", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    .disabled(busy).accessibilityIdentifier("reference.delete")
            } label: { Label("Mais", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("reference.more")
        }
    }

    private var kindPicker: some View {
        Picker(selection: $kind) {
            Text("Nota").tag("note"); Text("Link").tag("link"); Text("Imagem").tag("image")
            Text("Áudio/Vídeo").tag("media")
        } label: { Text("Tipo").fixedSize(horizontal: false, vertical: true).accessibilityHidden(true) }
            .labelsHidden()
            .accessibilityLabel("Tipo de referência")
            .accessibilityIdentifier("capture.kind")
    }

    private var live: Reference? {
        guard let reference else { return nil }
        let fromStore = store.items.first(where: { $0.id == reference.id })
        return [latest, fromStore, reference].compactMap { $0 }.max { lhs, rhs in
            if lhs.gallery.count != rhs.gallery.count { return lhs.gallery.count < rhs.gallery.count }
            return lhs.updatedAt < rhs.updatedAt
        }
    }
    private var liveTitle: String { live?.title ?? "" }

    private var linkFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(Color.muted)
                TextField(store.captureIntent == "post" || live?.linkSurface?.isPost == true
                          ? "Cole o link do post (X, Instagram, Dribbble, Behance ou Medium)"
                          : "https://…",
                          text: $url).textFieldStyle(.plain).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                    #endif
                    .accessibilityLabel("Endereço do link")
                    .accessibilityIdentifier("capture.url")
                    .disabled(locked)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let live, !live.gallery.isEmpty {
                RemoteImageCarousel(reference: live, thumbnail: false, fill: false, height: 280)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if let source = live?.source, source.state == "read", live?.linkSurface?.isPost == true,
               !source.text.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(source.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("post.body")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(store.captureIntent == "post" || live?.linkSurface?.isPost == true
                     ? "Contexto do post (opcional)" : "Contexto (opcional)").sectionLabel()
                editorBlock(minHeight: 120,
                            placeholder: store.captureIntent == "post" || live?.linkSurface?.isPost == true
                            ? "Quem postou, por que guardar, o que lembrar."
                            : "Por que este link importa?")
            }
        }
    }

    private var noteEditor: some View {
        editorBlock(minHeight: reference == nil ? 260 : 140,
                    placeholder: "Escreva sua nota. Use # para títulos, - para listas e - [ ] para tarefas.")
    }

    private func editorBlock(minHeight: CGFloat, placeholder: String) -> some View {
        MarkdownEditorBlock(text: $text, controller: editor, placeholder: placeholder, disabled: locked, minHeight: minHeight)
    }

    private func save() async {
        guard let api = session.client(), let uid = session.userID else { return }
        busy = true
        defer { busy = false }
        do {
            if let reference { _ = try await api.edit(reference, capture: capture, mutationID: requestID) }
            else if kind == "media", let media {
                _ = try await api.uploadMedia(id: requestID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), file: media.file.url)
            }
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
