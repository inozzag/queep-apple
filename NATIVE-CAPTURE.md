# Captura nativa

Implementada em 11/09/2026. Usa a API existente; nenhuma chave de IA fica nos apps.

| Entrada | Comportamento |
| --- | --- |
| Mac · ⌘⇧Espaço | Abre captura rápida, mesmo com a biblioteca fechada. Nota/link, colar e print têm ações visíveis. Esc fecha sem apagar o rascunho. |
| Mac · ⌘⇧7 | Pede permissão de captura de tela ao macOS; arrastar seleciona a área, Enter captura a tela escolhida, Esc cancela. Apenas uma imagem é enviada. |
| Mac · topo/notch | Área opcional para soltar imagem, texto ou link; clique abre captura rápida. Ajusta a posição quando as telas mudam e oferece alternativa sem notch. |
| iPhone · Compartilhar → Queep | Prévia de um link, texto ou imagem, seguida de Salvar. Reutiliza o login do app. Safari e Fotos verificados no simulador cloud. |

**Confirmação:** fecha o compartilhamento após a API confirmar o salvamento; a análise continua na nuvem. Falha mantém o mesmo conteúdo e identificador para repetir sem duplicação dentro daquele envio. Fechar a extensão/encerrar o app antes da confirmação ainda não tem recuperação persistente: fila offline fica para a próxima versão.

**Conta:** app iOS e extensão usam Keychain compartilhado. A sessão anterior é migrada na atualização. Cada cliente fixa o UID de origem e confere o usuário armazenado antes de pedir o token; mudar de conta não redireciona envios para outro acervo. A captura Mac limpa rascunhos ao trocar/sair da conta e invalida capturas de tela anteriores. Não existe leitura contínua do clipboard ou gravação contínua de tela.

**Formatos:** uma referência por envio. URL HTTP(S), nota até 30 mil caracteres, JPEG/PNG/HEIC estáticos. Clipboard Mac também normaliza TIFF. Imagens compartilhadas são reduzidas até 2048 px para conter memória da extensão; seletor/clipboard/print Mac até 4096 px. Arquivos de entrada até 32 MiB, saída até 12 MiB; metadados EXIF/GPS não são enviados. Em compartilhamento com URL e sua imagem de prévia, o link tem prioridade. Vídeo/PDF não são importados nesta entrega.

## Configuração e verificação

- `QueepShare` é embutida em `QueepiOS`. Firebase de desenvolvimento da extensão: `app.queep.ios.dev.share`, no mesmo projeto e com a mesma API key pública do app.
- App/extension precisam da mesma equipe e grupo de Keychain: `$(AppIdentifierPrefix)app.queep.auth.dev`. Release usa `app.queep.auth` e requer seus próprios plists/perfis antes da distribuição.
- `QueepCaptureTests`: 5 testes de classificação, tipos inválidos, imagem temporária/otimização e URL com prévia. `QueepCore`: 2 testes existentes.
- `ShortcutTests`: abrir pelo atalho fora do app, com biblioteca fechada, e fechar por Escape.
- `CloudShareTests`: sessão cloud existente; Safari aberto em `https://example.com/queep-native-share` e fixture sintética `../queep-api/evaluation/fixtures/001.png` importada por último em Fotos. Rodar apenas no simulador de QA. Testes salvam e abrem as referências no app; remover depois os itens sintéticos exatos, preservando conteúdo do usuário.
- `CaptureFlowTests`: regressão de nota local e teste de saída da conta/compartilhamento bloqueado. O teste de saída requer a mesma página de exemplo aberta no Safari local.

```sh
xcodebuild -project Queep.xcodeproj -scheme QueepCaptureTests -configuration Debug -derivedDataPath build-tests test
xcodebuild -project Queep.xcodeproj -scheme QueepMacCloud -configuration CloudDevelopment -derivedDataPath build-mac test
```

Antes do beta: testar iPhone físico, VoiceOver/Dynamic Type, múltiplos monitores/escalas, conflitos de atalhos, início no login e assinatura/distribuição. Essas verificações não são substituídas pelo build ou pelo teste de simulador.
