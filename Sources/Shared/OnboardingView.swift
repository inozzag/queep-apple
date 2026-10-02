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
        var workDetail: String?
        var step: Int
    }
}

/// Data, then a short demonstration, then the first real save.
struct OnboardingFlow: View {
    var onComplete: () -> Void
    @Environment(Session.self) private var session
    @Environment(LibraryStore.self) private var store
    @State private var step: Step = .welcome
    @State private var phoneCountry = PhoneNumber.deviceCountry
    @State private var phoneDigits = ""
    @State private var countryQuery = ""
    @State private var showCountries = false
    @State private var source: String?
    @State private var work: String?
    @State private var workDetail = ""
    @FocusState private var workFocused: Bool
    @State private var link = ""
    @State private var showLink = false
    @State private var busy = false
    @State private var captured = false
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var filePicker = false
    @FocusState private var phoneFocused: Bool

    var body: some View {
        Group {
            if step == .welcome { welcome }
            else { question }
        }
        .background(Color.white)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
        .onAppear(perform: restore)
        .onChange(of: step) { _, _ in persist() }
        .onChange(of: phoneDigits) { _, _ in persist() }
        .onChange(of: phoneCountry) { _, _ in persist() }
        .sheet(isPresented: $showCountries) { countrySheet }
        .onChange(of: source) { _, _ in persist() }
        .onChange(of: work) { _, _ in persist() }
        .onChange(of: workDetail) { _, _ in persist() }
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

    private var welcome: some View {
        ZStack(alignment: .bottom) {
            OnboardingWelcome()
            VStack(spacing: 16) {
                HStack(spacing: 7) {
                    Circle().fill(Theme.homeInk).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 0.82, green: 0.82, blue: 0.84)).frame(width: 7, height: 7)
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var question: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 22) {
                    header
                    stepBody
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("onboarding.error")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            if step != .action { footer }
        }
    }

    private var topBar: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(Step.questions, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Theme.homeInk : Color(red: 0.90, green: 0.90, blue: 0.91))
                        .frame(height: 5)
                }
            }
            .accessibilityLabel("Passo \(step.rawValue) de \(Step.questions.count)")
            .padding(.top, 8)
            HStack {
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .foregroundStyle(Theme.homeInk)
                        .frame(width: 44, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voltar")
                .accessibilityIdentifier("onboarding.back")
                .disabled(busy)
                Spacer()
                if step.isDemo {
                    Button("Pular") { step = .action }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.homePreview)
                        .accessibilityIdentifier("onboarding.skip")
                        .disabled(busy)
                } else {
                    Color.clear.frame(width: 44, height: 36)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var header: some View {
        VStack(spacing: 10) {
            Text(step.kicker)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.homeInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(Color(red: 0.86, green: 0.86, blue: 0.88)))
            Text(step.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.homeInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(step == .promise ? "onboarding.promise" : "onboarding.step")
            if let detail = step.detail {
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.homePreview)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var stepBody: some View {
        switch step {
        case .welcome:
            EmptyView()
        case .phone:
            phoneField
        case .source:
            choices(sourceOptions, selection: source) { source = $0 }
        case .work:
            VStack(spacing: 16) {
                choices(workOptions, selection: work) { picked in
                    work = picked
                    if picked == "outro" { workFocused = true }
                }
                if work == "outro" {
                    TextField("Digite sua profissão", text: $workDetail)
                        .font(.system(size: 17, weight: .medium))
                        .focused($workFocused)
                        .submitLabel(.done)
                        .padding(16)
                        .background(Theme.homeFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.homeLine))
                        .accessibilityIdentifier("onboarding.work.other")
                        .onChange(of: workDetail) { _, value in
                            if value.count > 40 { workDetail = String(value.prefix(40)) }
                        }
                    Text("Se a sua não está na lista, escreva aqui.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.homePreview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
        case .promise:
            OnboardingInboundAnimation()
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .padding(.top, 8)
        case .share:
            OnboardingSavePaths()
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
        Button { showPhotos = true } label: {
            actionLabel("photo.on.rectangle", "Abrir a galeria", "Escolha uma imagem")
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images, preferredItemEncoding: .current)
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
        case .welcome: true
        case .phone: PhoneNumber.e164(national: phoneDigits, country: phoneCountry) != nil
        case .source: source != nil
        case .work: work == "outro" ? OnboardingAnswers.workDetail(workDetail) != nil : work != nil
        case .promise, .share, .search, .spaces: true
        case .action: false
        }
    }

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Button { showCountries = true } label: {
                    HStack(spacing: 6) {
                        Text(phoneCountry.flag).font(.system(size: 22))
                        Text(phoneCountry.dialLabel)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.homeInk)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.homePreview)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("País, \(phoneCountry.name), \(phoneCountry.dialLabel)")
                .accessibilityIdentifier("onboarding.phone.country")
                Rectangle()
                    .fill(Theme.homeLine)
                    .frame(width: 1, height: 22)
                TextField(phoneCountry.iso == "BR" ? "(11) 98888-7777" : "Número", text: Binding(
                    get: { PhoneNumber.format(national: phoneDigits, country: phoneCountry) },
                    set: { phoneDigits = PhoneNumber.nationalDigits($0, country: phoneCountry) }
                ))
                .font(.system(size: 17, weight: .medium))
                .textContentType(.telephoneNumber)
                .focused($phoneFocused)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .padding(.horizontal, 12)
                .accessibilityIdentifier("onboarding.phone")
            }
            .frame(height: 56)
            .background(Theme.homeFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.homeLine))
            .onAppear { phoneFocused = true }
            Text(phoneHint)
                .font(.system(size: 13))
                .foregroundStyle(phoneHintIsError ? Color(red: 0.70, green: 0.16, blue: 0.14) : Theme.homePreview)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private var phoneHint: String {
        if phoneCountry.iso == "BR" {
            if phoneDigits.count >= 2, !PhoneNumber.areaCodeIsKnown(String(phoneDigits.prefix(2))) {
                return "Esse DDD não existe."
            }
            if PhoneNumber.e164(national: phoneDigits, country: phoneCountry) != nil {
                return "Fica salvo como \(phoneCountry.dialLabel) \(PhoneNumber.format(national: phoneDigits, country: phoneCountry))."
            }
            if phoneDigits.count >= 8 {
                return "Confira o DDD e complete o número."
            }
            return "DDI \(phoneCountry.dialLabel), DDD e o número. Exemplo: (11) 98888-7777"
        }
        if PhoneNumber.e164(national: phoneDigits, country: phoneCountry) != nil {
            return "Fica salvo como \(phoneCountry.dialLabel) \(PhoneNumber.format(national: phoneDigits, country: phoneCountry))."
        }
        if phoneDigits.count >= phoneCountry.nationalRange.lowerBound {
            return "Esse número não fecha para \(phoneCountry.name)."
        }
        return "DDI \(phoneCountry.dialLabel) e o número, sem o código do país."
    }

    private var phoneHintIsError: Bool {
        if phoneCountry.iso == "BR", phoneDigits.count >= 2,
           !PhoneNumber.areaCodeIsKnown(String(phoneDigits.prefix(2))) { return true }
        if phoneDigits.count >= phoneCountry.nationalRange.lowerBound,
           PhoneNumber.e164(national: phoneDigits, country: phoneCountry) == nil { return true }
        return phoneCountry.iso == "BR" && phoneDigits.count >= 8
            && PhoneNumber.e164(national: phoneDigits, country: phoneCountry) == nil
    }

    private var countrySheet: some View {
        NavigationStack {
            List(filteredCountries) { country in
                Button {
                    phoneCountry = country
                    phoneDigits = PhoneNumber.nationalDigits(phoneDigits, country: country)
                    showCountries = false
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag).font(.title3)
                        Text(country.name).foregroundStyle(Theme.homeInk)
                        Spacer()
                        Text(country.dialLabel)
                            .foregroundStyle(Theme.homePreview)
                        if country.iso == phoneCountry.iso {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.homeInk)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $countryQuery, prompt: "Buscar país")
            .navigationTitle("País")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { showCountries = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filteredCountries: [PhoneCountry] {
        let query = countryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return PhoneNumber.countries }
        return PhoneNumber.countries.filter {
            $0.name.localizedStandardContains(query)
                || $0.dial.contains(query.filter(\.isNumber))
                || $0.iso.localizedStandardContains(query)
        }
    }

    private func choices(_ options: [(String, String)], selection: String?, choose: @escaping (String) -> Void) -> some View {
        let rows = stride(from: 0, to: options.count, by: 2).map { Array(options[$0..<min($0 + 2, options.count)]) }
        return VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.0) { option in
                        let selected = selection == option.0
                        Button { choose(option.0) } label: {
                            Text(selected ? option.1 : "+  \(option.1)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(selected ? Color.white : Theme.homeInk)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(selected ? Theme.homeInk : Color.white, in: Capsule())
                                .overlay(Capsule().strokeBorder(selected ? Theme.homeInk : Color(red: 0.86, green: 0.86, blue: 0.88)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding.choice.\(option.0)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
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
        let parsed = PhoneNumber.parts(from: draft.phone)
        phoneCountry = parsed.0
        phoneDigits = parsed.1
        source = draft.source
        work = draft.work
        workDetail = draft.workDetail ?? ""
        if let restored = Step(rawValue: draft.step) { step = restored }
    }

    private func persist() {
        guard let uid = session.userID else { return }
        OnboardingProgress.save(.init(phone: "\(phoneCountry.iso)|\(phoneDigits)", source: source, work: work, workDetail: workDetail, step: step.rawValue), uid: uid)
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
              let phone = PhoneNumber.e164(national: phoneDigits, country: phoneCountry),
              let source, let work else {
            throw QueepError.server("Faltam o telefone ou as respostas.")
        }
        try await api.saveOnboarding(phone: phone, source: source, work: work,
                                     workDetail: work == "outro" ? workDetail : nil)
        guard session.userID == uid else { return }
        OnboardingProgress.markComplete(uid)
        onComplete()
    }

    private var sourceOptions: [(String, String)] {
        [("anuncio", "Anúncio"), ("instagram", "Instagram"), ("tiktok", "TikTok"),
         ("twitter", "Twitter"), ("youtube", "YouTube"), ("google", "Google"),
         ("linkedin", "LinkedIn"), ("amigo", "Amigo"), ("ai_chat", "AI Chat"),
         ("podcast", "Podcast"), ("app_store", "App Store")]
    }

    private var workOptions: [(String, String)] {
        [("design", "Design"), ("marketing", "Marketing"), ("conteudo", "Conteúdo"),
         ("social", "Social media"), ("fotografia", "Fotografia"), ("publicidade", "Publicidade"),
         ("produto", "Produto"), ("empreendedor", "Empreendedor"), ("educacao", "Educação"),
         ("outro", "Outro")]
    }

    private enum Step: Int, CaseIterable {
        case welcome, phone, source, work, promise, share, search, spaces, action

        static var questions: [Step] { allCases.filter { $0 != .welcome } }

        var isData: Bool { self == .phone || self == .source || self == .work }
        var isDemo: Bool { self == .promise || self == .share || self == .search || self == .spaces }

        var kicker: String {
            if isData { return "Seus dados" }
            if isDemo { return "Como funciona" }
            return "Primeiro save"
        }

        var title: String {
            switch self {
            case .welcome: "Salve horas do seu dia"
            case .phone: "Qual é o seu telefone?"
            case .source: "Como você conheceu o Queep?"
            case .work: "Com o que você trabalha?"
            case .promise: "Tudo que você salva, num lugar só"
            case .share: "Salve de onde você já está"
            case .search: "Pesquisa que entende o que você lembra"
            case .spaces: "Spaces separam o que importa"
            case .action: "Salve seu primeiro item"
            }
        }

        var detail: String? {
            switch self {
            case .welcome: "Encontre fácil tudo que você guarda. Da galeria, da rede social ou do navegador."
            case .phone: "Fica salvo na sua conta."
            case .source: "Escolha por onde chegou até aqui."
            case .work: "Escolha a que mais combina. Se não estiver aqui, use Outro."
            case .promise: "Instagram, X, Pinterest e as outras. Tudo entra no Queep."
            case .share: "Três jeitos de mandar uma referência para o Queep."
            case .search: "Descreva o assunto, o nome ou a aparência."
            case .spaces: "Trabalho, referências e ideias ficam juntos."
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
            .background(Theme.homeInk.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Networks around the mark. Each one sends a saved item into Queep, then the next.
private struct OnboardingInboundAnimation: View {
    private struct Item {
        let asset: String
        let title: String
    }

    private let items = [
        Item(asset: "BrandInstagram", title: "Foto"),
        Item(asset: "BrandTwitter", title: "Post"),
        Item(asset: "BrandPinterest", title: "Pin"),
        Item(asset: "BrandDribbble", title: "Shot"),
        Item(asset: "BrandMedium", title: "Artigo")
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let cycle = 1.65
            let elapsed = context.date.timeIntervalSince(started)
            let span = cycle * Double(items.count)
            let phase = elapsed.truncatingRemainder(dividingBy: span)
            let index = Int(phase / cycle) % items.count
            let local = phase.truncatingRemainder(dividingBy: cycle) / cycle
            stage(index: index, local: local)
        }
        .onAppear { started = Date() }
        .accessibilityHidden(true)
    }

    private func stage(index: Int, local: Double) -> some View {
        let travel = travelAmount(local)
        let origin = point(for: index)
        return ZStack {
            Circle()
                .stroke(Theme.homeLine, lineWidth: 1)
                .frame(width: 236, height: 236)
            ForEach(items.indices, id: \.self) { slot in
                let spot = point(for: slot)
                Image(items[slot].asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .padding(10)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().strokeBorder(slot == index ? Theme.homeInk : Theme.homeLine, lineWidth: slot == index ? 1.5 : 1))
                    .scaleEffect(slot == index ? 1.06 : 1)
                    .offset(spot)
            }
            QueepLogo(size: 42)
                .frame(width: 86, height: 86)
                .background(Color.white, in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                .scaleEffect(travel > 0.82 ? 1.08 : 1)
            if !reduceMotion {
                pill(items[index])
                    .offset(x: origin.width * (1 - travel), y: origin.height * (1 - travel))
                    .scaleEffect(1 - travel * 0.72)
                    .opacity(pillOpacity(local))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pill(_ item: Item) -> some View {
        HStack(spacing: 8) {
            Image(item.asset)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.homeInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.homeLine))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func point(for index: Int) -> CGSize {
        let angle = (Double(index) / Double(items.count)) * 2 * .pi - .pi / 2
        let radius = 118.0
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }

    /// 0 at the network, 1 inside the mark.
    private func travelAmount(_ local: Double) -> CGFloat {
        let start = 0.14
        let end = 0.78
        guard local > start else { return 0 }
        guard local < end else { return 1 }
        let unit = (local - start) / (end - start)
        return CGFloat(unit * unit * (3 - 2 * unit))
    }

    private func pillOpacity(_ local: Double) -> Double {
        if reduceMotion { return 0 }
        if local < 0.08 { return local / 0.08 }
        if local > 0.84 { return max(0, 1 - (local - 0.84) / 0.1) }
        return 1
    }
}

/// The three save paths, drawn with the library tile and the network marks.
private struct OnboardingSavePaths: View {
    var body: some View {
        VStack(spacing: 12) {
            path(title: "Galeria", text: "Manda uma foto sem sair do app de Fotos.") {
                KindTile(symbol: "photo", size: 48)
            }
            path(title: "Rede social", text: "No Instagram, no X ou em outra rede, toque em Compartilhar e escolha Queep.") {
                HStack(spacing: -12) {
                    ForEach([LinkSurface.instagram, .twitter, .pinterest], id: \.self) { surface in
                        PostBrandMark(surface: surface, size: 40, radius: 12)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(GalleryStyle.fill, lineWidth: 2)
                            }
                    }
                }
            }
            path(title: "Navegador", text: "No Safari, compartilhe a página. O Queep lê o que é público.") {
                PostBrandMark(surface: .website, size: 48, radius: 14)
            }
        }
    }

    private func path<Mark: View>(title: String, text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(alignment: .center, spacing: 14) {
            mark()
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: GalleryStyle.tileTitle, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(GalleryStyle.ink)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GalleryStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GalleryStyle.fill)
        .galleryTile()
    }
}

private struct OnboardingWelcome: View {
    var body: some View {
        GeometryReader { proxy in
            let collageHeight = proxy.size.height * 0.52
            ZStack(alignment: .top) {
                OnboardingCollage()
                    .frame(height: collageHeight + 80)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .offset(y: -48)
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0.30),
                        .init(color: .white.opacity(0.35), location: 0.38),
                        .init(color: .white, location: 0.48),
                        .init(color: .white, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: 0) {
                    Spacer().frame(height: proxy.size.height * 0.36)
                    QueepLogo(size: 34)
                        .frame(width: 78, height: 78)
                        .background(Color.white, in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                    Text("Salve horas do seu dia")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.homeInk)
                        .multilineTextAlignment(.center)
                        .padding(.top, 18)
                        .accessibilityIdentifier("onboarding.welcome")
                    Text("Encontre fácil tudo que você guarda. Da galeria, da rede social ou do navegador.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.homePreview)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .padding(.horizontal, 36)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 120)
            }
        }
    }
}

private struct OnboardingCollage: View {
    private struct Cover: Identifiable {
        let id = UUID()
        var title: String
        var kicker: String
        var top: Color
        var bottom: Color
        var height: CGFloat
        var ink: Color = .white
    }

    private let columns: [[Cover]] = [
        [
            Cover(title: "Campanha\nde verão", kicker: "Instagram", top: Color(red: 0.96, green: 0.45, blue: 0.28), bottom: Color(red: 0.72, green: 0.16, blue: 0.18), height: 168),
            Cover(title: "Print\nda home", kicker: "Galeria", top: Color(red: 0.18, green: 0.45, blue: 0.82), bottom: Color(red: 0.08, green: 0.22, blue: 0.48), height: 142),
            Cover(title: "Paleta\nde marca", kicker: "Design", top: Color(red: 0.95, green: 0.78, blue: 0.42), bottom: Color(red: 0.86, green: 0.48, blue: 0.18), height: 128)
        ],
        [
            Cover(title: "Artigo\nsalvo", kicker: "Safari", top: Color(red: 0.93, green: 0.93, blue: 0.90), bottom: Color(red: 0.78, green: 0.76, blue: 0.70), height: 150, ink: Color(red: 0.16, green: 0.15, blue: 0.13)),
            Cover(title: "Thread\ndo lançamento", kicker: "Twitter", top: Color(red: 0.12, green: 0.12, blue: 0.13), bottom: Color(red: 0.28, green: 0.28, blue: 0.30), height: 176),
            Cover(title: "Nota\nde reunião", kicker: "Nota", top: Color(red: 0.98, green: 0.96, blue: 0.90), bottom: Color(red: 0.90, green: 0.84, blue: 0.62), height: 136, ink: Color(red: 0.22, green: 0.18, blue: 0.12))
        ],
        [
            Cover(title: "Referência\nde UI", kicker: "Space", top: Color(red: 0.36, green: 0.62, blue: 0.46), bottom: Color(red: 0.12, green: 0.32, blue: 0.24), height: 158),
            Cover(title: "Landing\nnova", kicker: "Link", top: Color(red: 0.55, green: 0.36, blue: 0.78), bottom: Color(red: 0.28, green: 0.14, blue: 0.48), height: 148),
            Cover(title: "Story\ndo produto", kicker: "Galeria", top: Color(red: 0.93, green: 0.55, blue: 0.62), bottom: Color(red: 0.72, green: 0.24, blue: 0.38), height: 132)
        ]
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            column(columns[0], offset: 18)
            column(columns[1], offset: -26)
            column(columns[2], offset: 8)
        }
        .padding(.horizontal, 10)
    }

    private func column(_ covers: [Cover], offset: CGFloat) -> some View {
        VStack(spacing: 8) {
            ForEach(covers) { cover in
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [cover.top, cover.bottom], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cover.kicker.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                        Text(cover.title)
                            .font(.system(size: 16, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(cover.ink)
                    .padding(12)
                }
                .frame(maxWidth: .infinity)
                .frame(height: cover.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .offset(y: offset)
    }
}
