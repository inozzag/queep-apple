import SwiftUI
import PhotosUI
import QueepCore
import UniformTypeIdentifiers

struct ImagePixels: View {
    let data: Data
    var body: some View {
        #if os(macOS)
        if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
        #else
        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
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
    @State private var data: Data?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let data {
                ImagePixels(data: data).accessibilityLabel(reference.displayTitle)
            } else if let error {
                VStack(spacing: 8) {
                    Label(thumbnail ? "Prévia indisponível" : error, systemImage: "photo.badge.exclamationmark")
                    if !thumbnail { Button("Tentar novamente") { attempt += 1 } }
                }.font(.caption).foregroundStyle(.secondary).padding()
            } else {
                ProgressView("Carregando imagem…").controlSize(.small).padding()
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

struct ImageDetailView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let reference: Reference
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var error: String?
    @State private var zoomed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        RemoteImage(reference: reference)
                            .frame(width: geometry.size.width * (zoomed ? 2 : 1),
                                   height: geometry.size.height * (zoomed ? 2 : 1))
                    }
                }
                ScrollView { AnalysisView(reference: reference) }.frame(maxHeight: 150)
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                Button("Excluir imagem", role: .destructive) { confirmDelete = true }
                    .disabled(busy).accessibilityIdentifier("image.delete")
            }.padding()
            .navigationTitle(reference.displayTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }.disabled(busy)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { zoomed.toggle() } label: {
                        Label(zoomed ? "Ajustar imagem" : "Ampliar imagem",
                              systemImage: zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass")
                    }
                }
            }
            .confirmationDialog("Excluir esta imagem dos seus dispositivos?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { Task { await remove() } }
            }
            .overlay { if busy { ProgressView("Excluindo…").padding().background(.regularMaterial) } }
        }
        .interactiveDismissDisabled(busy)
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 800, minHeight: 500, idealHeight: 650)
        #endif
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
