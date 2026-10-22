import QueepCore
import SwiftUI

struct UsagePrivacyView: View {
    /// Pushed inside Ajustes. Back returns to that list; the close button still dismisses the sheet.
    var pushedInSettings = false
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @State private var usage: Usage?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if pushedInSettings {
                detail
            } else {
                NavigationStack { detail }
                    #if os(macOS)
                    .frame(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 680)
                    #endif
            }
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
    }

    private var detail: some View {
        SettingsPage(title: "Uso e privacidade",
                     subtitle: usage.map { "Plano Queep \($0.plan.title)" },
                     closeIdentifier: "usage.close",
                     close: close) {
            SettingsSection(title: "Seu uso mensal") {
                if let usage {
                    VStack(spacing: 6) {
                        counter("Salvamentos e novas análises", icon: "ri-sparkling-2-line", key: "operations", usage: usage)
                        counter("Áudio e vídeo para analisar", icon: "ri-voiceprint-line", key: "media_seconds",
                                usage: usage, divisor: 60, unit: "min")
                        counter("Arquivos enviados", icon: "ri-folder-line", key: "upload_bytes", usage: usage,
                                divisor: 1_048_576, unit: "MiB")
                        counter("Buscas com IA", icon: "ri-search-ai-line", key: "searches", usage: usage)
                        counter("Itens na biblioteca", icon: "ri-gallery-line", key: "items", usage: usage)
                        counter("Armazenamento", icon: "ri-stack-line", key: "storage_bytes", usage: usage,
                                divisor: 1_048_576, unit: "MiB")
                        counter("Spaces", icon: "ri-folder-6-line", key: "spaces", usage: usage)
                    }
                } else if error == nil {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Consultando uso…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            if let usage {
                Text("Renova em \(usage.resetsAt.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 14)
                    .padding(.top, -14)
                    .accessibilityIdentifier("usage.reset")
            }
            if let error {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsNotice(text: error, failure: true)
                    Button("Tentar novamente") { attempt += 1 }
                        .buttonStyle(.queep(.neutral, height: 40, stretches: false))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                note("Novos itens, edições e novas tentativas de análise contam. Repetir um envio não confirmado com o mesmo conteúdo não conta de novo. Reservas de envio e buscas iniciadas podem contar mesmo se houver falha. Excluir conteúdo libera espaço após a limpeza, mas não devolve a cota mensal de IA e envio.")
                note("As cotas de IA e envio renovam no primeiro dia de cada mês, à meia-noite UTC. Itens, armazenamento e Spaces são limites do acervo e não renovam.")
            }
            .padding(.horizontal, 14)
            SettingsSection(title: "Privacidade") {
                VStack(spacing: 6) {
                    information("Onde ficam suas referências", icon: "ri-global-line",
                        text: "O conteúdo enviado fica na nuvem do Queep, no Firebase/Google Cloud, para sincronizar seus dispositivos. A interpretação usa provedores de IA por meio do OpenRouter. Texto, imagens e trechos de mídia necessários à análise são enviados para esse processamento.")
                    information("Você escolhe o que enviar", icon: "ri-shield-check-line",
                        text: "O Queep recebe o que você salva, compartilha ou captura. Ele não acompanha continuamente sua tela nem suas conversas. Links usam conteúdo público acessível; algumas redes sociais oferecem apenas informações parciais.")
                    information("Excluir e recuperar", icon: "ri-delete-bin-line",
                        text: "Ao excluir a conta, você tem 30 dias para recuperá-la. A biblioteca fica bloqueada nesse período. Também é possível pedir a exclusão definitiva imediata. Depois da remoção, cópias de segurança dos arquivos podem permanecer por até 7 dias, sem acesso pelo app.")
                    information("Cópias no dispositivo", icon: "ri-device-line",
                        text: "A reprodução e a preparação de mídia usam arquivos temporários, removidos ao fechar o conteúdo. Se o app for interrompido, arquivos temporários antigos são limpos ao abri-lo novamente. O salvamento exige internet; só feche o envio após a confirmação.")
                }
            }
        }
    }

    private func close() {
        if pushedInSettings { library.presentation = nil } else { dismiss() }
    }

    @ViewBuilder private func counter(_ title: String, icon: String, key: String, usage: Usage,
                                       divisor: Double = 1, unit: String = "") -> some View {
        if let counter = usage.counters[key] {
            let value = Double(counter.used) / divisor
            let limit = Double(counter.limit) / divisor
            let digits = divisor == 1 ? 0 : 1
            let description = "\(value.formatted(.number.precision(.fractionLength(0...digits)))) de \(limit.formatted()) \(unit)"
            let ratio = counter.limit > 0 ? min(1, Double(counter.used) / Double(counter.limit)) : 0
            HStack(spacing: 12) {
                IconTile(asset: icon)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        Text(description)
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSoft)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fill)
                            Capsule()
                                .fill(ratio >= 0.9 ? Theme.danger.opacity(0.7) : Theme.forest.opacity(0.75))
                                .frame(width: max(6, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(.trailing, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(description)
            .accessibilityIdentifier("usage.\(key)")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func information(_ title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(asset: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
