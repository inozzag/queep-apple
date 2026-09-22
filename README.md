# Queep Apple

Um projeto Xcode, apps separados para macOS 14+ e iOS 17+, núcleo Swift comum em `Packages/QueepCore`. Interface SwiftUI com controles nativos e labels de acessibilidade. Firebase Auth mantém a identidade; todas as referências passam pela API.
Na nuvem, o app entra com Apple, Google ou e-mail e senha.

## Spaces

“Tudo” e os Spaces aparecem na biblioteca. A aba Spaces cria, renomeia, reordena e
exclui coleções; excluir preserva as referências. O botão Space nos detalhes e na
seleção em lote adiciona/remove vínculos imediatamente, com rollback em erro.
Captura normal e captura rápida do Mac oferecem “Salvar em…” opcional; o padrão
continua sendo nenhum Space. A extensão de compartilhamento continua na inbox,
com atribuição posterior, conforme o escopo permitido pela GAZ-116.

O cache de leitura é separado por conta e filtro, preserva a última seleção e é
removido ao trocar/sair da conta. Alterações exigem conexão. Busca usa o Space
selecionado; arquivados não aparecem nem contam nos Spaces ativos. Criação segue
as cotas 0/15/40 da API, sem bloquear atribuição aos Spaces já existentes.

Cobertura: `SpaceTests` no QueepCore, `LibrarySpacesTests` para cache e rollback,
e `SpacesTests` nos dois targets de UI (criar → atribuir → filtrar, com Firebase
emulado). `QueepMac` também inclui seu target de UI no esquema de testes.

## Rodar

1. Inicie os emuladores e a API em `../queep-api`.
2. Instale XcodeGen (`brew install xcodegen`) e rode `xcodegen generate`.
3. Configure sua equipe de desenvolvimento em `Config/Local.xcconfig` (`DEVELOPMENT_TEAM = ID`) ou passe pelo Xcode. Esse arquivo não vai para Git.
4. Abra `Queep.xcodeproj`; use `QueepMac` no Mac ou `QueepiOS` no simulador.
5. Crie uma conta de teste em um app e entre com a mesma conta no outro.

Debug usa `127.0.0.1` e `demo-queep`. Dispositivo físico precisa de ambiente HTTPS, configuração Firebase e assinatura; não aponta para o computador por localhost.

Os esquemas `QueepMacCloud` e `QueepiOSCloud` usam a configuração `CloudDevelopment`,
com Firebase `queep-dev-hstlx` e API HTTPS de desenvolvimento. O build inclui apenas
o plist do respectivo app e valida projeto/bundle ID antes de conectar. A API está
liberada para os apps com login Firebase; sincronização e edição Mac/iPhone foram
verificadas na nuvem. Configuração em `../queep-api/infra/CLOUD.md`.
Os identificadores públicos Firebase estão versionados;
credenciais de usuário, tokens e chaves de service account não fazem parte deles.

## O que funciona nesta entrega

Operações básicas completas em 12/09/2026: imagens, áudios e vídeos agora abrem como documento, com título e anotações Markdown editáveis e salvos pela API (`PATCH` com `kind` image/audio/video, que preserva o arquivo, sobe a revisão e reenfileira a análise). Excluir saiu do meio da tela para o menu "Mais" de cada documento, ao lado de compartilhar, copiar imagem ou link; no Mac esse menu fica no cabeçalho do documento porque folhas do macOS só mostram Fechar e Salvar na barra. Os cards da biblioteca ganharam menu de contexto (botão direito no Mac, toque longo no iPhone) com abrir, copiar e excluir com confirmação. `ImageEditTests` cobre renomear, anotar, salvar e excluir uma imagem nos dois apps com contas descartáveis dos emuladores.

Interface repaginada em 12/09/2026, inspirada no Craft e só com controles nativos do SwiftUI: biblioteca em cards uniformes com capa, texto e estado só quando informa algo; busca apresentada como conversa com a IA (cabeçalho com o que está sendo interpretado, esqueleto animado e resumo/assuntos nos resultados); referência aberta como documento, com título grande, editor Markdown com estilo ao vivo (títulos, listas, tarefas, citação, código, links) e barra de formatação; análise da IA em um card discreto. As notas continuam texto puro para a API; a fonte do sistema foi mantida. Base visual em `Sources/Shared/Theme.swift` e editor em `Sources/Shared/Markdown.swift`.

