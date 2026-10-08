# Auditoria pré-lançamento — cliente Apple (iOS + macOS)

Auditoria só de leitura do branch `develop` (HEAD `6a2ffc1`, TestFlight build 6, versão `0.1.0`). Nenhum código de produto foi alterado. Não há métricas de uso, conversão ou qualidade de busca neste repositório; o que segue é o que o cliente faz de fato.

Escopo: `Sources/`, `Packages/QueepCore/`, `project.yml`, `Config/`, `README.md`, `QUALITY.md`. O backend (`queep-api`) não foi aberto. Comportamento de loja (produtos App Store Connect, webhook da RevenueCat, qualidade do ranking) não dá para confirmar daqui.

## Como ler

Severidade:

- **Blocker** — pode derrubar sessão, cobrança ou o fluxo central no próximo TestFlight/loja.
- **High** — o usuário sente no caminho feliz (pagar, achar, esperar a análise, abrir Ajustes).
- **Medium** — inconsistente, frágil ou fácil de entender errado; dá para lançar com olho aberto.
- **Low** — cópia morta, hint errado, código que não está no caminho.

“Agora” = entra no próximo build que vai para gente de fora. “Depois” = não segura o corte.

---

## 1. Paywall e checkout

Há dois checkouts no mesmo `SubscriptionStore`:

| Superfície | Onde abre | Arquivo |
| --- | --- | --- |
| `ConversionPaywall` | Depois do primeiro save (`LibraryView.considerFirstPaywall`) e em 402 de mídia (`PaywallSheet` quando `resource == "media_av"`) | `Sources/Shared/SubscriptionView.swift` |
| `SubscriptionView` | Ajustes → Assinatura, e qualquer outro 402 (`spaces_required`, cota, etc.) | o mesmo arquivo |

O acesso exibido vem só da API (`GET v1/billing/access`, refresh em `POST v1/billing/sync`). Entitlement local da RevenueCat não libera o app — o comentário em `SubscriptionStore.load` deixa isso explícito. Isso é o desenho certo. O furo é o que a tela faz com uma compra já ativa.

### B1 — Assinante ativo não compra upgrade na tela de planos

**Severidade:** Blocker para quem já é Pro e bate no Max (áudio/vídeo ou “Conhecer o Max”).  
**Onde:** iOS e Mac, o mesmo código.  
**Evidência:** `SubscriptionView`, botão de cada pacote: se `store.access?.active == true` e não é `isDevelopment`, o botão abre `https://apps.apple.com/account/subscriptions` e não chama `purchase`. `SubscriptionStore.purchase` até aceita upgrade de rank (`upgrading` quando o plano alvo é maior). A tela de Ajustes nunca chega lá.

`ConversionPaywall.buy` é o oposto: só manda para a Apple se o rank atual já é maior ou igual ao plano da folha. Pro → Max por essa folha ainda compra in-app.

**Agora:** um único caminho de compra. Upgrade de rank (Pro → Max) tem que chamar `purchase` nas duas folhas. Troca mensal/anual do mesmo plano pode continuar na Apple — o próprio `purchase` já recusa isso com “Altere seu plano em Gerenciar na App Store”.  
**Depois:** nada.

### H1 — O paywall do primeiro save é marcado como visto antes de saber se há plano

**Severidade:** High.  
**Onde:** iOS e Mac.  
**Evidência:** `LibraryView.considerFirstPaywall` chama `OnboardingProgress.markPaywallShown(uid)` e só então `SubscriptionStore.load`. A chave é `queep.paywall.first.<uid>` (`OnboardingView.swift`). Se o load falha, `access` fica nil e o código trata como Free (`access?.plan ?? .free`) e abre a folha mesmo assim. A flag já está true: não abre de novo.

Ambiente `mode == "development"` também força a folha (comentário no código: emulador concede Max). No TestFlight isso depende do `mode` que a API devolver.

**Agora:** gravar “já mostrei” só depois de ofertas carregadas, e não tratar `access == nil` como Free.  
**Depois:** —

### H2 — Cópia de trial mente no plano e no período

