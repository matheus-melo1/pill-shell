# pill

Shell para Hyprland feito em [Quickshell](https://quickshell.org): uma pílula no topo da tela que se transforma em painéis (launcher, mixer, Wi‑Fi/Bluetooth, calendário, clipboard, wallpaper, energia, mídia) e uma **drawer lateral** que desliza pela direita com as integrações (GitHub, VPN, notificações, tarefas, disco, celular e chat com IA).

> Status: uso pessoal, repositório privado. Algumas integrações ainda têm valores fixos da máquina original. Veja [Ajustes para a sua máquina](#ajustes-para-a-sua-máquina).

---

## Pré-requisitos

### Obrigatórios

| Pacote | Para quê |
|---|---|
| **Hyprland** | compositor; a pill usa `Quickshell.Hyprland` para monitores e workspaces |
| **quickshell ≥ 0.3** | o runtime do shell (`qs`) |
| **qt6-declarative**, **qt6-svg** | QtQuick, efeitos (`MultiEffect`), shapes e ícones SVG |
| **python3** | scripts de status em `scripts/` (só usam a biblioteca padrão, exceto o celular) |
| **jq** | os atalhos usam `hyprctl ... \| jq` para descobrir o monitor focado |
| **PipeWire** + **WirePlumber** | mixer de áudio (`Quickshell.Services.Pipewire`) |
| **Fonte Inter** | fonte da interface (`Theme.font`) |

No Arch / CachyOS:

```bash
sudo pacman -S hyprland quickshell qt6-declarative qt6-svg \
               python jq pipewire wireplumber inter-font
```

> O `quickshell` está no repositório `extra` do Arch. Em outras distros, siga a [instalação oficial](https://quickshell.org/docs/guide/install-setup/).

### Opcionais (por funcionalidade)

Cada integração depende de ferramentas próprias. Sem elas a pill sobe normalmente, mas aquele painel fica vazio ou sem ação.

| Funcionalidade | Precisa de |
|---|---|
| Wi‑Fi / hotspot | `networkmanager` (`nmcli`) |
| Bluetooth | `bluez`, `bluez-utils` (`bluetoothctl`) |
| Bateria | `upower` |
| Player de mídia | qualquer player com MPRIS (Spotify, mpv + `mpv-mpris`, navegador) |
| Clipboard | `cliphist`, `wl-clipboard` |
| Wallpaper | `awww`, `wallust` e o script `~/.config/hypr/scripts/wallpaper.sh` |
| Captura de região no chat de IA | `grim`, `slurp` |
| Brilho de monitor externo | `ddcutil` (e o módulo `i2c-dev` carregado) |
| Vibrance (NVIDIA) | `nvibrant` (AUR) |
| GitHub (drawer) | `github-cli` (`gh`) logado com `gh auth login` |
| Sessões / review do Claude Code | `claude` (Claude Code CLI) e `tmux` |
| Chat com IA | chave da OpenRouter (ou CodeCraft), veja abaixo |
| VPN | `openvpn` com um unit `openvpn-client@<nome>` no systemd |
| Celular | `kdeconnect` pareado + `python-dbus` |
| Fonte japonesa (relógio) | `ttf-zen-kaku-gothic-new` (AUR), opcional |

Tudo de uma vez no Arch:

```bash
sudo pacman -S networkmanager bluez bluez-utils upower cliphist wl-clipboard \
               grim slurp ddcutil github-cli tmux openvpn kdeconnect python-dbus awww
paru -S wallust nvibrant ttf-zen-kaku-gothic-new   # AUR, se quiser
```

---

## Instalação

### 1. Clonar no diretório do Quickshell

O nome da pasta precisa ser `pill`: é ele que o `qs -c pill` procura.

```bash
mkdir -p ~/.config/quickshell
git clone git@github.com:matheus-melo1/pill-shell.git ~/.config/quickshell/pill
```

### 2. Testar

Rode em primeiro plano para ver erros no terminal:

```bash
qs -c pill
```

A pílula deve aparecer no topo de cada monitor. `Ctrl+C` encerra.

### 3. Desligar o que a pill substitui

A pill é **servidor de notificações** e **barra**. Se rodar junto com outro, os dois brigam:

- **Notificações:** pare `swaync`, `mako` ou `dunst`. Se o D-Bus continuar reativando o daemon, mascare-o:
  ```bash
  systemctl --user mask --now swaync.service
  ```
  Tire também o `exec-once` correspondente da config do Hyprland.
- **Barra:** desative Waybar ou similar. No ML4W, crie o arquivo `~/.config/ml4w/settings/waybar-disabled`.

### 4. Autostart e atalhos

Copie o exemplo e inclua no seu `hyprland.conf`:

```bash
cp ~/.config/quickshell/pill/examples/hyprland.conf ~/.config/hypr/pill.conf
echo 'source = ~/.config/hypr/pill.conf' >> ~/.config/hypr/hyprland.conf
hyprctl reload
```

O exemplo inclui o `exec-once = qs -c pill -d` e os atalhos abaixo. Revise antes, porque alguns podem conflitar com os seus (por exemplo `Super+V` e `Super+N`).

### 5. Configurar as integrações que for usar

**GitHub**
```bash
gh auth login
```

**Chat com IA** (a chave fica num arquivo, nunca no código):
```bash
mkdir -p ~/.local/share/pill
printf '%s' 'sk-or-...' > ~/.local/share/pill/openrouter.key
chmod 600 ~/.local/share/pill/openrouter.key
```
Para usar o CodeCraft, salve em `codecraft.key`. Para forçar um provedor, use `PILL_AI_PROVIDER=openrouter`.

**Celular:** pareie o telefone pelo app KDE Connect antes. A pill usa o primeiro dispositivo pareado.

---

## Atalhos padrão

| Atalho | Abre |
|---|---|
| `Super+Ctrl+Enter` | Launcher |
| `Super+V` | Clipboard |
| `Super+C` | Wallpaper |
| `Super+N` | Calendário |
| `Super+M` | Mixer |
| `Super+/` | Wi‑Fi / Bluetooth |
| `Super+P` | Energia |
| `Super+Ctrl+C` | Claude Code |
| `Super+Ctrl+D` | Nova tarefa |
| `Super+Ctrl+G` | Drawer: GitHub |
| `Super+Ctrl+V` | Drawer: VPN |
| `Super+Ctrl+N` | Drawer: notificações |
| `Super+Ctrl+A` | Drawer: chat com IA |
| `Super+Ctrl+Shift+D` | Drawer: tarefas |
| `Super+Ctrl+F` | Drawer: disco |

`Esc` ou um clique fora fecha qualquer painel. Repetir o atalho também fecha.

Tudo é exposto via IPC, então dá para ligar a outros atalhos ou scripts:

```bash
qs -c pill ipc show                          # lista as funções disponíveis
qs -c pill ipc call pill github DP-1         # abre a drawer do GitHub no monitor DP-1
qs -c pill ipc call pill hide                # fecha a surface aberta
```

---

## Ajustes para a sua máquina

Hoje estes valores estão no código. Se for usar a integração, edite o arquivo:

| Arquivo | Valor | O que é |
|---|---|---|
| `scripts/github-status.py`, `scripts/github-issue.py` | `BOARD_ORG = "Tecware-Bizpik"` | org do GitHub Project mostrado como board |
| `Singletons/GitHub.qml` (`defaultAccount`) | prefixo `"tecware"` | repositórios dessa org usam a conta "work" |
| `Singletons/Vpn.qml`, `scripts/vpn-status.py` | `openvpn-client@cliente`, `/etc/openvpn/client/cliente.conf` | unit e config da VPN |
| `scripts/claude-status.py` | `~/.claude-personal`, `~/.claude-work` | diretórios das contas do Claude Code |
| `Singletons/Walls.qml` | `~/Ricelin/wallpapers` | pasta de wallpapers |
| `LinkWifi.qml` | `RicelinHotspot` | nome da conexão de hotspot no NetworkManager |
| `Power.qml` | `~/.config/hypr/scripts/lock.sh` | comando de bloquear a tela |
| `Singletons/Cliphist.qml` | `~/.config/hypr/scripts/cliphist-thumbs.sh` | gera miniaturas de imagens do clipboard (sem ele, imagens aparecem sem preview) |

O estado da pill (tarefas, histórico de notificações, flags de Não Perturbe etc.) fica em `~/.local/state/ricelin/`. As chaves de IA ficam em `~/.local/share/pill/` e o cache em `~/.cache/pill-*`.

---

## Estrutura

```
shell.qml            entrada: uma pill + uma drawer por monitor, IPC e estado global
Pill.qml             a pílula do topo e o morph entre surfaces
Drawer.qml           drawer lateral: rail de navegação + views das integrações
*View.qml            conteúdo de cada rota da drawer
Singletons/          estado e serviços compartilhados (Theme, Motion, GitHub, Vpn, Ai...)
scripts/             coletores em Python chamados pelos singletons (saída em JSON)
examples/            config de exemplo para o Hyprland
```

### Adicionando uma rota na drawer

1. Uma entrada em `routes` no `Drawer.qml`: `{ key: "x", label: "X", icon: "..." }`.
2. Uma view dentro de `pane` com `open: drawer.open && drawer.route === "x"`.
3. Uma função no `IpcHandler` do `shell.qml`: `function x(mon: string): void { root.toggleDrawer(mon, "x"); }`.
4. Opcional: um `case` em `routeTint()` para a bolinha de status no rail.

---

## Solução de problemas

- **Nada aparece:** rode `qs -c pill` no terminal e leia os erros. Normalmente é um módulo Qt faltando (`qt6-svg`, `qt6-declarative`).
- **Notificações não chegam na pill:** outro daemon está com o nome `org.freedesktop.Notifications`. Confira com `busctl --user status org.freedesktop.Notifications`.
- **Atalho não faz nada:** teste a chamada direto, `qs -c pill ipc call pill mixer "$(hyprctl activeworkspace -j | jq -r .monitor)"`, e confira se o `jq` está instalado.
- **Recarregar depois de editar:** o Quickshell recarrega sozinho quando um `.qml` muda. Para reiniciar de vez: `pkill -f 'qs -c pill'; qs -c pill -d`.
