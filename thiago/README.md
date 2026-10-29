# Zelda: Breath of the Wild no Mac (port nativo)

Port nativo de Breath of the Wild para Mac, feito sobre o método [MacNativeGames](https://github.com/ly05010419/MacNativeGames) (o código ARM64 do jogo roda direto no Apple Silicon, gráficos NVN em Metal), com os ajustes abaixo. Este repositório
não tem nada do jogo: os arquivos do jogo e as chaves ficam fora dele (veja "O que guardar fora do GitHub").

## O que guardar fora do GitHub

Sem isto não dá para compilar. Tudo vem do seu próprio Switch:

- `The Legend of Zelda Breath of the Wild [01007EF00011E000][v0].nsp`: o jogo base
- `The Legend of Zelda Breath of the Wild [01007EF00011E800][v786432].nsp`: o update 1.6.0
- `... [DLC Pack 1 The Master Trials] [01007EF00011F001][v196608].nsp` e `... [DLC Pack 2 The Champions Ballad] [01007EF00011F002][v196608].nsp`
- `prod.keys` (e `title.keys`) e o firmware (`Firmware.22.5.0`)
- os saves: `~/Library/Application Support/MacNativeGames/BotW/profile/save/`

## Compilar do zero

Requisitos: macOS em Apple Silicon, Xcode completo, Python 3.14. O README principal explica as dependências.

```sh
git clone https://github.com/opsiscv/zelda-botw-mac-native.git ~/Games/MacNativeGames-BOTW
cd ~/Games/MacNativeGames-BOTW && git checkout thiago-botw

G="$HOME/Downloads/Games/Zelda BOTW"; W="$G/basegame/BotW_build"
python3.14 build_app.py "$G/basegame/The Legend of Zelda Breath of the Wild [01007EF00011E000][v0].nsp" \
  -k "$HOME/Downloads/Games/Switch /prod.keys" \
  --update "$G/update/The Legend of Zelda Breath of the Wild [01007EF00011E800][v786432].nsp" \
  --dlc "$G/dlc/The Legend of Zelda Breath of the Wild [DLC Pack 1 The Master Trials] [01007EF00011F001][v196608].nsp" \
  --dlc "$G/dlc/The Legend of Zelda Breath of the Wild [DLC Pack 2 The Champions Ballad] [01007EF00011F002][v196608].nsp" \
  --shared-fonts "$W/totk/extracted/firmware/shared-fonts" --work "$W" -o "/Applications/Breath of the Wild.app"
```

O app vai para /Applications: dentro de Downloads o macOS pede permissão de pasta a cada recompilação.

Depois de mudar só o código (sem trocar os arquivos do jogo), o caminho rápido, com o jogo fechado:

```sh
pkill -f "totk-native rewritten"; python3 update_runtime.py "/Applications/Breath of the Wild.app" --work "$W"
```

## Controles

Copie `controls.txt` para `~/Library/Application Support/MacNativeGames/BotW/controls.txt` (botões do mouse; o modo
mouse liga na tecla 1, no painel de ajustes). O teclado está no código (`games/totk/runtime/input.c` e `frontend.m`).

- No mundo: E interage (A), Ctrl arremessa (R), Shift corre, botão direito do mouse puxa o arco e o esquerdo atira,
  botão do meio arremessa, esquerdo ataca e, com uma runa na mão, usa a runa (A).
- Nas cenas: Espaço pula (manda X e + juntos; se o jogo perguntar, Enter confirma).
- Nos menus: Enter e Espaço confirmam, Esc volta e fecha; E e Shift não fazem nada, exceto E, que vai para a próxima aba no
  inventário e no diário (Q volta). O mouse aponta e clica (esquerdo confirma, direito volta).

## Armas inquebráveis

Dois passos (o primeiro vale para armas novas, o segundo para as que já estão no save):

```sh
python3 thiago/scripts/durability_mod.py      # mod de dados: Life 1000000 (o jogo limita a 65535) em armas, arcos e escudos
python3 games/totk/scripts/make_mod_manifest.py "$HOME/Library/Application Support/MacNativeGames/BotW/mods/botw160" \
  --app "/Applications/Breath of the Wild.app" --version botw160
# com o jogo fechado e um backup da pasta save:
python3 thiago/scripts/savefix.py "$HOME/Library/Application Support/MacNativeGames/BotW/profile/save/"*/[0-5]/game_data.sav
```

`savescan.py <game_data.sav>` lista as armas do save e a durabilidade de cada uma (em centésimos). As armas novas da DLC
não estão no mod (ficam em outro pacote).

## Outros ajustes deste fork

- Sem o quadro preto ao abrir a barra de armas ou o inventário (`games/totk/third_party/d2r_gfx/gfx/nvn/present_hold.h`).
- Cavalo com WASD, câmera livre a cavalo, Esc abre o menu e Tab o mapa, roda do mouse nas abas do diário.
- `scripts/launch_manual.sh`: abre uma sessão de teste no save manual (com log em `~/Library/Logs/MacNativeGames/botw.log`).

## Créditos

Todo o port (o carregador do jogo, o NVN em Metal, o áudio, os patches do jogo e as ferramentas de compilação) é do
projeto [MacNativeGames](https://github.com/ly05010419/MacNativeGames), dos seus contribuidores
(licença MIT: `LICENSE`; componentes de terceiros: `THIRD_PARTY_NOTICES.md`). Este repositório é um fork dele, com
os ajustes listados acima. A engenharia reversa se apoia também no decomp [zeldaret/botw](https://github.com/zeldaret/botw).