**Severidade:** High (texto de cobrança).  
**Onde:** `SubscriptionView`, qualquer pacote em `trialEligible`.  
**Evidência:** o texto é fixo: “7 dias grátis de Pro; depois, {preço} por ano”. `trialEligible` inclui anual de Pro **e** de Max (`SubscriptionStore.load`). Max anual aparece como trial de Pro. A folha `ConversionPaywall` está melhor: “7 dias grátis” / “Começar 7 dias grátis” e o preço do pacote escolhido.

**Agora:** usar o título do plano e o período do pacote, como a folha de conversão já faz.  
**Depois:** —

### H3 — Dois checkouts para o mesmo 402

**Severidade:** High de produto, não de crash.  
**Onde:** iOS e Mac.  
**Evidência:** `PaywallSheet` manda `media_av` para `ConversionPaywall(focus: .max)` e o resto para `SubscriptionView(requirement:)`. `visiblePackages` ainda filtra pelo `requiredPlan` exato: um 402 que pede Pro não mostra Max.

Cotas na tela de planos estão escritas na view (“12 capturas…”, “100 capturas…”, “200 capturas…”), não lidas de `SubscriptionAccess.limits` nem de `GET v1/usage`. Se a API mudar o número, a vitrine mente.

**Agora:** conferir na mão se os números da vitrine batem com `PLANS.md` / a API que o TestFlight aponta. Unificar a folha pode esperar se a compra de upgrade (B1) estiver certa.  
**Depois:** uma folha só; limites vindos da API.

### M1 — Loja e chaves não estão neste git; a documentação se contradiz

**Severidade:** Medium como risco de processo. Não dá para marcar Blocker sem o archive.  
**Evidência:**

- `Scripts/verify-billing-config.sh` recusa configuração `Release` e `TestFlight` sem chave `appl_…` e sem URLs HTTPS de privacidade e termos.
- `Config/BillingTestFlight.xcconfig` não está no git. Só `Config/BillingTestFlight.xcconfig.example`, com os quatro campos vazios.
- `Config/Release.xcconfig` inclui `BillingProduction.xcconfig`, arquivo que não existe no repositório.
- `SubscriptionStore.key` em build que não é `DEBUG` exige prefixo `appl_` mais `QueepPrivacyURL` e `QueepTermsURL`. Sem isso a UI diz “Compras ainda não disponíveis nesta versão.”
- IDs de produto são separados por app: `app.queep.pro.monthly` / `app.queep.max.yearly` no iOS e `app.queep.mac.pro.monthly` / `app.queep.mac.max.yearly` no Mac (`SubscriptionPlan.product`). A compra de um não é o produto Apple do outro; o outro aparelho só enxerga o plano depois do `POST v1/billing/sync`.
- `README.md` diz que compra/restauração de Test Store foi validada e que “Produtos Apple/publicação seguem pendentes.” `QUALITY.md` ainda diz “RevenueCat e App Store Connect permanecem adiados.”

O código de compra existe e o script de TestFlight não deixa subir chave `test_`. Isso não prova que o build 6 tem produto sandbox aprovado, grupo de assinatura cruzando iPhone e Mac, nem webhook que confirma o plano.

**Agora:** um sandbox real nos dois apps: comprar Pro anual, ver `awaitingConfirmation` sumir, abrir o outro app com a mesma conta Firebase e ver o plano na API. Sem isso, não mandar gente pagar.  
**Depois:** apagar a frase defasada do `QUALITY.md` quando a loja estiver de fato ligada.

### M2 — Restaurar na folha de conversão não olha se a loja existe

**Severidade:** Medium.  
**Evidência:** `SubscriptionView` desabilita “Restaurar compras” com `!store.storeAvailable`. `ConversionPaywall` desabilita “Restaurar” só com `store.busy`. Sem chave, `restore` cai no erro genérico de `perform`.

**Agora:** se B1/H1 entrarem na mesma folha, alinhar o botão.  
**Depois:** se a folha nem abrir sem ofertas.

### L1 — Atalho da extensão sempre abre paywall de Max como se a conta fosse Free

