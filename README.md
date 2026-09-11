# Queep Apple

Um projeto Xcode, apps separados para macOS 14+ e iOS 17+, núcleo Swift comum em `Packages/QueepCore`. Interface SwiftUI com controles nativos e labels de acessibilidade. Firebase Auth mantém a identidade; todas as referências passam pela API.

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

Conta, notas/links/imagens, galeria com miniaturas, visualização/edição de texto, abertura da fonte, exclusão, atualização a cada quatro segundos enquanto ativo e busca textual nos itens carregados. O Mac usa barra de menu sem Dock, atalho global `⌘⇧Espaço` e opção de iniciar no login. Se o atalho estiver ocupado, o menu continua disponível.

Imagens podem ser escolhidas em arquivos no Mac/iPhone e em Fotos no iPhone. JPEG, PNG e HEIC estáticos de até 32 MiB são otimizados (até 4096 px), com prévia, envio, reenvio sem duplicação e visualizador com ampliação/exclusão. A galeria preserva a proporção das imagens em uma grade adaptativa.

IA, áudio/vídeo, screenshots, notch e Share Extension são próximas entregas. As referências indicam que aguardam análise; a busca atual é textual, por título/texto carregado. Acessibilidade assistiva completa e refinamento da galeria continuam pendentes.

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

Debug e CloudDevelopment usam identificadores `.dev`, separados dos apps de produção.
Release exclui os arquivos Firebase de desenvolvimento e **não usa emuladores como fallback**:
configuração ausente bloqueia conexão. Firebase de produção e assinatura de distribuição
serão configurados antes do beta. Firebase SDK está fixado em 12.19.1. RevenueCat/IAP
entra antes do beta público; o UID Firebase será o App User ID.

O teste de interface usa `preview@queep.test` / `queep-preview-only`, exclusivamente no emulador. A sessão é iniciada pelo SDK Firebase antes de exercitar a captura, evitando diálogos do gerenciador de senhas. `--ui-testing` e essas variáveis são aceitos apenas em Debug local. Nenhum token é simulado e o backend continua validando a identidade.

Com API/emuladores abertos, execute o teste de interface pelo esquema `QueepiOS` no Xcode. Ele salva e reabre uma nota com título único. A mesma conta local pode ser usada no Mac para verificar a sincronização.

Ainda precisam de validação manual: VoiceOver, tamanhos máximos de texto, múltiplas telas, funcionamento contínuo do atalho ao fechar a janela e início no login em app assinado. Compilar em sandbox não equivale à aprovação na Mac App Store.

Validado na nuvem: PNG de Fotos no iPhone → aberto/excluído no Mac; HEIC do Mac → aberto/excluído no iPhone. Uploads usam a mesma API autenticada das notas. A conta usada no teste manual foi preservada com a imagem adicionada durante o teste; credenciais locais ficam em `.local/`, ignorado pelo Git, sem tokens exportados.
