# Imagens do ticker de entrada

As 44 fotos em `Sources/Shared/Ticker/` aparecem no carregamento, no login e no paywall
(`ReferenceTicker`). Todas vieram do Unsplash em 06/10/2026, filtradas por licença gratuita
(sem Unsplash+), e foram recortadas e reduzidas para 440 px de largura.

A [licença do Unsplash](https://unsplash.com/license) permite uso comercial sem atribuição.
Ela não cobre marcas, obras de terceiros nem direito de imagem de pessoas que apareçam na foto.
Por isso a seleção evitou rostos identificáveis e embalagens de marca, e uma foto teve o recorte
ajustado para tirar um logotipo (`dashboard`). Os dois cartazes são do acervo da Library of
Congress (WPA, domínio público).

Para trocar uma imagem: substitua o arquivo `ticker-<nome>.jpg` mantendo a proporção indicada,
ou altere a entrada em `TickerCatalog` (`Sources/Shared/ReferenceTicker.swift`) e esta tabela.
Depois de adicionar ou remover arquivos, rode `xcodegen generate`.

| Arquivo | Proporção | Autor no Unsplash | Foto |
|---|---|---|---|
| `ticker-design-swatches.jpg` | 4:5 | [@balazsketyi](https://unsplash.com/@balazsketyi) | https://unsplash.com/photos/LPWl2pEVGKc |
| `ticker-design-system.jpg` | 3:4 | [@balazsketyi](https://unsplash.com/@balazsketyi) | https://unsplash.com/photos/_x335IZXxfc |
| `ticker-icon-set.jpg` | 4:5 | [@balazsketyi](https://unsplash.com/@balazsketyi) | https://unsplash.com/photos/U008D4Jp2CY |
| `ticker-dashboard.jpg` | 4:5 | [@danielkorpai](https://unsplash.com/@danielkorpai) | https://unsplash.com/photos/iopITwyUcTA |
| `ticker-app-orange.jpg` | 3:4 | [@danielkorpai](https://unsplash.com/@danielkorpai) | https://unsplash.com/photos/aUmq85-2V7I |
| `ticker-app-dark.jpg` | 4:5 | [@danielkorpai](https://unsplash.com/@danielkorpai) | https://unsplash.com/photos/2nxugQEgsOc |
| `ticker-app-gradients.jpg` | 9:16 | [@typerium](https://unsplash.com/@typerium) | https://unsplash.com/photos/0-hAKXukW_s |
| `ticker-wireframes.jpg` | 9:16 | [@fazurrehman](https://unsplash.com/@fazurrehman) | https://unsplash.com/photos/dJpupM4LiS4 |
| `ticker-brand-cards.jpg` | 1:1 | [@alphabag](https://unsplash.com/@alphabag) | https://unsplash.com/photos/dqGbTgRpLYw |
| `ticker-hibiscus.jpg` | 2:3 | [@_coldgrain](https://unsplash.com/@_coldgrain) | https://unsplash.com/photos/t7itPRh7Kkg |
| `ticker-water.jpg` | 1:1 | [@abyanathif](https://unsplash.com/@abyanathif) | https://unsplash.com/photos/K0U0eSAjFGU |
| `ticker-hands-sky.jpg` | 3:4 | [@sharonros](https://unsplash.com/@sharonros) | https://unsplash.com/photos/iUmQbuiIb0Q |
| `ticker-jacket-truck.jpg` | 4:5 | [@parikarra](https://unsplash.com/@parikarra) | https://unsplash.com/photos/elK1z1WcsR8 |
| `ticker-ceramics.jpg` | 3:4 | [@wariontaipei](https://unsplash.com/@wariontaipei) | https://unsplash.com/photos/8QIAj5tHDdc |
| `ticker-journal.jpg` | 4:5 | [@esteejanssens](https://unsplash.com/@esteejanssens) | https://unsplash.com/photos/MUf7Ly04sOI |
| `ticker-tulips.jpg` | 2:3 | [@ksanarts](https://unsplash.com/@ksanarts) | https://unsplash.com/photos/BxK2qcVU35E |
| `ticker-yellow-dress.jpg` | 9:16 | [@goh](https://unsplash.com/@goh) | https://unsplash.com/photos/FO-zQd7Wqio |
| `ticker-blazer.jpg` | 4:5 | [@chyntiajuls](https://unsplash.com/@chyntiajuls) | https://unsplash.com/photos/HlVjI5WmoQY |
| `ticker-sunglasses.jpg` | 3:4 | [@ethanhaddox](https://unsplash.com/@ethanhaddox) | https://unsplash.com/photos/wBgG_tj-sq8 |
| `ticker-streetwear.jpg` | 9:16 | [@ghafouripic](https://unsplash.com/@ghafouripic) | https://unsplash.com/photos/RxBnnZ2vxZc |
| `ticker-sneakers-color.jpg` | 4:5 | [@ikredenets](https://unsplash.com/@ikredenets) | https://unsplash.com/photos/dwKiHoqqxk8 |
| `ticker-sneaker-orange.jpg` | 1:1 | [@fahiminia](https://unsplash.com/@fahiminia) | https://unsplash.com/photos/t4g1gctAaKk |
| `ticker-stairs.jpg` | 3:4 | [@coohom](https://unsplash.com/@coohom) | https://unsplash.com/photos/5MG8cQbw-T8 |
| `ticker-arch.jpg` | 4:5 | [@insideweather](https://unsplash.com/@insideweather) | https://unsplash.com/photos/Uxqlfigh6oE |
| `ticker-console.jpg` | 1:1 | [@kaboompics](https://unsplash.com/@kaboompics) | https://unsplash.com/photos/ulh3-dLSXjI |
| `ticker-chair-window.jpg` | 2:3 | [@yoyoand](https://unsplash.com/@yoyoand) | https://unsplash.com/photos/WpQIcQrZ5TI |
| `ticker-poster-science.jpg` | 2:3 | [@libraryofcongress](https://unsplash.com/@libraryofcongress) | https://unsplash.com/photos/ngyHhFNgIZw |
| `ticker-poster-exhibition.jpg` | 2:3 | [@libraryofcongress](https://unsplash.com/@libraryofcongress) | https://unsplash.com/photos/gIawC7CDcSg |
| `ticker-geometric.jpg` | 3:4 | [@maxberg](https://unsplash.com/@maxberg) | https://unsplash.com/photos/sURsAcl9eQQ |
| `ticker-numeral.jpg` | 4:5 | [@deefbelgium](https://unsplash.com/@deefbelgium) | https://unsplash.com/photos/zcZ7rIUJwT0 |
| `ticker-gradient-print.jpg` | 3:4 | [@dariadurand](https://unsplash.com/@dariadurand) | https://unsplash.com/photos/IapYO40ZHaQ |
| `ticker-glass-purple.jpg` | 9:16 | [@fakurian](https://unsplash.com/@fakurian) | https://unsplash.com/photos/mFaWic9EvBU |
| `ticker-soft-layers.jpg` | 3:4 | [@theshubhamdhage](https://unsplash.com/@theshubhamdhage) | https://unsplash.com/photos/NPJF9xPoCHk |
| `ticker-glass-grid.jpg` | 4:5 | [@fakurian](https://unsplash.com/@fakurian) | https://unsplash.com/photos/3iFOosUelfk |
| `ticker-metal-waves.jpg` | 9:16 | [@zacong](https://unsplash.com/@zacong) | https://unsplash.com/photos/V3j7yy3CzqU |
| `ticker-copper.jpg` | 3:4 | [@brewcat](https://unsplash.com/@brewcat) | https://unsplash.com/photos/yEkRzLjW118 |
| `ticker-concrete.jpg` | 4:5 | [@heysupersimi](https://unsplash.com/@heysupersimi) | https://unsplash.com/photos/ItvVUpgac0o |
| `ticker-curves.jpg` | 3:4 | [@iltunography](https://unsplash.com/@iltunography) | https://unsplash.com/photos/rfklsTwIYBM |
| `ticker-towers.jpg` | 4:5 | [@adriancuj](https://unsplash.com/@adriancuj) | https://unsplash.com/photos/o_9YmCY0bag |
| `ticker-tower-dusk.jpg` | 2:3 | [@parrish](https://unsplash.com/@parrish) | https://unsplash.com/photos/Wi_Kun_mstU |
| `ticker-magazine.jpg` | 3:4 | [@n_0351](https://unsplash.com/@n_0351) | https://unsplash.com/photos/zpsN9hcrIw4 |
| `ticker-palm-hotel.jpg` | 4:5 | [@nikita_pishchugin](https://unsplash.com/@nikita_pishchugin) | https://unsplash.com/photos/D4wi3gZrq4U |
| `ticker-umbrellas.jpg` | 3:4 | [@hannahinacio](https://unsplash.com/@hannahinacio) | https://unsplash.com/photos/yDBjliiSwys |
| `ticker-film-temple.jpg` | 2:3 | [@rex_filmer](https://unsplash.com/@rex_filmer) | https://unsplash.com/photos/6kp-Dg72NC4 |