**Severidade:** Low para o app; Medium se a pessoa compartilha vídeo sem Max.  
**Evidência:** a extensão abre `{scheme}://subscription?plan=max` (`ShareViewController.swift`). `RootView.onOpenURL` ignora a query e faz `session.planRequirement = .media(for: .free)`. `PlanRequirement.media` fixa a mensagem “Áudio e vídeo são do Queep Max.” Quem já é Pro cai na folha certa de produto (Max). Quem já é Max é empurrado para a URL da Apple por `ConversionPaywall.buy`. O query `plan` não é lido.

**Agora:** não bloqueia o corte se B1 estiver feito.  
**Depois:** passar o plano real da API para o deep link.

---

## 2. Ajustes

Não existe uma aba com esse nome. O botão da biblioteca (`HomeAccountButton`, identifier `person.crop.circle`, help “Conta”) abre um sheet `AccountView` cujo título é “Ajustes”. iOS e Mac usam a mesma lista. O que muda é `listStyle` (inset grouped no iOS, inset no Mac) e a altura mínima da janela no Mac.

O sheet é um enum só (`LibraryPresentation` em `LibraryStore`). Trocar de seção não empilha: substitui o sheet.

### H4 — Cada seção que não é nome/e-mail/senha/login fecha Ajustes

**Severidade:** High. É o “todas as seções” do radar.  
**Onde:** iOS e Mac.  
**Evidência:** `AccountView`.

| Seção | O que faz |
| --- | --- |
| Nome, E-mail, Senha, Logins | `NavigationLink` dentro do sheet. Dá para voltar. |
| Arquivados | `store.show(.archived)` e `presentation = nil`. Some o sheet e troca a biblioteca. |
| Assinatura e planos | `presentation = .subscription`. O sheet de Ajustes é destruído. Fechar volta para a biblioteca, não para Ajustes. |
| Gerenciar cobrança na Apple | `https://apps.apple.com/account/subscriptions` |
| Notas fiscais e compras | `https://reportaproblem.apple.com` |
| Como usar o Queep | `presentation = .help` |
| Uso e privacidade | `presentation = .usage` |
| Sair / Excluir conta | sair no lugar; excluir troca para `.deleteAccount` |

Não há lista de sessões, aparelhos ou “onde estou logado”. “Logins” é vínculo Apple/Google no Firebase (`AccountLoginsEditor`), escondido quando `session.isLocal`.

**Agora:** Assinatura, Uso, Ajuda e Excluir como push dentro do `NavigationStack` de Ajustes, com voltar. Arquivados pode continuar indo para a biblioteca, mas o rótulo precisa dizer isso.  
**Depois:** uma tela de sessões, se o produto quiser isso. Hoje não existe nem na API do cliente.

### H5 — Erro de conta vira texto de login

**Severidade:** High no suporte (“não consigo mudar o e-mail e o app fala para entrar de novo”).  
**Evidência:** nome, e-mail, senha e vínculos passam por `SocialAuth.message`. Códigos Firebase mapeados são poucos (`requiresRecentLogin`, `emailAlreadyInUse`, `weakPassword`, …). O `default` devolve “Não foi possível entrar. Tente de novo.” — frase de `SignInView`, usada no editor de perfil.

Troca de e-mail não troca na hora: `Session.requestEmailChange` chama `sendEmailVerification(beforeUpdatingEmail:)`. A linha “E-mail ainda não confirmado” fica solta no primeiro section, sem botão; o reenvio está um nível abaixo.

Senha mínima é 6 caracteres, igual ao Firebase. Conta Apple sem e-mail não cria senha: “Cadastre um e-mail antes de criar uma senha.”

**Agora:** mensagem por contexto (salvar nome / e-mail / senha / vínculo), não a frase de login.  
**Depois:** —

### M3 — A linha de assinatura não mostra o plano

**Severidade:** Medium.  
**Evidência:** `SettingsRow` de “Assinatura e planos” passa `value: nil`. O plano confirmado está em `SubscriptionStore.access` e de novo em `GET v1/usage` (`UsagePrivacyView`, “Plano Queep {title}”). A pessoa abre Ajustes e não vê Free/Pro/Max.

`UsagePrivacyView` omite o contador se a chave não vier no JSON (`usage.counters[key]`). Não avisa que o dado faltou.

**Agora:** o valor da linha pode ser `access.plan.title` se o load já rodou.  
**Depois:** —

