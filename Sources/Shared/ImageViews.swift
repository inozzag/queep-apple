import SwiftUI
import PhotosUI
import QueepCore
import UniformTypeIdentifiers

struct ImagePixels: View {
    let data: Data
    var fill = false
    var body: some View {
        #if os(macOS)
        if let image = NSImage(data: data) { Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit) }
        #else
        if let image = UIImage(data: data) { Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit) }
        #endif
    }
}

struct ImagePickerSection: View {
    @Binding var image: ImportedImage?
    @Binding var preparing: Bool
    var disabled: Bool
    @State private var filePicker = false
    @State private var photo: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        Section("Imagem") {
            if let image {
                ImagePixels(data: image.data).frame(maxWidth: .infinity, maxHeight: 250)
                    .accessibilityLabel("Prévia da imagem selecionada")
            }
            #if os(iOS)
            PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) {
                Label("Escolher em Fotos", systemImage: "photo.on.rectangle")
            }.disabled(disabled || preparing).accessibilityIdentifier("capture.photos")
            #endif
            Button { filePicker = true } label: {
                Label(image == nil ? "Escolher arquivo" : "Trocar imagem", systemImage: "folder")
            }.disabled(disabled || preparing).accessibilityIdentifier("capture.imageFile")
            if preparing { ProgressView("Preparando imagem…") }
            if let error { Text(error).foregroundStyle(.red) }
            Text("JPEG, PNG ou HEIC · até 32 MB. A imagem é otimizada para salvar e sincronizar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.jpeg, .png, .heic, .heif]) { result in
            switch result {
            case .success(let url):
                Task {
                    preparing = true; error = nil; image = nil
                    defer { preparing = false }
                    do { image = try await Task.detached(priority: .userInitiated) { try ImportedImage.prepare(url: url) }.value }
                    catch { self.error = error.localizedDescription }
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .onChange(of: photo) { _, selection in
            guard let selection else { return }
            Task {
                preparing = true; error = nil; image = nil
                defer { preparing = false }
                do {
                    guard let value = try await selection.loadTransferable(type: ImportedImage.self) else {
                        throw QueepError.server("Não foi possível abrir esta foto.")
                    }
                    image = value
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct RemoteImage: View {
    @Environment(Session.self) private var session
    let reference: Reference
    var thumbnail = false
    var fill = false
    @State private var data: Data?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let data {
                ImagePixels(data: data, fill: fill).accessibilityLabel(reference.displayTitle)
            } else if let error {
                VStack(spacing: 8) {
                    Label(thumbnail ? "Prévia indisponível" : error, systemImage: "photo.badge.exclamationmark")
                    if !thumbnail { Button("Tentar novamente") { attempt += 1 } }
                }.font(.caption).foregroundStyle(.secondary).padding()
            } else {
                if thumbnail { Color.primary.opacity(0.05) }
                else { ProgressView("Carregando imagem…").controlSize(.small).padding() }
            }
        }
        .task(id: "\(session.userID ?? "")/\(reference.id)/\(attempt)") {
            data = nil; error = nil
            guard let api = session.client(), let uid = session.userID else { return }
            do {
                let bytes = try await (reference.media == nil ? api.imageData(reference, thumbnail: thumbnail)
                                      : api.mediaData(reference, thumbnail: thumbnail))
                guard !Task.isCancelled, uid == session.userID else { return }
                data = bytes
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

/// An image reads like a document too: the picture, a title, your notes, then the analysis.
struct ImageDetailView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let reference: Reference
    @State private var title: String
    @State private var text: String
    @State private var data: Data?
    @State private var loadError: String?
    @State private var attempt = 0
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var error: String?
    @State private var zoomed = false
    @State private var editor = MarkdownEditorController()
    @State private var mutationID = UUID()

    init(reference: Reference) {
        self.reference = reference
        _title = State(initialValue: reference.title)
        _text = State(initialValue: reference.text)
    }

    private var changed: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != reference.title || text != reference.text
    }
    private var canSave: Bool { changed && !busy && title.count <= 200 && text.count <= 30_000 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    DocumentActions { zoomButton; moreMenu }
                    picture
                    DocumentTitleField(title: $title, disabled: busy, identifier: "image.title")
                    MarkdownEditorBlock(text: $text, controller: editor,
                                        placeholder: "Anotações sobre esta imagem: onde viu, por que guardou, o que lembrar.",
                                        disabled: busy, minHeight: 120, identifier: "image.text")
                    AnalysisView(reference: reference)
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red) }
                }
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Color.card)
            .navigationTitle("Imagem")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { dismiss() }.disabled(busy)
                        .keyboardShortcut(.cancelAction)
                        #if os(iOS)
                        .labelStyle(.iconOnly)
                        #endif
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .primaryAction) { zoomButton; moreMenu }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if busy { ProgressView().controlSize(.small) }
                        else {
                            #if os(iOS)
                            Label("Salvar", systemImage: "checkmark").labelStyle(.iconOnly)
                            #else
                            Text("Salvar")
                            #endif
                        }
                    }.disabled(!canSave)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("image.save")
                        .accessibilityLabel(busy ? "Salvando" : "Salvar")
                }
            }
            .markdownToolbarBar(editor, disabled: busy)
            .confirmationDialog("Excluir esta imagem dos seus dispositivos?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { Task { await remove() } }
            }
        }
        .interactiveDismissDisabled(busy)
        .task(id: "\(session.userID ?? "")/\(reference.id)/\(attempt)") {
            data = nil; loadError = nil
            guard let api = session.client(), let uid = session.userID else { return }
            do {
                let bytes = try await api.imageData(reference)
                guard !Task.isCancelled, uid == session.userID else { return }
                data = bytes
            } catch is CancellationError { }
            catch { if !Task.isCancelled { loadError = error.localizedDescription } }
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 760, minHeight: 560, idealHeight: 720)
        #endif
    }

    private var zoomButton: some View {
        Button { zoomed.toggle() } label: {
            Label(zoomed ? "Ajustar imagem" : "Ampliar imagem",
                  systemImage: zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass")
        }.disabled(data == nil)
    }

    private var moreMenu: some View {
        Menu {
            if let data, let image = platformImage(data) {
                ShareLink(item: image, preview: SharePreview(reference.displayTitle, image: image)) {
                    Label("Compartilhar", systemImage: "square.and.arrow.up")
                }
                Button("Copiar imagem", systemImage: "doc.on.doc") { Clipboard.copy(imageData: data) }
            }
            Divider()
            Button("Excluir imagem", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .disabled(busy).accessibilityIdentifier("image.delete")
        } label: { Label("Mais", systemImage: "ellipsis.circle") }
            .accessibilityIdentifier("reference.more")
    }

    @ViewBuilder private var picture: some View {
        if let data {
            if zoomed {
                ScrollView([.horizontal, .vertical]) {
                    ImagePixels(data: data)
                        .frame(width: CGFloat(reference.image?.width ?? 1200) / 2,
                               height: CGFloat(reference.image?.height ?? 800) / 2)
                }
                .frame(height: 480)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("\(reference.displayTitle), ampliada")
            } else {
                ImagePixels(data: data)
                    .frame(maxWidth: .infinity).frame(maxHeight: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(reference.displayTitle)
            }
        } else if let loadError {
            VStack(spacing: 8) {
                Label(loadError, systemImage: "photo.badge.exclamationmark")
                Button("Tentar novamente") { attempt += 1 }
            }.font(.callout).foregroundStyle(Color.muted).frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            ProgressView("Carregando imagem…").controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 60)
        }
    }

    private func save() async {
        guard let api = session.client(), let uid = session.userID else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await api.editMetadata(reference, title: title, text: text, mutationID: mutationID)
            guard session.userID == uid else { return }
            store.discardSearchReference(reference.id)
            await store.refresh(api, account: uid)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func remove() async {
        guard let api = session.client(), let uid = session.userID else { return }
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
