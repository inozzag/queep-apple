import SwiftUI
import QueepCore

struct SpacesOverview: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: GalleryStyle.gap), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
            HStack {
                Spacer(minLength: 0)
                Button { store.presentation = .newSpace } label: {
                    Label("Novo Space", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("spaces.new")
            }
            #endif
            if store.spaces.isEmpty {
                emptySpaces
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(store.spaces) { space in
                        SpaceGalleryCard(space: space)
                    }
                }
            }
            if let error = store.spaceError {
                Text(error).foregroundStyle(.red).font(.callout)
            }
        }
    }

    private var emptySpaces: some View {
        VStack(spacing: 12) {
            HomeGlyph(asset: "HomeSpaces", size: 28)
            Text("Crie e organize os seus itens em spaces inteligentes")
                .font(.system(size: 14))
                .foregroundStyle(Theme.homePreview)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center)
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
            VStack(alignment: .leading, spacing: 10) {
                SpaceMosaic(previews: previews)
                VStack(alignment: .leading, spacing: 3) {
                    Text(space.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.homeInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12) {
                        Text(space.countLabel)
                        Text(SpaceBoardTime.compact(since: activityDate))
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.homePreview)
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
    private let gap: CGFloat = 2.5
    private let placeholder = Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255)

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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Nome do Space", text: $name)
                    .textFieldStyle(.roundedBorder).focused($focused)
                    .accessibilityIdentifier("spaces.name")
                    .onSubmit { save() }
                Text("De 1 a 40 caracteres. Você pode usar um emoji no nome.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = store.spaceError { Text(error).font(.callout).foregroundStyle(.red) }
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle(space == nil ? "Novo Space" : "Renomear Space")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(store.spaceMutating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(space == nil ? "Criar" : "Salvar", action: save)
                        .disabled(!valid || store.spaceMutating)
                        .accessibilityIdentifier("spaces.save")
                }
            }
        }
        .subscriptionGate()
        .interactiveDismissDisabled(store.spaceMutating)
        .onAppear { store.spaceError = nil; focused = true }
        #if os(macOS)
        .frame(width: 440, height: 240)
        #else
        .presentationDetents([.medium])
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
        NavigationStack {
            List {
                Section {
                    ForEach(store.spaces) { space in
                        let current = references.map { store.reference($0.id) ?? $0 }
                        let count = current.filter { $0.membershipIDs.contains(space.id) }.count
                        let all = count == current.count
                        Button {
                            Task {
                                guard let api = session.client(), let uid = session.userID else { return }
                                await store.assignSpace(space, references: current, adding: !all, client: api, account: uid)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: all ? "checkmark.square.fill" : count > 0 ? "minus.square" : "square")
                                Text(space.name)
                                Spacer()
                                Text(space.countLabel).font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight: 36).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(store.spaceMutating)
                        .accessibilityLabel(space.name)
                        .accessibilityValue(all ? "Selecionado" : count > 0 ? "Parcialmente selecionado" : "Não selecionado")
                        .accessibilityIdentifier("spaces.pick.\(space.id)")
                    }
                    Button("Novo Space", systemImage: "plus") { creating = true }
                        .disabled(store.spaceMutating).accessibilityIdentifier("spaces.new")
                } footer: {
                    Text(references.count == 1 ? "Marque os Spaces desta referência. As alterações são salvas imediatamente."
                         : "Marque para adicionar todas as referências. Desmarque para remover todas deste Space.")
                }
                if let error = store.spaceError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Spaces")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Concluir") { dismiss() }.disabled(store.spaceMutating).accessibilityIdentifier("spaces.done")
            } }
        }
        .sheet(isPresented: $creating) { SpaceNameSheet() }
        .task {
            guard let api = session.client(), let uid = session.userID else { return }
            await store.refreshSpaces(api, account: uid)
        }
        .interactiveDismissDisabled(store.spaceMutating)
        #if os(macOS)
        .frame(width: 480, height: 440)
        #endif
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
        ContentUnavailableView {
            Label("Este Space está esperando suas ideias", systemImage: "square.stack.3d.up")
        } description: {
            Text("Selecione referências da biblioteca e use Space para reuni-las aqui.")
        } actions: {
            Button("Adicionar da biblioteca") { store.showHome() }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("spaces.addFromLibrary")
        }
    }
}