### M4 — Avatar na API, zero UI

**Severidade:** Medium se a loja promete foto; Low se não promete.  
**Evidência:** `APIClient.uploadAvatar`, `avatarData`, `deleteAvatar` (`v1/account/avatar`) não têm caller fora do próprio client. `Session.Identity.photoURL` é a foto do Firebase e não aparece em `AccountView`.

**Agora:** não colocar foto no material de lançamento.  
**Depois:** ligar a UI ou apagar o client.

### L2 — “Testar aviso do feed” só em DEBUG

**Severidade:** Low. Não vai no TestFlight (`#if DEBUG` em `AccountView` e `FeedNotice`). O comentário em `FeedNotice` diz que o limite real de 10 minutos em app social depende de Family Controls, que não está implementado.

**Agora:** não.  
**Depois:** ou tira o experimento, ou vira feature de verdade.

---

## 3. Análise — status, erro e retry no cliente

O backend enfileira. O cliente só faz `GET v1/references/{id}` e `POST v1/references/{id}/retry` com a `revision`. Há quatro loops, com regras diferentes. Nenhum retry escreve de volta no `LibraryStore`; o card só muda no refresh da lista.

| Tela | Poll | Para quando | Erro de rede | Retry recomeça o poll? |
| --- | --- | --- | --- | --- |
| `AnalysisView` (nota em `CaptureView`, imagem em `ImageDetailView`, mídia em `MediaDetailView`) | 5 s, sem teto | `ready` ou `error` | `catch { return }` — para e não mostra o erro | Sim, se o `status` mudar: o `.task` inclui `current.status` |
| `CaptureView` (notas e links abertos por ele) | 2 s, até 45 vezes | `error`; em `ready` ainda espera foto se for post | `catch { }` — ignora e segue | Não. O `.task` é `reference?.id`. O `AnalysisView` filho faz um segundo poll em paralelo |
| `PostDetailView.refresh` | 2 s, até 45 vezes | `error`; em `ready` segue até a galeria encher ou 15 polls extras | ignora | Não. `.task(id: reference.id)` já saiu |
| `SiteDetailView` / `ProfileDetailView` | 2 s, até 45 vezes | `error` **ou** `ready` | ignora | Não |

`GalleryDetailView` (o que abre na biblioteca quando há imagem, e vídeo com `media`) **não faz poll**. O comentário em `RootView` diz “Keep polling while a post is open so carousel photos appear after analysis.” O código não olha se o post está aberto. Só chama `library.refresh` se `library.items.count <= 40`.

### B2 — Um GET `v1/account` que falha derruba a sessão a cada 4 segundos

**Severidade:** Blocker. Entra neste capítulo porque é o mesmo timer que devia acompanhar a análise.  
**Onde:** iOS e Mac, app em primeiro plano.  
**Evidência:** `RootView` dorme 4 s e chama `session.handleUnauthorized(uid)` “para a conta fechada em outro aparelho também dispensar a tela”. `handleUnauthorized` faz `refreshAccount` → `APIClient.accountStatus()` → `GET v1/account`. Qualquer `throw` cai em `invalidate`: `Auth.auth().signOut()` e o aviso “Sua sessão foi encerrada…”.

`APIClient.request` transforma falha de rede em `QueepError.unavailable` e 5xx em `QueepError.server`. Os dois derrubam o login. Não é só 401.

O mesmo loop roda quando `userID == nil` e `accountOwner` está setado (conta em exclusão, `AccountRecoveryView`): um blip também chama `invalidate`.

O listener de auth é o contrário: `try? await self.refreshAccount` engole o erro e não aplica estado. Cold start com rede ruim mostra `SignInView` mais “Conecte-se à internet e entre novamente…” mesmo com usuário Firebase ainda presente (`Session.finishSetup`).

**Agora:** o batimento de 4 s só pode deslogar em 401/403 de conta encerrada, ou quando `AccountStatus` disser que não está `active`. Timeout e 5xx ficam em silêncio e tentam de novo.  
**Depois:** —

### H6 — Biblioteca com mais de 40 itens não acompanha a análise

