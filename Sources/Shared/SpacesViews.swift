import SwiftUI
import QueepCore

struct SpacesOverview: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        #if os(macOS)
        let count = typeSize.isAccessibilitySize ? 2 : 4
        #else
        let count = typeSize.isAccessibilitySize ? 1 : 2
        #endif
        return Array(repeating: GridItem(.flexible(), spacing: Theme.gap, alignment: .top), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                // The Mac's bar already names the tab and counts the Spaces.
                #if os(iOS)
                PageTitle(text: "Spaces", detail: store.spaces.isEmpty ? nil
                          : "\(store.spaces.count) \(store.spaces.count == 1 ? "Space" : "Spaces")")
                #endif
                #if os(macOS)
                Button { store.presentation = .newSpace } label: {
                    HStack(spacing: 8) {
                        QueepIcon("ri-folder-add-line", size: 20, color: Theme.ink)
                        Text("Novo Space")
                    }
                }
                .buttonStyle(.queep(.neutral, height: Theme.control, stretches: false))
                .accessibilityIdentifier("spaces.new")
                #endif
            }
            if store.spaces.isEmpty {
                emptySpaces
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(store.spaces) { space in
                        SpaceGalleryCard(space: space)
                    }
                }
            }
            if let error = store.spaceError {
                SettingsNotice(text: error, failure: true)
            }
        }
    }

    private var emptySpaces: some View {
        EmptyState(icon: "ri-folder-6-line", title: "Seus projetos, cada um no seu Space",
                   message: "Crie Spaces e reúna as referências de cada trabalho. Uma referência pode estar em vários.") {
            Button {
                store.presentation = .newSpace
            } label: {
                HStack(spacing: 8) {
                    QueepIcon("ri-folder-add-line", size: 20, color: Theme.ink)
                    Text("Criar Space")
                }
            }
            .buttonStyle(.queep(.primary, stretches: false))
            .accessibilityIdentifier("spaces.create")
        }
    }
}

