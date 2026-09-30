import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QueepCore

enum OnboardingProgress {
    static func isComplete(_ uid: String?) -> Bool {
        guard let uid else { return false }
        return UserDefaults.standard.bool(forKey: completeKey(uid))
    }

    static func markComplete(_ uid: String) {
        UserDefaults.standard.set(true, forKey: completeKey(uid))
        UserDefaults.standard.removeObject(forKey: draftKey(uid))
    }

    static func paywallShown(_ uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: paywallKey(uid))
    }

    static func markPaywallShown(_ uid: String) {
        UserDefaults.standard.set(true, forKey: paywallKey(uid))
    }

    fileprivate static func draft(_ uid: String) -> Draft? {
        guard let data = UserDefaults.standard.data(forKey: draftKey(uid)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    fileprivate static func save(_ draft: Draft, uid: String) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: draftKey(uid))
    }

    private static func completeKey(_ uid: String) -> String { "queep.onboarding.complete.\(uid)" }
    private static func paywallKey(_ uid: String) -> String { "queep.paywall.first.\(uid)" }
    private static func draftKey(_ uid: String) -> String { "queep.onboarding.draft.\(uid)" }

    fileprivate struct Draft: Codable {
        var phone: String
        var source: String?
        var work: String?
        var step: Int
    }
}