**Severidade:** High.  
**Evidência:** o `if library.items.count <= 40` em `RootView`. Acima disso, card, galeria e carrossel ficam no snapshot do último `refresh` manual (puxar para atualizar no iOS, botão/atalho no Mac, ou voltar o app para `.active`, que recria o `.task`).

O card sem imagem em `queued`/`processing` diz “Enviando novos itens...” (`HomeReferenceCard.analyzingTile`), mesmo quando o upload já acabou e o que falta é a análise. Itens com imagem só ganham um spinner. `coverage == "partial"` não aparece no card (o overlay só trata `status == "error"`). A pílula “Análise parcial” existe em `StatusPill` e no `statusLabel` de `Reference`, mas a galeria não usa.

**Agora:** enquanto houver item `queued`/`processing` na memória, ou um detalhe aberto, continuar o refresh — sem o teto de 40. Trocar o texto “Enviando novos itens...”.  
**Depois:** badge de análise parcial no card.

### H7 — Retry não religa o poll e não atualiza a lista

**Severidade:** High.  
**Evidência:** `PostDetailView.retry`, `SiteDetailView.retry`, `ProfileDetailView.retry` gravam `latest` local. O loop já retornou no `error` e o id da task não muda. Se o POST devolve `queued`, a tela mostra “em segundo plano” e não busca de novo. `AnalysisView` é o único que volta a pollar, e mesmo assim um erro de rede no meio do `repeat` encerra o loop sem botão (o botão só existe em `status == "error"`).

`retry` não chama `store` para substituir o item. O card segue “Falha na análise” até um refresh da lista que, acima de 40 itens, não vem sozinho (H6).

Nota aberta ainda dispara dois GETs: `CaptureView` a cada 2 s e `AnalysisView` a cada 5 s, no mesmo id.

**Agora:** uma função de poll (intervalo, teto, o que é terminal, o que fazer com rede) e o retry sempre recolocar `queued`/`processing` e continuar. Escrever o `Reference` novo no store.  
**Depois:** apagar os loops copiados.

### M5 — O que a IA escreveu depende de qual detalhe abriu

**Severidade:** Medium.  
**Evidência:**

- `AnalysisView`: resumo, até 8 tags, limitações, texto da página, transcrição, botão de retry. Usado em nota, imagem e mídia.
- `PostDetailView` (comentário no tipo: “No notes or AI prose”): em processamento, uma linha; senão só chips (`topics + usefulness + entities + appearance`, até 10). Sem `summary`, sem `limitations`.
- `SiteDetailView` e `ProfileDetailView`: o mesmo, sem `appearance`.
- `GalleryDetailView` (caminho padrão de imagem, post com foto, site com foto, vídeo): o resumo vira legenda de até 3 linhas no Mac (`summaryText.lineLimit(3)`), sem status e sem retry. Retry fica em “Editar e ver análise”, que abre `ReferenceDetail`.
- `GalleryDetailView.supports` devolve false para perfil, nota e áudio. Esses três abrem o detalhe completo. O resto com galeria abre o viewer.

Os botões “Space” de post, site e perfil têm `.accessibilityHint("Em breve")` (`PostDetailView`, `SiteDetailView`, `ProfileDetailView`). O botão abre `SpacePicker` de verdade (`ReferenceSpaceButton`). VoiceOver mente. O menu da galeria não tem esse hint.

**Agora:** no viewer, se `status == "error"`, mostrar a falha e o retry sem obrigar “Editar”. Tirar o hint “Em breve”.  
**Depois:** uma vista de análise só.

### L3 — `editMetadata` engole 422 de servidor velho

**Severidade:** Low no TestFlight atual, se a API já aceita título de mídia.  
**Evidência:** `APIClient.editMetadata` transforma `QueepError.invalidCapture` em “Este servidor ainda não aceita editar título e anotações de imagens e mídias.” O comentário diz que post não reenfileira análise. O cliente não distingue 422 de validação de 422 de servidor antigo.

**Agora:** não, se a API do build 6 já aceita o PATCH.  
**Depois:** não remapear todo 422.

---

## 4. Busca em linguagem natural

