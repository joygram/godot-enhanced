# Linux Japanese input (Mozc) — verification

- Engine change: none
- Tests: [`ime-linux.sh`](../misc/scripts/agent_tests/ime-linux.sh) (X11), [`ime-wayland.sh`](../misc/scripts/agent_tests/ime-wayland.sh) (Wayland)
- Run: `node misc/scripts/remote_build.mjs <linux-agent> --test ime-linux,ime-wayland --wait`
- Tools: Xvfb, xdotool, sway, wtype, fcitx5, fcitx5-mozc, dbus-launch

## Report checked

- Godot 4.7.1, Arch, KDE Plasma, fcitx5 + Mozc
- Japanese mode types Latin, `Ctrl+Space` swallowed by Godot

## Method

- Godot `LineEdit` focused, prints `IME_PREEDIT` / `IME_TEXT` / `IME_RESULT`
- Switch to Mozc: `fcitx5-remote -s mozc` (tray) or `Ctrl+Space` (hotkey)
- Type `nihongo`, Return to commit, Return to submit
- Pass = `IME_RESULT:にほんご` exact
- Control: plain Xlib XIM client, same steps

## Result (Ubuntu 24.04, fcitx5 5.1, Mozc)

| Session | Switch | Result |
|---|---|---|
| X11 (Xvfb), XIM | `fcitx5-remote` | `にほんご` ✔ |
| X11 (Xvfb), XIM | `Ctrl+Space` | `にほんご` ✔ |
| Wayland (sway), `text-input-v3` | `fcitx5-remote` | `にほんご` ✔, preedit `にほｎ → にほんご` |
| Wayland (sway), `text-input-v3` | `Ctrl+Space` | `にほんご` ✔, preedit shown |
| Xlib control client | `fcitx5-remote` | `にほんご` |

## Findings

- Godot X11 (XIM) and Wayland (`text-input-v3`) Japanese input works
- `Ctrl+Space` not swallowed: fcitx5 switches to Mozc in both sessions
- First key after the first Mozc use in a session can leak as Latin (`nいほんご`) → Mozc server start-up; gone once Mozc warmed
- Not verified: KDE KWin — headless KWin lacks virtual keyboard protocol, no key injection

## If it fails on your desktop

- KDE Wayland: System Settings → Virtual Keyboard → Fcitx 5
- XWayland / X11: `XMODIFIERS=@im=fcitx` in the session environment
- Force a session: `--display-driver wayland` or `--display-driver x11`
