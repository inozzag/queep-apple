import SwiftUI
import UIKit
import QueepCore

@MainActor
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        CrashReporting.start()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        CrashReporting.start()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        CrashReporting.start()
        #if DEBUG
        if CrashReporting.consumeShareTestCrash(extensionContext) { return }
        #endif
        guard let extensionContext else { return }
        let session = Session()
        let controller = UIHostingController(rootView: ShareView(context: extensionContext)
            .environment(session))
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
    }
}

private struct ShareView: View {
    @Environment(Session.self) private var session
    let context: NSExtensionContext
    @State private var incoming: IncomingReference?
    @State private var error: String?
    @State private var loading = true
    @State private var sending = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if loading || session.preparing { ProgressView("Preparando referência…") }
                    if let configurationError = session.configurationError {
                        Text(configurationError).foregroundStyle(.red)
                    } else if !session.preparing && session.userID == nil {
                        Label("Abra o Queep e entre na sua conta. Depois compartilhe novamente.", systemImage: "person.crop.circle")
                    }
                    if let incoming {
                        if let media = incoming.media {
                            Label(media.kind == "video" ? "Vídeo preparado" : "Áudio preparado",
                                  systemImage: media.kind == "video" ? "play.rectangle" : "waveform")
                            Text("\(Int(media.duration.rounded())) segundos · pronto para enviar")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let bytes = incoming.image, let image = UIImage(data: bytes) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280)
                                .accessibilityLabel("Imagem compartilhada")
                        }
                        if let url = incoming.url { Label(url, systemImage: "link").lineLimit(4) }
                        if !incoming.text.isEmpty { Text(incoming.text).lineLimit(12) }
                        Text("A referência será salva na sua biblioteca e analisada em segundo plano.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("share.error") }
                    if session.planRequirement != nil {
                        Text("Abra o Queep e acesse Conta → Assinatura para conhecer o Max. Depois compartilhe novamente.")
                        Button("Abrir Queep") {
                            let scheme = Bundle.main.object(forInfoDictionaryKey: "QueepURLScheme") as? String ?? "queep"
                            context.open(URL(string: "\(scheme)://subscription?plan=max")!) { _ in }
                        }
                    }
                    if saved { Label("Salvo no Queep", systemImage: "checkmark.circle.fill") }
                    else if sending { ProgressView("Salvando…") }
                }.padding()
            }
            .navigationTitle("Salvar no Queep")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { context.completeRequest(returningItems: nil) }
                        .disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(error == nil ? "Salvar" : "Tentar novamente") { Task { await save() } }
                        .disabled(loading || sending || saved || session.preparing || session.userID == nil || incoming == nil)
                        .accessibilityIdentifier("share.save")
                }
            }
        }
        .interactiveDismissDisabled(sending)
        .task(id: "\(session.userID ?? "")/\(session.preparing)") {
            incoming = nil; error = nil
            guard !session.preparing, let owner = session.userID else { loading = false; return }
            loading = true
            defer { loading = false }
            let items = context.inputItems.compactMap { $0 as? NSExtensionItem }
            do {
                let result = try await IncomingLoader.load(items.flatMap { $0.attachments ?? [] },
                    context: items.compactMap { $0.attributedContentText?.string }.joined(separator: "\n"),
                    authorizeMedia: {
                        guard let client = session.client() else { throw QueepError.unauthorized }
                        try await client.requireMediaAccess()
                    })
                guard owner == session.userID, !Task.isCancelled else { return }
                incoming = result
            } catch { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        guard !sending, !saved, let incoming, let client = session.client(), let owner = session.userID else { return }
        sending = true; error = nil
        defer { sending = false }
        do {
            let reference = try await incoming.save(using: client)
            guard owner == session.userID else { return }
            ShareCaptureQueue.enqueue(id: reference.id, kind: ProductEvent.kind(kind: reference.kind, url: reference.url))
            saved = true
            context.completeRequest(returningItems: nil)
        } catch { self.error = error.localizedDescription }
    }
}
