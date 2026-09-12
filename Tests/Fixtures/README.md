# Mídia sintética de teste

- `sample-audio.wav`: voz sintetizada em português descrevendo o projeto fictício
  Aurora, que organiza clipes de jogos e sugere títulos. Menciona uma interface com
  fundo escuro, botões brancos e tabela de partidas.
- `sample-video.mp4`: vídeo H.264 com fundo azul escuro e narração sobre o mesmo
  projeto. **Nenhuma interface, botão ou tabela aparece nas imagens.**

Gerados localmente com voz do macOS e FFmpeg; não contêm gravação de pessoa real
nem conteúdo da biblioteca do usuário. As durações são curtas e diferentes.
Servem para testar reprodução, transcrição e a distinção entre fala e aparência.
São recursos apenas dos targets de teste; não acompanham os aplicativos.

`sample-image.jpg`: JPEG sintético de 900×600 gerado localmente (fundo amarelo e um bloco escuro; JPEG porque o Xcode reescreve PNGs do bundle iOS no formato CgBI, que a API não aceita), usado por `ImageEditTests` para editar título/anotações e excluir uma imagem em contas descartáveis dos emuladores.