/// Data, then a short demonstration, then the first real save.
struct OnboardingFlow: View {
    var onComplete: () -> Void
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var step: Step = .phone
    @State private var phone = ""
    @State private var source: String?
    @State private var work: String?
    @State private var link = ""
    @State private var showLink = false
    @State private var busy = false
    @State private var captured = false
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var filePicker = false
    @FocusState private var phoneFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    stepBody
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .accessibilityIdentifier("onboarding.error")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if step != .action { footer }
        }
        .background(Color.white)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
        .onAppear(perform: restore)
        .onChange(of: step) { _, _ in persist() }
        .onChange(of: phone) { _, _ in persist() }
        .onChange(of: source) { _, _ in persist() }
        .onChange(of: work) { _, _ in persist() }
        .onChange(of: photo) { _, selection in
            guard let selection else { return }
            Task { await importPhoto(selection) }
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.jpeg, .png, .heic, .heif]) { result in
            guard case .success(let url) = result else { return }
            Task { await importFile(url) }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack {
                if step == .phone {
                    Color.clear.frame(width: 44, height: 44)
                } else {
                    Button { back() } label: {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voltar")
                    .accessibilityIdentifier("onboarding.back")
                    .disabled(busy)
                }
                Spacer()
                if step.isDemo {
                    Button("Pular") { step = .action }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.homePreview)
                        .accessibilityIdentifier("onboarding.skip")
                        .disabled(busy)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.homeLine)
                    Capsule().fill(Theme.homeInk)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .accessibilityLabel("Passo \(step.rawValue + 1) de \(Step.allCases.count)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var progress: CGFloat {
        CGFloat(step.rawValue + 1) / CGFloat(Step.allCases.count)
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if step.isData {
                Text("Seus dados").font(.footnote.weight(.medium)).foregroundStyle(Theme.homePreview)
            }
            Text(step.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.homeInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(step == .promise ? "onboarding.promise" : "onboarding.step")
            if let detail = step.detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(Theme.homePreview)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var stepBody: some View {
        switch step {
        case .phone:
            TextField("Telefone", text: $phone)
                .font(.title3)
                .textContentType(.telephoneNumber)
                .focused($phoneFocused)
                #if os(iOS)
                .keyboardType(.phonePad)
                #endif
                .padding(16)
                .background(Theme.homeFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.homeLine))
                .accessibilityIdentifier("onboarding.phone")
                .onAppear { phoneFocused = true }
        case .source:
            choices(sourceOptions, selection: source) { source = $0 }
        case .work:
            choices(workOptions, selection: work) { work = $0 }
        case .promise:
            QueepLogo(size: 72)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        case .share:
            VStack(spacing: 12) {
                explain("photo.on.rectangle", "Galeria", "Manda uma foto sem sair do app de Fotos.")
                explain("square.and.arrow.up", "Rede social", "No Instagram, no X ou em outra rede, toque em Compartilhar e escolha Queep.")
                explain("safari", "Navegador", "No Safari, compartilhe a página. O Queep lê o que é público.")
            }
        case .search:
            Text("“interfaces claras de CRM”")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.homeInk)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.homeFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .spaces:
            explain("square.stack.3d.up", "Um grupo para cada contexto", "Trabalho, referências e ideias ficam juntos. Você acha o conjunto, não um arquivo perdido.")
        case .action:
            actionBody
        }
    }

    private var actionBody: some View {
        VStack(spacing: 12) {
            if captured {
                Button { Task { await finish() } } label: {
                    Text(busy ? "Salvando…" : "Continuar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPrimaryButton())
                .disabled(busy)
            } else {
                galleryButton
                Button { showLink.toggle() } label: {
                    actionLabel("link", "Colar um link", showLink ? "O campo está aberto abaixo" : "De uma rede social")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.social")
                .disabled(busy)
                if showLink {
                    TextField("instagram.com/…", text: $link)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .padding(16)
                        .background(Theme.homeFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityIdentifier("onboarding.link")
                    Button { Task { await saveLink() } } label: {
                        Text(busy ? "Salvando…" : "Salvar link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingPrimaryButton())
                    .disabled(busy || OnboardingAnswers.link(link) == nil)
                    .accessibilityIdentifier("onboarding.saveLink")
                }
                Button("Agora não") { Task { await finish() } }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.homePreview)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .disabled(busy)
                    .accessibilityIdentifier("onboarding.later")
            }
        }
    }

    @ViewBuilder private var galleryButton: some View {
        #if os(iOS)
        PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) {
            actionLabel("photo.on.rectangle", "Abrir a galeria", "Escolha uma imagem")
        }
        .disabled(busy)
        .accessibilityIdentifier("onboarding.gallery")
        #else
        Button { filePicker = true } label: {
            actionLabel("photo.on.rectangle", "Abrir a galeria", "Escolha uma imagem")
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("onboarding.gallery")
        #endif
    }

    private var footer: some View {
        Button { advance() } label: {
            Text(busy ? "Salvando…" : "Continuar")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(OnboardingPrimaryButton())
        .disabled(!canContinue || busy)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .accessibilityIdentifier("onboarding.continue")
    }

    private var canContinue: Bool {
        switch step {
        case .phone: OnboardingAnswers.phone(phone) != nil
        case .source: source != nil
        case .work: work != nil
        case .promise, .share, .search, .spaces: true
        case .action: false
        }
    }

    private func choices(_ options: [(String, String)], selection: String?, choose: @escaping (String) -> Void) -> some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.0) { option in
                Button { choose(option.0) } label: {
                    HStack {
                        Text(option.1).font(.body.weight(.semibold)).foregroundStyle(Theme.homeInk)
                        Spacer()
                        if selection == option.0 {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.homeInk)
                        }
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selection == option.0 ? Theme.homeInk : Theme.homeLine, lineWidth: selection == option.0 ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.choice.\(option.0)")
            }
        }
    }

    private func explain(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.homeInk)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Theme.homeInk)
                Text(text).font(.callout).foregroundStyle(Theme.homePreview)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.homeFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actionLabel(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(Theme.homePreview)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.homePreview)
        }
        .foregroundStyle(Theme.homeInk)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.homeInk, lineWidth: 1.5))
    }

    private func advance() {
        guard canContinue, let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeOut(duration: 0.2)) { step = next }
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeOut(duration: 0.2)) { step = previous }
    }

    private func restore() {
        guard let uid = session.userID, let draft = OnboardingProgress.draft(uid) else { return }
        phone = draft.phone
        source = draft.source
        work = draft.work
        if let restored = Step(rawValue: draft.step) { step = restored }
    }

    private func persist() {
        guard let uid = session.userID else { return }
        OnboardingProgress.save(.init(phone: phone, source: source, work: work, step: step.rawValue), uid: uid)
    }

    private func importPhoto(_ selection: PhotosPickerItem) async {
        busy = true
        error = nil
        do {
            guard let image = try await selection.loadTransferable(type: ImportedImage.self) else {
                throw QueepError.server("Não foi possível abrir esta foto.")
            }
            try await upload(image)
        } catch {
            busy = false
            self.error = "Não foi possível abrir esta foto. Tente outra."
            return
        }
        busy = false
        await finish()
    }

    private func importFile(_ url: URL) async {
        busy = true
        error = nil
        do {
            let image = try await Task.detached(priority: .userInitiated) { try ImportedImage.prepare(url: url) }.value
            try await upload(image)
        } catch {
            busy = false
            self.error = "Não foi possível abrir esta imagem. Tente outra."
            return
        }
        busy = false
        await finish()
    }

    private func upload(_ image: ImportedImage) async throws {
        guard let api = session.client(), let uid = session.userID else { return }
        let saved = try await api.uploadImage(id: UUID(), title: "", data: image.data)
        ProductAnalytics.captureSaved(kind: saved.kind, url: saved.url, source: "library")
        guard session.userID == uid else { return }
        await store.refresh(api, account: uid)
        captured = true
    }

    private func saveLink() async {
        guard let api = session.client(), let uid = session.userID, let url = OnboardingAnswers.link(link) else { return }
        busy = true
        error = nil
        do {
            let saved = try await api.create(id: UUID(), capture: Capture(kind: "link", title: "", text: "", url: url))
            ProductAnalytics.captureSaved(kind: saved.kind, url: saved.url, source: "library")
            guard session.userID == uid else { return }
            await store.refresh(api, account: uid)
            captured = true
        } catch {
            busy = false
            self.error = "Não foi possível salvar esse link. Confira o endereço e tente de novo."
            return
        }
        busy = false
        await finish()
    }

    private func finish() async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await finishSaving() }
        catch { self.error = "Não foi possível guardar seus dados. Tente novamente." }
    }

    private func finishSaving() async throws {
        guard let api = session.client(), let uid = session.userID,
              let source, let work else {
            throw QueepError.server("Faltam o telefone ou as respostas.")
        }
        try await api.saveOnboarding(phone: phone, source: source, work: work)
        guard session.userID == uid else { return }
        OnboardingProgress.markComplete(uid)
        onComplete()
    }

    private var sourceOptions: [(String, String)] {
        [("anuncio", "Anúncio"), ("twitter", "Twitter"), ("instagram", "Instagram"),
         ("amigo", "Amigo"), ("ai_chat", "AI Chat")]
    }

    private var workOptions: [(String, String)] {
        [("marketing", "Marketing"), ("design", "Design"), ("produto", "Produto"),
         ("conteudo", "Conteúdo"), ("educacao", "Educação"), ("outro", "Outro")]
    }

    private enum Step: Int, CaseIterable {
        case phone, source, work, promise, share, search, spaces, action

        var isData: Bool { self == .phone || self == .source || self == .work }
        var isDemo: Bool { self == .promise || self == .share || self == .search || self == .spaces }

        var title: String {
            switch self {
            case .phone: "Qual é o seu telefone?"
            case .source: "Como você conheceu o Queep?"
            case .work: "Com o que você trabalha?"
            case .promise: "Salve horas do seu dia"
            case .share: "Salve de onde você já está"
            case .search: "Pesquisa que entende o que você lembra"
            case .spaces: "Spaces separam o que importa"
            case .action: "Salve seu primeiro item"
            }
        }

        var detail: String? {
            switch self {
            case .phone: "Fica salvo na sua conta."
            case .source, .work: nil
            case .promise: "Encontrando fácil tudo que você salva."
            case .share: "Três jeitos de mandar uma referência para o Queep."
            case .search: "Descreva o assunto, o nome ou a aparência."
            case .spaces: nil
            case .action: "Uma imagem da galeria ou um link. Depois disso, a biblioteca é sua."
            }
        }
    }
}

struct OnboardingPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .background(Theme.homeInk.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