O cliente manda uma string. Não há ranking, embedding nem prompt aqui. `APIClient.search` faz `POST v1/search` com `query` e `space_id` opcional, timeout 90 s, tamanho 2…500. A resposta (`SearchResults`) traz `items`, `hasPending` e `candidateLimit`. A UI usa `items`. `candidateLimit` não é lido em lugar nenhum. `hasPending` só é lido por uma view que não está na tela.

### H8 — O refresh da biblioteca apaga resultado de busca

**Severidade:** High. Explica “achei e sumiu” sem falar da qualidade do modelo.  
**Onde:** iOS e Mac. O timer de 4 s (B2/H6) chama `LibraryStore.refresh`.  
**Evidência:** se `searchItems` não é nil, cada item que também está na página recém-baixada só permanece se `revision` for a mesma **e** `status == "ready"`. Caso contrário vira `nil` e sai da lista. Item fora dessa página fica. Análise que termina (revisão sobe, ou status passa de `processing` para `ready` com revisão nova) remove o hit. Item ainda na fila também sai, se estiver na página.

`discardSearchReference` na exclusão/edição tira o id e não busca de novo.

**Agora:** atualizar o hit com o `Reference` novo; não remover porque a revisão mudou ou porque ainda não está `ready`.  
**Depois:** —

### H9 — A UI de “conversa com a IA” não está ligada, e o erro real é descartado

**Severidade:** High.  
**Evidência:** `SearchHeader` em `LibraryView.swift` (esqueleto, “Interpretando…”, “N referências conferidas por IA”, aviso de `hasPending`, botões Buscar/Limpar) não tem call site. O README ainda descreve essa conversa.

O que aparece:

- Mac: `HomeSearchField` no header (`MacHome.swift`). Submit manda `LibraryStore.search`. Chips abaixo do campo.
- iOS: a lupa troca o tab bar pelo campo (`MobileLibraryNav`, modo `.search`). No submit o modo volta para `.standard` e o campo some. Os chips ficam na faixa de cima (`iPhoneLibrary`).

`LibraryView`, ramo `store.searchError != nil`, mostra “Não foi possível buscar” / “Tente novamente em instantes.” O `searchError` (texto do `QueepError`, inclusive cota e “2 a 500 caracteres”) não entra na tela. 402 ainda abre o paywall pelo `onPlanRequired`, e por baixo fica o vazio genérico.

Filtro de tipo é client-side depois da API (`LibraryView.filtered`). Uma busca que voltou sites, com filtro “Imagens”, cai em “Nenhuma correspondência entre os candidatos analisados” mesmo com hits de outro tipo.

Vários chips viram **uma** query: `searchChips.joined(separator: ", ")`. Não são filtros. Arquivados nem chamam `v1/search`: `LibraryStore.search` filtra a página carregada por título, `displayTitle` e URL, sem acento.

**Agora:** mostrar `searchError`; não dizer “candidatos analisados” quando o filtro local zerou a lista; mostrar `hasPending` em algum lugar vivo (o texto já está escrito no `SearchHeader`).  
**Depois:** decidir se a conversa do README volta ou se o README é que está velho. Qualidade do ranking é API, fora deste repo. `candidateLimit` ou entra na UI ou sai do decode se a API puder omitir — hoje o decode exige o campo (`SearchResults`).

### M6 — Busca no Space e na conta grande

**Severidade:** Medium.  
**Evidência:** `client.search(term, spaceID: scopedSpaceID)` manda o Space só na aba Spaces com um space selecionado (`LibraryStore.scopedSpaceID` / `filterKey`). Home busca a conta. Não há paginação de busca; a biblioteca pagina com `next_cursor` e lotes de 18 (`GalleryPaging.batch`). O cliente não pede a “próxima página” de busca.

**Agora:** não prometer no onboarding que a busca vê o acervo inteiro se a API corta candidatos. O hint do primeiro item (`onboarding.searchHint`) diz para buscar “pelo nome ou, depois da análise, pelo assunto”. Isso é cópia, não garantia.  
**Depois:** se a API expuser cursor ou `candidateLimit`, a UI precisa dizer que olhou um recorte.

### L4 — Campo “Limpar” do header morto e o `didSet` de `query`