Conta, notas/links/imagens/áudio/vídeo, galeria, edição de notas/links, exclusão e busca semântica. A busca só envia uma consulta ao confirmar pelo teclado ou botão; considera o acervo processado da conta, não apenas a página carregada. Mostra até 10 referências conferidas por IA, estados de análise e nova tentativa. O Mac fica no Dock com o mesmo ícone do iPhone, mantém a barra de menu e a opção de iniciar no login.

Primeiro uso: a biblioteca vazia oferece captura direta de nota, link, imagem ou mídia e
explica captura, processamento e busca. Após salvar o primeiro item, aparece uma
dica dispensável; **Conta → Como usar o Queep** mantém as instruções disponíveis.
A atualização em segundo plano preserva a tela vazia e seus controles. Erros de
carregamento têm estado próprio. Não há conteúdo de exemplo inserido na conta.
`FirstUseTests` verifica captura e reabertura da ajuda nos emuladores; no Mac também
confere o conteúdo da primeira nota diretamente na API. Usa contas descartáveis.

Captura Mac: `⌘⇧Espaço` abre uma janela independente da biblioteca; `⌘⇧7` seleciona uma área da tela. Também aceita colar texto/link/imagem e arrastar para a ilha opcional no notch: ela fica escondida atrás do notch, abre ao passar o mouse ou ao arrastar um arquivo, mostra a última referência e as ações de captura, e recolhe ao afastar o ponteiro (em telas sem notch, uma aba sob a barra de menus). O menu oferece as mesmas ações. No iPhone, a opção Queep no compartilhamento salva um link, texto ou imagem usando a conta do app. [Funcionamento e limites](NATIVE-CAPTURE.md).

Imagens podem ser escolhidas em arquivos no Mac/iPhone e em Fotos no iPhone. JPEG, PNG e HEIC estáticos de até 32 MiB são otimizados (até 4096 px), com prévia, envio, reenvio sem duplicação e visualizador com ampliação/exclusão. A galeria preserva a proporção das imagens em uma grade adaptativa.

Áudio/vídeo: escolher arquivo nos dois apps, vídeo de Fotos no iPhone, compartilhar
arquivo ou arrastá-lo para o topo do Mac. Até cinco minutos, original de até 150 MiB
e envio preparado de até 25 MiB; vídeo otimizado para 720p e áudio em M4A. A galeria
mostra tipo/duração; o detalhe reproduz, pausa, permite avançar no áudio e mostra
análise/transcrição. Download autenticado para arquivo temporário, removido ao fechar.
Não há reprodução automática. [Cobertura e testes](../queep-api/infra/MEDIA.md).

Na nuvem, os arquivos são interpretados automaticamente; links mostram o texto ou
metadados públicos acessíveis, com cobertura parcial explícita. YouTube/Vimeo não
equivalem a análise de fala/cenas pelo link. A biblioteca atualiza ao voltar de outro
app e a primeira página a cada quatro segundos enquanto ativa, sem repetir consultas
pagas; o detalhe acompanha a análise. No ambiente local a IA vem desabilitada por
padrão. Validação completa de acessibilidade e aparelhos físicos segue antes do beta.

## Verificar

```sh
cd Packages/QueepCore
swift test
```

Build local Mac com certificado de desenvolvimento e perfil compatível (Firebase Auth usa Keychain):

```sh
xcodebuild -project Queep.xcodeproj -scheme QueepMac -configuration Debug -derivedDataPath build-mac build
```

## Nuvem e publicação

Debug usa identificadores/grupo de autenticação `.local`; CloudDevelopment usa `.dev`.
Assim os testes nos emuladores não substituem a instalação nem o login cloud.
Release exclui os arquivos Firebase de desenvolvimento e **não usa emuladores como fallback**:
configuração ausente bloqueia conexão. Firebase de produção e assinatura de distribuição
serão configurados antes do beta. Firebase SDK está fixado em 12.19.1. RevenueCat 5.89.0
usa o UID Firebase como App User ID; compra/restauração Test Store e reconhecimento
Mac/iPhone foram validados. Produtos Apple/publicação seguem pendentes.
Configuração, testes opt-in e evidências: [BILLING.md](../queep-api/infra/BILLING.md).

