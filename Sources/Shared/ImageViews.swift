import SwiftUI
import PhotosUI
import AVFoundation
import CryptoKit
import QueepCore
import UniformTypeIdentifiers
import ImageIO

struct ImagePixels: View {
    let data: Data
    var fill = false
    var body: some View {
        #if os(macOS)
        if let image = DecodedImages.image(data) { Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit) }
        #else
        if let image = DecodedImages.image(data) { Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit) }
        #endif
    }
}

/// Images decoded once per byte buffer. `ImagePixels` can be rebuilt many times a second, as on
/// the gallery plane, and decoding in `body` would repeat the work each time.
enum DecodedImages {
    #if os(macOS)
    typealias PlatformImage = NSImage
    #else
    typealias PlatformImage = UIImage
    #endif

    nonisolated(unsafe) private static let cache: NSCache<NSData, PlatformImage> = {
        let cache = NSCache<NSData, PlatformImage>()
        cache.countLimit = 400
        return cache
    }()

    static func image(_ data: Data) -> PlatformImage? {
        let key = data as NSData
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = PlatformImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Decodes a thumbnail's pixels now, off the main thread, so drawing it later costs nothing.
    /// `maxPixels` bounds the long side; gallery tiles never show more.
    nonisolated static func prepare(_ data: Data, maxPixels: Int = 640) {
        let key = data as NSData
        guard cache.object(forKey: key) == nil,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
        #if os(macOS)
        let image = NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
        #else
        let image = UIImage(cgImage: pixels)
        #endif
        cache.setObject(image, forKey: key)
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
            if let error { Text(error).foregroundStyle(Theme.danger) }
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

/// Keeps gallery bytes in memory and on disk so scrolling back does not download them again.
enum ImageByteCache {
    // NSCache synchronizes its own reads and writes.
    private nonisolated(unsafe) static let memory: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 80
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private static let io = NSLock()
    private static let budget = 160 * 1024 * 1024
    // Incremented only while `io` is locked.
    private nonisolated(unsafe) static var writes = 0
    private static let folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("queep-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func key(account: String, reference: Reference, index: Int = 0,
                    thumbnail: Bool = true, author: Bool = false, motion: Bool = false) -> String {
        let sha: String
        if author {
            sha = reference.authorImage?.sha256 ?? ""
        } else if reference.gallery.indices.contains(index) {
            sha = reference.gallery[index].sha256
        } else {
            sha = reference.media?.sha256 ?? ""
        }
        return "\(account)/\(reference.id)/\(index)/\(author)/\(thumbnail)/\(motion)/\(sha)"
    }

    /// Memory only, cheap enough for `body`: lets a view that is rebuilt draw its image in the
    /// first frame instead of an empty placeholder.
    static func memoryData(for key: String) -> Data? {
        memory.object(forKey: key as NSString) as Data?
    }

    static func data(for key: String) -> Data? {
        if let hit = memory.object(forKey: key as NSString) { return hit as Data }
        let url = fileURL(key)
        io.lock()
        let stored = try? Data(contentsOf: url)
        io.unlock()
        guard let stored, !stored.isEmpty else { return nil }
        memory.setObject(stored as NSData, forKey: key as NSString, cost: stored.count)
        return stored
    }

    static func store(_ data: Data, for key: String) {
        guard !data.isEmpty else { return }
        memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        io.lock()
        defer { io.unlock() }
        try? data.write(to: fileURL(key), options: .atomic)
        writes += 1
        if writes.isMultiple(of: 16) { trimLocked() }
    }

    private static func fileURL(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(name)
    }

    private static func trimLocked() {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let ranked = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = ranked.reduce(0) { $0 + $1.1 }
        for item in ranked where total > budget {
            try? manager.removeItem(at: item.0)
            total -= item.1
        }
    }
}

/// How many muted loops may play at once, and how far ahead of the viewport their bytes are fetched.
enum InlineLoop {
    static let playerCap = 4
    static let prefetchMargin: CGFloat = 360
}

/// Downloads posters for the first screen, and loop bytes only for cells near the viewport.
enum ImagePrefetch {
    static func warm(_ items: [Reference], client: APIClient, account: String) {
        let posters = Array(items.prefix(18))
        guard !posters.isEmpty else { return }
        Task { await fetch(posters, client: client, account: account, motion: false) }
    }

    static func warmMotion(_ items: [Reference], client: APIClient, account: String) {
        let moving = items.filter(\.playsInlineLoop)
        guard !moving.isEmpty else { return }
        Task { await fetch(moving, client: client, account: account, motion: true) }
    }

    private static func fetch(_ items: [Reference], client: APIClient, account: String, motion: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for reference in items {
                if running == 4 {
                    await group.next()
                    running -= 1
                }
                group.addTask {
                    await load(reference, client: client, account: account, motion: motion)
                }
                running += 1
            }
            await group.waitForAll()
        }
    }

    private static func load(_ reference: Reference, client: APIClient, account: String, motion: Bool) async {
        if motion {
            guard reference.playsInlineLoop else { return }
        } else if reference.kind != "video" && reference.gallery.isEmpty {
            return
        }
        let key = ImageByteCache.key(account: account, reference: reference, thumbnail: !motion, motion: motion)
        if ImageByteCache.data(for: key) != nil { return }
        do {
            let bytes: Data
            if motion, reference.kind == "video", reference.media?.loop == true {
                bytes = try await client.mediaData(reference, loop: true)
            } else if reference.kind == "video", reference.gallery.isEmpty {
                bytes = try await client.mediaData(reference, thumbnail: !motion, loop: motion)
            } else if motion {
                bytes = try await client.imageData(reference, motion: true)
            } else {
                bytes = try await client.imageData(reference, thumbnail: true)
            }
            ImageByteCache.store(bytes, for: key)
        } catch { }
    }
}

struct RemoteImage: View {
    @Environment(Session.self) private var session
    let reference: Reference
    var thumbnail = false
    var fill = false
    var index = 0
    var author = false
    /// Draws nothing until loaded, so a sharper copy can sit over a preview that is already shown.
    var quiet = false
    @State private var data: Data?
    @State private var error: String?
    @State private var attempt = 0

    private var cacheKey: String {
        ImageByteCache.key(account: session.userID ?? "", reference: reference,
                           index: index, thumbnail: thumbnail, author: author)
    }

    var body: some View {
        Group {
            if let data = data ?? ImageByteCache.memoryData(for: cacheKey) {
                ImagePixels(data: data, fill: fill).accessibilityLabel(reference.displayTitle)
            } else if quiet {
                Color.clear
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
        .task(id: "\(cacheKey)/\(attempt)") {
            // Disk reads and decoding stay off the main thread: on the gallery plane many tiles
            // appear at once while the hand is moving.
            let key = cacheKey
            let small = thumbnail || author
            let cached = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let bytes = ImageByteCache.data(for: key) else { return nil }
                if small { DecodedImages.prepare(bytes) }
                return bytes
            }.value
            guard !Task.isCancelled else { return }
            if let cached {
                data = cached
                error = nil
                return
            }
            data = nil
            error = nil
            guard let api = session.client(), let uid = session.userID else { return }
            do {
                let bytes = try await (author || reference.media == nil
                                       ? api.imageData(reference, thumbnail: thumbnail, index: index,
                                                       role: author ? "author" : "gallery")
                                       : api.mediaData(reference, thumbnail: thumbnail))
                guard !Task.isCancelled, uid == session.userID else { return }
                await Task.detached(priority: .userInitiated) {
                    ImageByteCache.store(bytes, for: key)
                    if small { DecodedImages.prepare(bytes) }
                }.value
                guard !Task.isCancelled else { return }
                data = bytes
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct RemoteImageCarousel: View {
    let reference: Reference
    var thumbnail = false
    var fill = false
    var height: CGFloat? = 280
    var showsChrome = true
    @State private var page: Int? = 0

    private var gallery: [ImageInfo] { reference.gallery }
    private var current: Int {
        min(max(page ?? 0, 0), max(gallery.count - 1, 0))
    }
    private var currentKind: String { showsPlay(at: current) ? "Vídeo" : "Foto" }

    private func showsPlay(at index: Int) -> Bool {
        guard gallery.indices.contains(index) else { return false }
        if gallery[index].isVideoPreview {
            return reference.linkSurface?.isPost != true
        }
        return gallery.count == 1 && (reference.kind == "video" || reference.media != nil)
    }

    var body: some View {
        Group {
            if gallery.isEmpty {
                Color.clear
            } else {
                GeometryReader { geo in
                    let pageSize = CGSize(width: max(geo.size.width, 1), height: max(geo.size.height, 1))
                    ZStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(gallery.indices, id: \.self) { index in
                                    ZStack {
                                        if abs(index - current) <= 1 {
                                            RemoteImage(reference: reference, thumbnail: thumbnail, fill: fill, index: index)
                                            if gallery[index].motion == true, index == current {
                                                MotionLoop(reference: reference, index: index, fill: fill, active: true)
                                            }
                                        } else {
                                            Color.primary.opacity(0.05)
                                        }
                                        if showsPlay(at: index), gallery[index].motion != true {
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.white)
                                                .shadow(radius: 6)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .frame(width: pageSize.width, height: pageSize.height)
                                    .clipped()
                                    .id(index)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $page)
                        .scrollDisabled(gallery.count < 2)
                        if gallery.count > 1 {
                            chrome
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .onChange(of: reference.id) { _, _ in page = 0 }
        .onChange(of: gallery.count) { _, count in
            if current >= count { page = max(0, count - 1) }
        }
        .accessibilityIdentifier(gallery.count > 1 ? "post.carousel" : "post.photo")
        .accessibilityLabel(gallery.count > 1 ? "Carrossel de \(gallery.count) mídias" : reference.displayTitle)
        .accessibilityValue(gallery.count > 1 ? "\(currentKind) \(current + 1) de \(gallery.count)" : "")
        .accessibilityAdjustableAction { direction in
            guard gallery.count > 1 else { return }
            switch direction {
            case .increment: if current + 1 < gallery.count { page = current + 1 }
            case .decrement: if current > 0 { page = current - 1 }
            default: break
            }
        }
    }

    @ViewBuilder private var chrome: some View {
        if showsChrome {
            HStack {
                stepButton(back: true)
                Spacer()
                stepButton(back: false)
            }
            .padding(.horizontal, 8)
        }
        VStack {
            Spacer()
            HStack {
                dots
                Spacer()
                if showsChrome { countBadge }
            }
            .padding(10)
        }
        .allowsHitTesting(showsChrome)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(gallery.indices, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .shadow(radius: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private var countBadge: some View {
        Text("\(current + 1)/\(gallery.count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .accessibilityHidden(true)
    }

    private func stepButton(back: Bool) -> some View {
        Button {
            let next = back ? current - 1 : current + 1
            guard gallery.indices.contains(next) else { return }
            page = next
        } label: {
            Image(systemName: back ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.black.opacity(current == (back ? 0 : gallery.count - 1) ? 0.2 : 0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(current == (back ? 0 : gallery.count - 1))
        .opacity(current == (back ? 0 : gallery.count - 1) ? 0.35 : 1)
        .accessibilityLabel(back ? "Foto anterior" : "Próxima foto")
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
    private var canSave: Bool {
        changed && !busy && !reference.isArchived && title.count <= 200 && text.count <= 30_000
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack { ReferenceSpaceButton(reference: reference); Spacer(); DocumentActions { zoomButton; moreMenu } }
                    picture
                    DocumentTitleField(title: $title, disabled: busy || reference.isArchived,
                                       identifier: "image.title")
                    MarkdownEditorBlock(text: $text, controller: editor,
                                        placeholder: "Anotações sobre esta imagem: onde viu, por que guardou, o que lembrar.",
                                        disabled: busy || reference.isArchived, minHeight: 120,
                                        identifier: "image.text")
                    AnalysisView(reference: reference)
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Theme.danger) }
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
            .confirmationDialog("Excluir permanentemente esta imagem?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { Task { await remove() } }
            } message: { Text("Arquivar esconde. Excluir apaga da sua conta.") }
        }
        .subscriptionGate()
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
            Button(reference.isArchived ? "Desarquivar" : "Arquivar",
                   systemImage: reference.isArchived ? "archivebox.fill" : "archivebox") {
                archive()
            }
            .accessibilityIdentifier("image.archive")
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
            }.font(.callout).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity).padding(.vertical, 40)
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
            await store.refresh(api, account: uid, force: true)
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
            await store.refresh(api, account: uid, force: true)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func archive() {
        guard let api = session.client(), let uid = session.userID else { return }
        store.setArchived([reference], archived: !reference.isArchived, client: api, account: uid)
    }
}

/// Poster stays underneath until the muted loop is ready, then the GIF or the first 8 seconds play.
/// `active` is false for off-screen cells so the player, looper, and temp file are released.
struct MotionLoop: View {
    @Environment(Session.self) private var session
    let reference: Reference
    var index = 0
    var fill = true
    var active = false
    /// The tile's corner radius. The video is a platform layer that SwiftUI's clip shape does not
    /// reach, so the layer rounds itself.
    var cornerRadius: CGFloat = 0
    @State private var data: Data?

    /// Uploaded videos keep their loop even when a poster image is stored beside the file.
    private var usesUploadedLoop: Bool { reference.kind == "video" && reference.media?.loop == true }

    private var enabled: Bool {
        if usesUploadedLoop { return true }
        return reference.gallery.indices.contains(index) && reference.gallery[index].motion == true
    }

    private var cacheKey: String {
        ImageByteCache.key(account: session.userID ?? "", reference: reference,
                           index: index, thumbnail: false, motion: true)
    }

    var body: some View {
        // A ZStack, not a Group: an empty Group is no view at all, so its task never ran and
        // the loop was never fetched.
        ZStack {
            Color.clear
            if active, let data {
                LoopFilm(data: data, fill: fill, cornerRadius: cornerRadius)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: active ? cacheKey : "off-\(cacheKey)") {
            guard active, enabled, let api = session.client(), let uid = session.userID else { return }
            if let cached = ImageByteCache.data(for: cacheKey) {
                data = cached
                return
            }
            do {
                let bytes = try await usesUploadedLoop
                    ? api.mediaData(reference, loop: true)
                    : api.imageData(reference, index: index, motion: true)
                guard !Task.isCancelled, uid == session.userID else { return }
                ImageByteCache.store(bytes, for: cacheKey)
                data = bytes
            } catch { }
        }
    }
}


private struct LoopFilm: View {
    let data: Data
    var fill = false
    var cornerRadius: CGFloat = 0
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var file: TemporaryMediaFile?

    var body: some View {
        // Not a Group: an empty Group never appears, and the player is made on appear.
        ZStack {
            Color.clear
            if let player {
                PlayerLayerBox(player: player, fill: fill, cornerRadius: cornerRadius)
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
        file = nil
    }

    private func start() {
        if let player {
            player.play()
            return
        }
        let stored = TemporaryMediaFile(extension: "mp4")
        do { try data.write(to: stored.url, options: .atomic) } catch { return }
        let item = AVPlayerItem(url: stored.url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        let loop = AVPlayerLooper(player: queue, templateItem: item)
        file = stored
        looper = loop
        player = queue
        queue.play()
    }
}

#if os(iOS)
import UIKit

private struct PlayerLayerBox: UIViewRepresentable {
    let player: AVPlayer
    var fill: Bool
    var cornerRadius: CGFloat = 0

    func makeUIView(context: Context) -> PlayerHost {
        let view = PlayerHost()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: PlayerHost, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.playerLayer.cornerRadius = cornerRadius
        view.playerLayer.cornerCurve = .continuous
        view.playerLayer.masksToBounds = cornerRadius > 0
    }
}

private final class PlayerHost: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#else
import AppKit

private struct PlayerLayerBox: NSViewRepresentable {
    let player: AVPlayer
    var fill: Bool
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> PlayerHost {
        let view = PlayerHost()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PlayerHost, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.playerLayer.cornerRadius = cornerRadius
        view.playerLayer.cornerCurve = .continuous
        view.playerLayer.masksToBounds = cornerRadius > 0
    }
}

private final class PlayerHost: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVPlayerLayer()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#endif