**Severidade:** Low.  
**Evidência:** `LibraryStore.query.didSet` chama `clearSearch()` quando o texto muda e não há chips. Com chips, editar o campo não limpa o resultado até um submit. O botão “Limpar” que zera `query` está só no `SearchHeader` morto. No Mac/iOS vivos, limpar é remover chip (`removeSearchChip`), que busca de novo se ainda sobrar chip.

**Agora:** não.  
**Depois:** junto com H9.

---

## 5. Rede, auth e outros pontos frágeis

### M7 — 429 e 403 usam a frase de indisponibilidade

**Severidade:** Medium.  
**Evidência:** `APIClient.request`, casos `403, 413, 415, 429`: se o JSON não tiver `detail`, a mensagem é “Serviço temporariamente indisponível. Tente novamente.” Cota de busca estourada em 429 fica igual a queda. 402 com corpo inválido vira “Confira seu plano em Conta → Assinatura.” sem abrir paywall (`onPlanRequired` só roda se o `PlanRequirement` decodar).

Sentry: `APIDiagnostics.shouldReport` manda 5xx e erro de transporte. 401, 402, 403, 404, 409, 422, 429 não. Isso está coberto em `DiagnosticTests`.

**Agora:** 429 com cópia de limite, se a API não mandar `detail`.  
**Depois:** —

### M8 — Extensão de compartilhamento é inbox, sem Space e sem análise

**Severidade:** Medium. iOS only. Não há extensão no target Mac (`project.yml`: `QueepShare` embedado em `QueepiOS`).  
**Evidência:** `ShareViewController` / `ShareView`. Sem conta compartilhada no keychain, pede para abrir o app. Mídia passa por `requireMediaAccess` (sem RevenueCat na extensão). Sucesso chama `context.completeRequest` na hora; não espera `ready`. Space fica para depois — o README cita isso como escopo da GAZ-116. Áudio/vídeo/atalho/ilha do notch não existem no iPhone; fotos da biblioteca (`PhotosPicker`, `LibraryView.sendGalleryPhoto`) não existem no Mac.

`Session.finishSetup` só chama `useUserAccessGroup` em `#if os(iOS)`. O Mac não precisa da extensão; o grupo está no entitlements dos dois (`Config/iOS.entitlements`, `Config/Mac.entitlements`) com sufixos `.local` / `.dev` / produção via `QUEEP_AUTH_GROUP`.

**Agora:** testar no aparelho o fluxo que o `QUALITY.md` ainda lista como pendente: compartilhar link, imagem e um vídeo acima do plano, com o app já logado. O próprio `QUALITY.md` diz que o iPhone da rodada de acessibilidade estava bloqueado.  
**Depois:** Space na extensão, se a GAZ-116 deixar.

### L5 — Orientação e “Queep things”

**Severidade:** Low.  
**Evidência:** `project.yml` do iOS libera portrait, upside down e os dois landscapes. O Mac força canvas claro (`RootView.preferredColorScheme(.light)`), igual ao iOS. O botão de adicionar no Mac se chama “Queep things” (`MacLibraryHeader`, identifier `library.add`). A cópia de filtro vazio repete “Queep things guarda o próximo.” (`LibraryView`).

**Agora:** não, a menos que o nome da marca no botão principal do Mac esteja errado para a loja.  
**Depois:** travar orientação se o layout não foi feito para landscape.

---

## 6. Código morto ou superado

| O quê | Onde | Nota |
| --- | --- | --- |
| `SearchHeader` | `LibraryView.swift` | A busca “em conversa” do README. Sem call site. `hasPending` mora aqui. |
| `candidateLimit` | `Reference.swift` `SearchResults` | Decodifica, ninguém lê. |
| Avatar | `APIClient` | Sem UI. |
| Hint “Em breve” | Post, site, perfil | O Space abre. |
| `FeedNotice` | DEBUG | Lembrete de feed sem Family Controls. |
| Dois pollers na nota | `CaptureView` + `AnalysisView` | O de 2 s e o de 5 s no mesmo id. |
| `ImageDetailView` / `MediaDetailView` / `PostDetailView` como destino direto | `ReferenceDetail` | Ainda são o “Editar e ver análise” e o fallback quando `GalleryDetailView.supports` é false. Não estão mortos. A galeria é que passou a ser o caminho principal (commit `fcf0681`, “Saved-style gallery”). |
| Mapa `yearly` / `monthly` | `SubscriptionStore.plan`, `#if DEBUG` | Fixture da Test Store. O script de Release/TestFlight barra chave `test_`. Não entra no archive de loja. |

