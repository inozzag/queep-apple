import SwiftUI
import QueepCore

struct SpaceNavigation: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tab("Tudo", count: nil, id: nil)
                ForEach(store.spaces) { space in tab(space.name, count: space.countLabel, id: space.id) }
                Button { store.presentation = .newSpace } label: {
                    Label("Novo Space", systemImage: "plus")
                        .padding(.horizontal, 14).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("spaces.new")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces da biblioteca")
    }

    private func tab(_ name: String, count: String?, id: String?) -> some View {
        let selected = store.selectedSpaceID == id
        return Button { store.selectSpace(id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.callout.weight(selected ? .semibold : .regular)).lineLimit(1)
                if let count { Text(count).font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(name), \($0)" } ?? name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id.map { "spaces.tab.\($0)" } ?? "spaces.all")
    }
}

struct SpacesOverview: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Session.self) private var session
    @State private var editing: Space?
    @State private var deleting: Space?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Spaces").font(.title.bold())
                Spacer()
                Button("Novo Space", systemImage: "plus") { store.presentation = .newSpace }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("spaces.new")
            }
            Text("Organize referências de clientes, projetos e ideias. Uma referência pode estar em vários Spaces.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Tudo", systemImage: "square.grid.2x2") { store.selectSpace(nil) }
                .accessibilityIdentifier("spaces.all")
            if store.spaces.isEmpty {
                ContentUnavailableView("Suas ideias, organizadas", systemImage: "square.stack.3d.up",
                    description: Text("Crie seu primeiro Space para reunir referências. Disponível a partir do Queep Pro."))
            }
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, space in
                HStack {
                    Button { store.selectSpace(space.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(space.name).font(.headline)
                                Text(space.countLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("spaces.open.\(space.id)")
                    Menu {
                        Button("Renomear", systemImage: "pencil") { editing = space }
                        Button("Mover para cima", systemImage: "arrow.up") { reorder(space, to: index - 1) }
                            .disabled(index == 0)
                        Button("Mover para baixo", systemImage: "arrow.down") { reorder(space, to: index + 1) }
                            .disabled(index == store.spaces.count - 1)
                        Divider()
                        Button("Excluir Space…", systemImage: "trash", role: .destructive) { deleting = space }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Opções de \(space.name)")
                    .disabled(store.spaceMutating)
                }.card(padding: 14, elevated: false)
            }
            if let error = store.spaceError { Text(error).foregroundStyle(.red).font(.callout) }
        }
        .sheet(item: $editing) { SpaceNameSheet(space: $0) }
        .confirmationDialog("Excluir Space?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { space in
            Button("Excluir Space", role: .destructive) {
                Task {
                    guard let api = session.client(), let uid = session.userID else { return }
                    await store.deleteSpace(space, client: api, account: uid)
                }
            }
        } message: { _ in Text("As referências não serão apagadas. Elas continuam em Tudo e nos outros Spaces.") }
    }

    private func reorder(_ space: Space, to index: Int) {
        Task {
            guard let api = session.client(), let uid = session.userID else { return }
            _ = await store.saveSpace(api, account: uid, space: space, sortIndex: index)
        }
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
            Button("Adicionar da biblioteca") { store.selectSpace(nil) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("spaces.addFromLibrary")
        }
    }
}
