# Qualidade e limites

- **Uso e privacidade:** cotas reais e renovação no horário local; explicação da
  nuvem/IA, captura explícita e recuperação de conta. A política pública final
  e as informações de privacidade das lojas continuam na etapa de publicação.
- **Acessibilidade:** biblioteca com avisos dentro da rolagem; coluna única com
  texto acessível; contraste reforçado, alvos de toque e títulos sem corte;
  captura com seletor adaptado e título multilinha. Botões de toolbar têm nomes
  acessíveis; Escape fecha captura/uso no Mac.
- **Estabilidade e privacidade local:** arquivos temporários liberados ao fechar;
  arquivos do Queep abandonados por mais de 24 h são removidos no próximo início.
  A limpeza ignora arquivos recentes, de outros nomes e links simbólicos.

## Validação

8 testes de importação/captura e 3 testes do núcleo Swift passaram. Testes de
interface cobrem uso, captura por teclado, primeiro salvamento e áudio/vídeo.
Builds de desenvolvimento Mac, simulador e iPhone físico foram produzidos.

As auditorias com texto padrão/claro e máximo/escuro passaram. Uso cloud conferido
pela interface do Mac; biblioteca preservada nos dois apps, incluindo os cinco itens
presentes na conferência final. O iPhone físico recebeu o build final assinado.

Logs finais em `/tmp/queep-quality-{light-tests-3,large-final-tests,mac-final-tests}.log`.
Importação e núcleo: `/tmp/queep-quality-capture-tests.log` e
`/tmp/queep-quality-core-tests.log`. Reprodução: `/tmp/queep-quality-light-tests.log`
(a reprodução passou; os ajustes restantes da auditoria estão nas rodadas finais).

`QualityTests` usa a [auditoria de acessibilidade do XCTest](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
em primeiro uso, biblioteca, uso e captura. Compara texto padrão/tema claro e
o maior texto acessível/tema escuro. O teste ignora apenas falhas de contraste
em elementos fora da tela ou cortados pela rolagem, que o iOS 26 também inclui
na auditoria; traz ações para a área visível antes de avaliá-las.

Isso não substitui uma sessão completa com VoiceOver. Antes do beta ainda precisam
ser conferidos VoiceOver, múltiplos monitores, início no login e compartilhamento
em aparelho físico. O iPhone 16 pareado recebeu o app, mas estava bloqueado durante
esta rodada; não registrar isso como teste físico completo.

RevenueCat e App Store Connect permanecem adiados por decisão do usuário.

`RedesignSnapshotTests` (Mac e iPhone) é opt-in com `TEST_RUNNER_QUEEP_SNAPSHOTS=1`: em uma biblioteca já conectada, captura biblioteca, busca digitada sem enviar (Mac), um detalhe aberto (Mac) e um rascunho Markdown sem salvar. Não cria, não altera e não busca; serve para conferir a interface com dados reais.