/// Pinterest-style board cover: a three-cell mosaic, then the name and a gray meta line.
private struct SpaceGalleryCard: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Session.self) private var session
    let space: Space
    @State private var fetched: [Reference] = []

    private var previews: [Reference] {
        let known = store.spaceThumbnails(space.id)
        return known.isEmpty ? Array(fetched.prefix(3)) : known
    }

    private var activityDate: Date {
        space.updatedAt
    }

    var body: some View {
        Button { store.selectSpace(space.id) } label: {
            VStack(alignment: .leading, spacing: 12) {
                SpaceMosaic(previews: previews)
                VStack(alignment: .leading, spacing: 3) {
                    Text(space.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12) {
                        Text(space.countLabel)
                        Text(SpaceBoardTime.compact(since: activityDate))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(space.name), \(space.countLabel), \(SpaceBoardTime.compact(since: activityDate))")
        .accessibilityIdentifier("spaces.open.\(space.id)")
        .task(id: "\(space.id)-\(space.referenceCount)") {
            guard space.referenceCount > 0, store.spaceThumbnails(space.id).isEmpty else { return }
            guard let api = session.client(), session.userID != nil else { return }
            guard let page = try? await api.list(spaceID: space.id, limit: 12) else { return }
            fetched = page.items
                .filter { !$0.isArchived && (!$0.gallery.isEmpty || $0.media != nil) }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                    return lhs.id > rhs.id
                }
        }
    }
}

/// Large tile on the left, two stacked tiles on the right. Missing images stay light gray.
private struct SpaceMosaic: View {
    let previews: [Reference]
    private let gap: CGFloat = 3
    private let placeholder = Theme.fill

    var body: some View {
        Color.white
            .aspectRatio(1.08, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let left = (geo.size.width - gap) * 2 / 3
                    let right = geo.size.width - gap - left
                    let top = (geo.size.height - gap) / 2
                    let bottom = geo.size.height - gap - top
                    HStack(spacing: gap) {
                        cell(previews.first)
                            .frame(width: left, height: geo.size.height)
                        VStack(spacing: gap) {
                            cell(previews.count > 1 ? previews[1] : nil)
                                .frame(width: right, height: top)
                            cell(previews.count > 2 ? previews[2] : nil)
                                .frame(width: right, height: bottom)
                        }
                        .frame(width: right)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .accessibilityHidden(true)
    }

    private func cell(_ reference: Reference?) -> some View {
        ZStack {
            placeholder
            if let reference {
                RemoteImage(reference: reference, thumbnail: true, fill: true, quiet: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// Compact Portuguese age, matching a Pinterest board’s “2 a” line.
enum SpaceBoardTime {
    static func compact(since date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "agora" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(hours) h" }
        let days = Int(seconds / 86_400)
        if days < 7 { return "\(max(days, 1)) d" }
        let weeks = days / 7
        if weeks < 52 { return "\(weeks) sem" }
        return "\(max(days / 365, 1)) a"
    }
}

struct SpaceNameSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let space: Space?
    @State private var name: String
    @FocusState private var focused: Bool

    init(space: Space? = nil) {
        self.space = space
        _name = State(initialValue: space?.name ?? "")
    }

    private var valid: Bool {
        (1...40).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                IconTile(asset: "ri-folder-add-line")
                Text(space == nil ? "Novo Space" : "Renomear Space")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 7) {
                FieldLabel(text: "Nome")
                TextField("", text: $name, prompt: Text("Ex.: Rebrand da padaria 🥐").foregroundStyle(Theme.inkFaint))
                    .focused($focused)
                    .accessibilityLabel("Nome do Space")
                    .accessibilityIdentifier("spaces.name")
                    .onSubmit { save() }
                    .queepField(focused: focused)
                Text("De 1 a 40 caracteres. Você pode usar um emoji no nome.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
            }
            if let error = store.spaceError { SettingsNotice(text: error, failure: true) }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.queep(.neutral))
                    .disabled(store.spaceMutating)
                    .keyboardShortcut(.cancelAction)
                Button(space == nil ? "Criar" : "Salvar", action: save)
                    .buttonStyle(.queepPrimary)
                    .disabled(!valid || store.spaceMutating)
                    .accessibilityIdentifier("spaces.save")
            }
        }
        .padding(24)
        .background(Theme.surface)
        .environment(\.colorScheme, .light)
        .subscriptionGate()
        .interactiveDismissDisabled(store.spaceMutating)
        .onAppear { store.spaceError = nil; focused = true }
        #if os(macOS)
        .frame(width: 440, height: 300)
        #else
        .presentationDetents([.height(340)])
        .presentationCornerRadius(Theme.radius + 10)
        #endif
    }

    private func save() {
        guard valid else { return }
        Task {
            guard let api = session.client(), let uid = session.userID else { return }
            if await store.saveSpace(api, account: uid, space: space, name: name) { dismiss() }
        }
    }
}

struct SpacePicker: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let references: [Reference]
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spaces")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(references.count == 1 ? "Marque os Spaces desta referência. As alterações são salvas na hora."
                         : "Marque para adicionar as \(references.count) referências. Desmarque para tirar todas deste Space.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Concluir") { dismiss() }
                    .buttonStyle(.queep(.primary, height: 40, stretches: false))
                    .disabled(store.spaceMutating)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("spaces.done")
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.spaces) { space in
                        row(space)
                    }
                    Button { creating = true } label: {
                        SettingsRow(icon: "ri-folder-add-line", title: "Novo Space", chevron: false)
                    }
                    .buttonStyle(SettingsRowStyle())
                    .disabled(store.spaceMutating)
                    .accessibilityIdentifier("spaces.new")
                }
                .padding(Theme.chromeInset)
                .surface(.outline, radius: Theme.radius)
            }
            .scrollIndicators(.hidden)
            if let error = store.spaceError { SettingsNotice(text: error, failure: true) }
        }
        .padding(24)
        .background(Theme.surface)
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $creating) { SpaceNameSheet() }
        .task {
            guard let api = session.client(), let uid = session.userID else { return }
            await store.refreshSpaces(api, account: uid)
        }
        .interactiveDismissDisabled(store.spaceMutating)
        #if os(macOS)
        .frame(width: 480, height: 480)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func row(_ space: Space) -> some View {
        let current = references.map { store.reference($0.id) ?? $0 }
        let count = current.filter { $0.membershipIDs.contains(space.id) }.count
        let all = count == current.count && count > 0
        return Button {
            Task {
                guard let api = session.client(), let uid = session.userID else { return }
                await store.assignSpace(space, references: current, adding: !all, client: api, account: uid)
            }
        } label: {
            HStack(spacing: 12) {
                IconTile(asset: "ri-folder-6-line")
                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(space.countLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                QueepIcon(all ? "ri-checkbox-fill" : count > 0 ? "ri-checkbox-blank-line" : "ri-checkbox-blank-line",
                          size: 22, color: all ? Theme.forest : Theme.inkFaint)
                    .overlay {
                        if count > 0 && !all {
                            RoundedRectangle(cornerRadius: 1).fill(Theme.forest).frame(width: 9, height: 2)
                        }
                    }
                    .padding(.trailing, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .disabled(store.spaceMutating)
        .accessibilityLabel(space.name)
        .accessibilityValue(all ? "Selecionado" : count > 0 ? "Parcialmente selecionado" : "Não selecionado")
        .accessibilityIdentifier("spaces.pick.\(space.id)")
    }
}

struct ReferenceSpaceButton: View {
    let reference: Reference
    @State private var picking = false
    var body: some View {
        if !reference.isArchived {
            Button("Space", systemImage: "square.stack.3d.up") { picking = true }
                .accessibilityIdentifier("reference.space")
                .sheet(isPresented: $picking) { SpacePicker(references: [reference]) }
        }
    }
}

struct CaptureSpaceChoice: View {
    @Environment(LibraryStore.self) private var store
    @Binding var selection: String?
    var body: some View {
        if !store.spaces.isEmpty {
            Picker("Salvar em…", selection: $selection) {
                Text("Nenhum Space (Tudo)").tag(String?.none)
                ForEach(store.spaces) { space in Text(space.name).tag(Optional(space.id)) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("capture.space")
        }
    }
}

struct EmptySpaceView: View {
    @Environment(LibraryStore.self) private var store
    var body: some View {
        EmptyState(icon: "ri-folder-6-line", title: "Este Space está esperando suas ideias",
                   message: "Selecione referências na Gallery e use Spaces para reuni-las aqui.") {
            Button("Abrir a Gallery") { store.showHome() }
                .buttonStyle(.queep(.primary, stretches: false))
                .accessibilityIdentifier("spaces.addFromLibrary")
        }
    }
}