**Conta → Excluir conta** agenda a remoção para 30 dias e bloqueia a biblioteca.
Entrar novamente mostra a data e permite **Cancelar exclusão e recuperar conta**,
com confirmação de senha. Login sozinho não cancela. A opção de exclusão definitiva
imediata permanece disponível. Política ativa e validada na nuvem; RevenueCat adiado.
[Funcionamento e retenção](../queep-api/infra/ACCOUNTS.md).
`AccountDeletionTests` cria contas descartáveis nos emuladores; nunca usa a conta
cloud do usuário. Agendamento, reabertura, recuperação e exclusão imediata passaram
no iPhone; bloqueio entre sessões e recuperação passaram no Mac.

O teste de interface usa `preview@queep.test` / `queep-preview-only`, exclusivamente no emulador. A sessão é iniciada pelo SDK Firebase antes de exercitar a captura, evitando diálogos do gerenciador de senhas. `--ui-testing` e essas variáveis são aceitos apenas em Debug local. Nenhum token é simulado e o backend continua validando a identidade.

Com API/emuladores abertos, execute o teste de interface pelo esquema `QueepiOS` no Xcode. Ele salva e reabre uma nota com título único. A mesma conta local pode ser usada no Mac para verificar a sincronização.

O teste Mac de interface verifica o atalho com Finder em primeiro plano, biblioteca fechada e fechamento por Escape. Ainda precisam de validação manual: VoiceOver, tamanhos máximos de texto, múltiplas telas e início no login em app assinado. Compilar em sandbox não equivale à aprovação na Mac App Store.

`MediaImportTests` testa exportação, remoção dos temporários e arquivo compartilhado
removido pelo provedor após o callback. `MediaFlowTests` cria uma conta descartável,
envia áudio/vídeo sintéticos e verifica reprodução/pausa e avanço do relógio nos dois
apps. Os arquivos em `Tests/Fixtures` só entram nos bundles de teste.

Busca cloud verificada no Mac e no iPhone: nota sintética criada no Mac, interpretada
em segundo plano, encontrada pelo assunto e aberta no iPhone. O teste opt-in
`CloudSearchTests/testSearchAcrossDevices` usa `CloudDevelopment` e uma sessão
previamente autenticada com a nota indicada no teste; não cria nem troca contas.
Em Debug local ele é ignorado. Limpar a nota sintética pela API após a rodada.

Links agora mostram texto extraído, data e limitações quando o backend fornece `source`.
Títulos escritos pelo usuário continuam prioritários; links sem título usam o título
da página quando disponível. `CloudSourceTests/testSearchAndReadExtractedPage` é opt-in:
preparar o link público HTTPX com o título indicado no teste, sem contexto adicional.
Funciona com conta cloud existente ou `preview@queep.test` nos emuladores; não executa
busca paga sem encontrar a referência de teste. Limpar essa referência após a rodada.
Funcionalidade publicada na nuvem de desenvolvimento. O teste passou nos emuladores
e no iPhone cloud; leitura/expansão também verificadas no Mac. As referências de teste
foram removidas, mantendo a conta e os conteúdos anteriores.

Validado na nuvem: PNG de Fotos no iPhone → aberto/excluído no Mac; HEIC do Mac → aberto/excluído no iPhone. Uploads usam a mesma API autenticada das notas. A conta usada no teste manual foi preservada com a imagem adicionada durante o teste; credenciais locais ficam em `.local/`, ignorado pelo Git, sem tokens exportados.


## Free / Pro / Max (GAZ-115)

A tela compartilhada de planos usa o plano confirmado pela API, preços da loja,
desconto anual calculado pelos produtos e trial somente com elegibilidade confirmada.
Erros 402 abrem Pro/Max conforme a API; mídia é verificada antes da preparação,
inclusive na extensão (sem RevenueCat). Uso mostra cotas mensais e inventário.

Esquemas `QueepiOSTestFlight` / `QueepMacTestFlight` usam configuração de release
com Firebase dev e API isolada. Preencher `Config/BillingTestFlight.xcconfig`
a partir do exemplo após configurar os consoles. O build rejeita chaves `test_`.
[Contrato backend](../queep-api/infra/PLANS.md) e
[configuração Apple, pendências e margem anual](../queep-api/infra/APPLE-LAUNCH.md).
