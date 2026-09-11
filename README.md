# Queep Apple

Um projeto Xcode, apps separados para macOS 14+ e iOS 17+, núcleo Swift comum em `Packages/QueepCore`. Interface SwiftUI com controles nativos e labels de acessibilidade. Firebase Auth mantém a identidade; todas as referências passam pela API.

## Rodar

1. Inicie os emuladores e a API em `../queep-api`.
2. Instale XcodeGen (`brew install xcodegen`) e rode `xcodegen generate`.
3. Configure sua equipe de desenvolvimento em `Config/Local.xcconfig` (`DEVELOPMENT_TEAM = ID`) ou passe pelo Xcode. Esse arquivo não vai para Git.
4. Abra `Queep.xcodeproj`; use `QueepMac` no Mac ou `QueepiOS` no simulador.
5. Crie uma conta de teste em um app e entre com a mesma conta no outro.

Debug usa `127.0.0.1` e `demo-queep`. Dispositivo físico precisa de ambiente HTTPS, configuração Firebase e assinatura; não aponta para o computador por localhost.

## O que funciona nesta entrega

Conta, notas/links, galeria, visualização/edição, abertura da fonte, exclusão, atualização a cada quatro segundos enquanto ativo e busca textual nos itens carregados. O Mac usa barra de menu sem Dock, atalho global `⌘⇧Espaço` e opção de iniciar no login. Se o atalho estiver ocupado, o menu continua disponível.

IA, uploads de mídia, screenshots, notch e Share Extension são próximas entregas. A interface identifica esta versão de desenvolvimento e referências aguardando análise. A galeria inicial é uma grade; o layout de alturas variadas chega com imagens.

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

Debug usa identificadores `.dev`, separados dos apps de produção. Configurar arquivos Firebase distintos por app/ambiente, `QueepAPIURL` HTTPS e assinatura da equipe. Release **não usa emuladores como fallback**: configuração ausente bloqueia conexão. Firebase SDK está fixado em 12.19.1. RevenueCat/IAP entra antes do beta público; o UID Firebase será o App User ID.

O teste de interface usa `preview@queep.test` / `queep-preview-only`, exclusivamente no emulador. A sessão é iniciada pelo SDK Firebase antes de exercitar a captura, evitando diálogos do gerenciador de senhas. `--ui-testing` e essas variáveis são aceitos apenas em Debug local. Nenhum token é simulado e o backend continua validando a identidade.

Com API/emuladores abertos, execute o teste de interface pelo esquema `QueepiOS` no Xcode. Ele salva e reabre uma nota com título único. A mesma conta local pode ser usada no Mac para verificar a sincronização.

Ainda precisam de validação manual: VoiceOver, tamanhos máximos de texto, múltiplas telas, funcionamento contínuo do atalho ao fechar a janela e início no login em app assinado. Compilar em sandbox não equivale à aprovação na Mac App Store.
