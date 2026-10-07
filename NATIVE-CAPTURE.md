# Captura nativa

Implementada em 11/09/2026. Usa a API existente; nenhuma chave de IA fica nos apps.

| Entrada | Comportamento |
| --- | --- |
| Mac · ⌘⇧Espaço | Abre captura rápida, mesmo com a biblioteca fechada. Nota/link, colar e print têm ações visíveis. Esc fecha sem apagar o rascunho. |
| Mac · ⌘⇧7 | Pede permissão de captura de tela ao macOS; arrastar seleciona a área, Enter captura a tela escolhida, Esc cancela. Apenas uma imagem é enviada. |
| Mac · pin de captura | Pin opcional que fica sobre a tela e pode ser arrastado para qualquer lugar. Passar o mouse ou arrastar um arquivo até ele abre um cartão com a última referência e as ações de captura rápida, colar, capturar tela e abrir a biblioteca. Ao salvar, o cartão fecha e o pin mostra a logo com um check. Falhas continuam abrindo a janela rápida para repetir ou descartar. A posição é lembrada e recolocada se o monitor mudar. |
| iPhone · Compartilhar → Salvar no Queep | Aparece na lista de ações (junto de ChatGPT/Gemini), com prévia de link, texto, imagem ou arquivo de áudio/vídeo, seguida de Salvar. Reutiliza o login do app. Pode ser fixada em **Editar Ações**. |

**Confirmação:** fecha o compartilhamento após a API confirmar o salvamento; a análise continua na nuvem. Falha mantém o mesmo conteúdo e identificador para repetir sem duplicação dentro daquele envio. Fechar a extensão/encerrar o app antes da confirmação ainda não tem recuperação persistente: fila offline fica para a próxima versão.

**Conta:** app iOS e extensão usam Keychain compartilhado. A sessão anterior é migrada na atualização. Cada cliente fixa o UID de origem e confere o usuário armazenado antes de pedir o token; mudar de conta não redireciona envios para outro acervo. A captura Mac limpa rascunhos ao trocar/sair da conta e invalida capturas de tela anteriores. Não existe leitura contínua do clipboard ou gravação contínua de tela.

**Formatos:** uma referência por envio. URL HTTP(S), nota até 30 mil caracteres, JPEG/PNG/HEIC estáticos. Clipboard Mac também normaliza TIFF. Imagens compartilhadas são reduzidas até 2048 px para conter memória da extensão; seletor/clipboard/print Mac até 4096 px. Imagens de entrada até 32 MiB, saída até 12 MiB; metadados EXIF/GPS não são enviados. Em compartilhamento com URL e sua imagem de prévia, o link tem prioridade. Se o compartilhamento incluir o arquivo de áudio/vídeo (Instagram, X/Twitter, Fotos), o arquivo ganha da URL do post.

Áudio/vídeo: original de até 150 MiB e cinco minutos, preparado em arquivo temporário
M4A/MP4 de até 25 MiB; vídeo em 720p. O arquivo temporário do provedor é copiado antes
de seu callback terminar e convertido de forma assíncrona. Os apps também oferecem
seletor de arquivos e, no iPhone, seletor de vídeos em Fotos. [Limites da análise](../queep-api/infra/MEDIA.md).
PDF continua fora desta entrega. Links sociais não necessariamente entregam o arquivo:
quando o compartilhamento contém só a URL, o Queep salva e analisa os dados públicos acessíveis.

## Configuração e verificação

- `QueepShare` é embutida em `QueepiOS`. Firebase de desenvolvimento da extensão: `app.queep.ios.dev.share`, no mesmo projeto e com a mesma API key pública do app.
- App/extension precisam da mesma equipe e grupo de Keychain. CloudDevelopment usa `$(AppIdentifierPrefix)app.queep.auth.dev`; Debug local usa `app.queep.auth.local` e bundles `app.queep.mac.local`, `app.queep.ios.local` e `app.queep.ios.local.share`. Isso mantém login e instalação locais separados da nuvem. Release usa `app.queep.auth` e requer seus próprios plists/perfis antes da distribuição.
- `QueepCaptureTests`: 7 testes de classificação, tipos inválidos, arquivos temporários,
  exportação de mídia, imagem/otimização e URL com prévia. `QueepCore`: 3 testes.
- `MediaFlowTests`: áudio/vídeo enviados por contas descartáveis e reproduzidos/pausados
  nos apps Mac/iPhone, com confirmação de avanço do relógio. Importação pelo seletor
  de arquivos também conferida no Mac. Compartilhamento de mídia em aparelho físico
  permanece entre as validações antes do beta.
- `ShortcutTests`: abrir pelo atalho fora do app, com biblioteca fechada, e fechar por Escape.
- `IslandTests`: pin presente, abertura por hover com as quatro ações e recolhimento ao afastar o ponteiro, com screenshots anexados.
- `CloudShareTests`: sessão cloud existente; Safari aberto em `https://example.com/queep-native-share` e fixture sintética `../queep-api/evaluation/fixtures/001.png` importada por último em Fotos. Rodar apenas no simulador de QA. Testes salvam e abrem as referências no app; remover depois os itens sintéticos exatos, preservando conteúdo do usuário.
- `CaptureFlowTests`: regressão de nota local e teste de saída da conta/compartilhamento bloqueado. O teste de saída requer a mesma página de exemplo aberta no Safari local.

```sh
xcodebuild -project Queep.xcodeproj -scheme QueepCaptureTests -configuration Debug -derivedDataPath build-tests test
xcodebuild -project Queep.xcodeproj -scheme QueepMacCloud -configuration CloudDevelopment -derivedDataPath build-mac test
```

Antes do beta: testar iPhone físico, VoiceOver/Dynamic Type, múltiplos monitores/escalas, conflitos de atalhos, início no login e assinatura/distribuição. Essas verificações não são substituídas pelo build ou pelo teste de simulador.
