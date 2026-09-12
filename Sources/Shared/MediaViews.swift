import AVKit
import PhotosUI
import QueepCore
import SwiftUI
import UniformTypeIdentifiers

struct MediaPickerSection: View {
    @Binding var media: ImportedMedia?
    @Binding var preparing: Bool
    let disabled: Bool
    @State private var filePicker = false
    @State private var photo: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        Section("Áudio ou vídeo") {
            if let media {
                Label(media.kind == "video" ? "Vídeo preparado" : "Áudio preparado",
                      systemImage: media.kind == "video" ? "play.rectangle" : "waveform")
                    .accessibilityIdentifier("capture.mediaReady")
                Text("\(Int(media.duration.rounded())) segundos").font(.caption)
            }
            #if os(iOS)
            PhotosPicker(selection: $photo, matching: .videos, preferredItemEncoding: .current) {
                Label("Escolher vídeo em Fotos", systemImage: "photo.on.rectangle")
            }.disabled(disabled || preparing).accessibilityIdentifier("capture.videos")
            #endif
            Button { filePicker = true } label: { Label("Escolher arquivo", systemImage: "folder") }
                .disabled(disabled || preparing).accessibilityIdentifier("capture.mediaFile")
            if preparing { ProgressView("Preparando mídia…") }
            if let error { Text(error).foregroundStyle(.red) }
            Text("Até 5 minutos · original de até 150 MB, com até 25 MB após preparar. Vídeos são otimizados para 720p.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.movie, .audio]) { result in
            Task {
                preparing = true; error = nil; media = nil
                defer { preparing = false }
                do { media = try await ImportedMedia.prepare(url: result.get()) }
                catch { self.error = error.localizedDescription }
            }
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            Task {
                preparing = true; error = nil; media = nil
                defer { preparing = false }
                do {
                    guard let value = try await selected.loadTransferable(type: ImportedMedia.self) else {
                        throw QueepError.server("Não foi possível abrir este vídeo.")
                    }
                    media = value
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct MediaDetailView: View {
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let reference: Reference
    @State private var player: AVPlayer?
    @State private var file: TemporaryMediaFile?
    @State private var error: String?
    @State private var attempt = 0
    @State private var busy = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let player {
                        MediaPlaybackView(player: player, video: reference.kind == "video",
                                          duration: reference.media?.durationSeconds ?? 0)
                    } else if error == nil { ProgressView("Carregando mídia…") }
                    if let media = reference.media {
                        Label("\(reference.kindLabel) · \(media.durationLabel)", systemImage: reference.kindSymbol)
                    }
                    if let error {
                        Text(error).foregroundStyle(.red)
                        Button("Tentar novamente") { attempt += 1 }.disabled(busy)
                    }
                    AnalysisView(reference: reference)
                    Button("Excluir \(reference.kindLabel.lowercased())", role: .destructive) { confirmDelete = true }
                        .disabled(busy).accessibilityIdentifier("media.delete")
                }.padding()
            }
            .navigationTitle(reference.displayTitle)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Fechar") { dismiss() }.disabled(busy)
            } }
            .confirmationDialog("Excluir esta mídia dos seus dispositivos?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Excluir", role: .destructive) { Task { await remove() } }
            }
        }
        .interactiveDismissDisabled(busy)
        .task(id: "\(session.userID ?? "")/\(reference.id)/\(attempt)") {
            clear(); error = nil
            guard let api = session.client(), let owner = session.userID else { return }
            do {
                let data = try await api.mediaData(reference)
                guard !Task.isCancelled, owner == session.userID else { return }
                let temporary = TemporaryMediaFile(extension: reference.kind == "video" ? "mp4" : "m4a")
                try data.write(to: temporary.url, options: .atomic)
                file = temporary; player = AVPlayer(url: temporary.url)
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .onDisappear { clear() }
        .onChange(of: phase) { _, value in if value != .active { player?.pause() } }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 680, minHeight: 500, idealHeight: 650)
        #endif
    }

    private func clear() { player?.pause(); player = nil; file = nil }

    private func remove() async {
        guard let api = session.client(), let owner = session.userID else { return }
        busy = true
        defer { busy = false }
        do {
            try await api.delete(reference)
            guard owner == session.userID else { return }
            clear(); store.discardSearchReference(reference.id)
            await store.refresh(api, account: owner)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct MediaPlaybackView: View {
    let player: AVPlayer
    let video: Bool
    let duration: Double
    @State private var elapsed = 0.0
    @State private var playing = false
    @State private var observer: Any?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 12) {
            if video { VideoPlayer(player: player).frame(height: 260) }
            if failed {
                Text("Não foi possível reproduzir este arquivo. Feche e abra a mídia novamente.")
                    .foregroundStyle(.red)
            }
            HStack(spacing: 16) {
                Button {
                    if playing { player.pause() }
                    else {
                        if elapsed >= duration - 0.2 { player.seek(to: .zero) }
                        player.play()
                    }
                } label: {
                    Label(playing ? "Pausar" : "Reproduzir",
                          systemImage: playing ? "pause.fill" : "play.fill")
                }
                .disabled(failed).accessibilityIdentifier("media.playPause")
                Spacer()
                Text(timestamp(elapsed)).monospacedDigit().font(.caption)
                    .accessibilityLabel("Tempo reproduzido: \(timestamp(elapsed))")
                    .accessibilityIdentifier("media.elapsed")
            }
            if !video {
                Slider(value: Binding(get: { elapsed }, set: { value in
                    elapsed = value
                    player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
                }), in: 0...max(duration, 0.1))
                .accessibilityLabel("Posição do áudio")
                .accessibilityValue("\(timestamp(elapsed)) de \(timestamp(duration))")
                .disabled(failed)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("media.player")
        .onReceive(player.publisher(for: \.timeControlStatus)) { playing = $0 == .playing }
        .onReceive(player.publisher(for: \.status)) { failed = $0 == .failed }
        .onReceive(NotificationCenter.default.publisher(
            for: .AVPlayerItemFailedToPlayToEndTime, object: player.currentItem)) { _ in failed = true }
        .onAppear {
            observer = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
                    Task { @MainActor in if time.seconds.isFinite { elapsed = time.seconds } }
                }
        }
        .onDisappear {
            player.pause()
            if let observer { player.removeTimeObserver(observer); self.observer = nil }
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
