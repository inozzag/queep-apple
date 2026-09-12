import QueepCore
import SwiftUI

struct UsagePrivacyView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var usage: Usage?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Seu uso diário").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        if let usage {
                            counter("Salvamentos e novas análises", key: "operations", usage: usage)
                            counter("Áudio e vídeo para analisar", key: "media_seconds", usage: usage, divisor: 60, unit: "min")
                            counter("Arquivos enviados", key: "upload_bytes", usage: usage, divisor: 1_048_576, unit: "MiB")
                            counter("Buscas com IA", key: "searches", usage: usage)
                            Text("Renova em \(usage.resetsAt.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.callout).accessibilityIdentifier("usage.reset")
                        } else if error == nil { ProgressView("Consultando uso…") }
                        if let error {
                            Text(error).foregroundStyle(.red)
                            Button("Tentar novamente") { attempt += 1 }
                        }
                        Text("Novos itens, edições e novas tentativas de análise contam. Repetir um envio não confirmado com o mesmo conteúdo não conta de novo. Reservas de envio e buscas iniciadas podem contar mesmo se houver falha. Excluir conteúdo não devolve a cota diária.")
                            .font(.callout).foregroundStyle(Color.primary.opacity(0.8))
                        Text("Estes são limites iniciais de uso. Os planos comerciais ainda serão definidos.")
                            .font(.callout).foregroundStyle(Color.primary.opacity(0.8))
                    }
                    Divider()
                    information("Onde ficam suas referências", symbol: "icloud",
                        text: "O conteúdo enviado fica na nuvem do Queep, no Firebase/Google Cloud, para sincronizar seus dispositivos. A interpretação usa provedores de IA por meio do OpenRouter. Texto, imagens e trechos de mídia necessários à análise são enviados para esse processamento.")
                    information("Você escolhe o que enviar", symbol: "hand.raised",
                        text: "O Queep recebe o que você salva, compartilha ou captura. Ele não acompanha continuamente sua tela nem suas conversas. Links usam conteúdo público acessível; algumas redes sociais oferecem apenas informações parciais.")
                    information("Excluir e recuperar", symbol: "trash",
                        text: "Ao excluir a conta, você tem 30 dias para recuperá-la. A biblioteca fica bloqueada nesse período. Também é possível pedir a exclusão definitiva imediata. Depois da remoção, cópias de segurança dos arquivos podem permanecer por até 7 dias, sem acesso pelo app.")
                    information("Cópias no dispositivo", symbol: "internaldrive",
                        text: "A reprodução e a preparação de mídia usam arquivos temporários, removidos ao fechar o conteúdo. Se o app for interrompido, arquivos temporários antigos são limpos ao abri-lo novamente. O salvamento exige internet; só feche o envio após a confirmação.")
                }.padding(24).frame(maxWidth: 600, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("Uso e privacidade")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Fechar", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    #if os(iOS)
                    .labelStyle(.iconOnly)
                    #endif
                    .accessibilityIdentifier("usage.close")
            } }
        }
        .task(id: "\(session.userID ?? "")/\(attempt)") {
            usage = nil; error = nil
            guard let api = session.client(), let owner = session.userID else { return }
            do {
                let result = try await api.usage()
                guard !Task.isCancelled, session.userID == owner else { return }
                usage = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 660)
        #endif
    }

    @ViewBuilder private func counter(_ title: String, key: String, usage: Usage,
                                       divisor: Double = 1, unit: String = "") -> some View {
        if let counter = usage.counters[key] {
            let value = Double(counter.used) / divisor
            let limit = Double(counter.limit) / divisor
            let digits = divisor == 1 ? 0 : 1
            let description = "\(value.formatted(.number.precision(.fractionLength(0...digits)))) de \(limit.formatted()) \(unit)"
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(description).font(.callout).monospacedDigit()
                ProgressView(value: min(Double(counter.used), Double(counter.limit)), total: Double(counter.limit))
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(description)
            .accessibilityIdentifier("usage.\(key)")
        }
    }

    private func information(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline).accessibilityAddTraits(.isHeader)
            Text(text).foregroundStyle(Color.primary.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