Não achei `#if false`, `TODO`/`FIXME` nem handler vazio de botão. Os `fatalError` de `init(coder:)` são de view que não vem de storyboard.

---

## 7. iOS e macOS — o que não é o mesmo produto

O núcleo (`LibraryStore`, `APIClient`, `SubscriptionStore`, `AccountView`, busca, análise) é compartilhado. A diferença que o usuário vê:

| | iPhone | Mac |
| --- | --- | --- |
| Busca | Modo da barra; o campo fecha ao enviar | Campo fixo de 400 pt no header |
| Abrir item com imagem | Sheet | Overlay em cima da biblioteca (`macGallery`) |
| Seleção em massa por arraste | `SelectionBrush` | Não |
| Fotos do sistema direto na biblioteca | `PhotosPicker` | Não; arquivo / captura |
| Compartilhar de outro app | Extensão `QueepShare` | Não |
| Captura de tela, atalho, notch | Não | `ScreenCapture`, `GlobalShortcut`, `NotchIsland` |
| Login no arranque | Não | `QueepMacApp` / ServiceManagement |
| Grupo de auth no `Session` | `useUserAccessGroup` | Não é chamado |
| Paywall, Ajustes, retry, `GET v1/account` | Iguais | Iguais |

Testes de UI de RevenueCat (`RevenueCatTests`, `RevenueCatCrossDeviceTests`) começam com `XCTSkip` pedindo fixture local. Não são rede de segurança do build 6.

---

## Linha de corte

### Tem que ir no próximo TestFlight / build de loja

1. **Sessão.** `handleUnauthorized` no timer de 4 s não pode dar `signOut` em timeout, offline ou 5xx de `GET v1/account`. Só conta inativa ou 401 de verdade. (B2)
2. **Cobrança.** Upgrade Pro → Max chama `purchase` também em `SubscriptionView`. Trial não diz “de Pro” / “por ano” para o pacote errado. Paywall do primeiro save só marca “visto” depois das ofertas. Um sandbox nos dois bundle IDs, com a mesma conta, até a API confirmar o plano. (B1, H1, H2, M1)
3. **Análise.** Sem o teto cego de 40 itens enquanto algo está `queued`/`processing` ou o detalhe está aberto. Retry recoloca o poll e atualiza o card. Falha de rede no poll não congela “Analisando” para sempre. (H6, H7)
4. **Busca.** O refresh não remove hit porque a revisão mudou. A tela mostra o erro que a API mandou, e `hasPending` aparece. (H8, H9)
5. **Ajustes.** Assinatura, uso, ajuda e excluir voltam para a lista. A linha de assinatura mostra o plano. Erro de e-mail/senha não diz “não foi possível entrar”. (H4, H5, M3)
6. **Extensão no aparelho**, uma vez, logado: link, imagem, vídeo sem Max. O `QUALITY.md` ainda trata isso como não feito no device. (M8)

### Pode esperar

- Unificar as duas folhas de paywall e ler cotas da API (H3), se o upgrade e o sandbox passaram.
- Avatar, Family Controls, Space dentro da extensão, hint “Em breve”, “Queep things”, `SearchHeader` morto, `candidateLimit`.
- Qualidade do ranking semântico em si. Este repositório só manda a string e desenha `items`. Ajuste de modelo é o outro repo.
- Paginação de busca, busca semântica em arquivados, filtro de tipo no servidor.
- Uma única vista de análise no lugar de `AnalysisView` + post + site + perfil. Para o corte, basta o viewer não esconder falha e retry.
- Orientação landscape e sessão/aparelhos (não existe).

### Fora deste cliente

Confirmar na API do build 6: corpo do 402, `hasPending`, se `candidateLimit` é obrigatório, se terminar a análise muda `revision`, e se `POST v1/billing/sync` enxerga compra feita no outro bundle ID. O cliente já está escrito em cima dessas suposições.
